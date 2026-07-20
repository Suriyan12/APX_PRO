"""
Authentication business logic.

One cohesive service owns the entire account lifecycle:

  register (pending) ──► verify (email OTP | Firebase phone) ──► active ──► login

Design rules:
  * Accounts are created PENDING (is_verified=False, is_active=False) and are
    unusable until one verification channel succeeds. Never both.
  * Email channel: we generate a 6-digit OTP, store only its sha256 hash,
    enforce expiry (10 min), max wrong attempts (5) and resend cooldown (60 s).
  * Phone channel: Firebase Authentication owns the OTP end-to-end. The backend
    stores nothing and trusts only a verified Firebase ID token whose
    phone_number claim matches the account.
  * Password login accepts email OR phone as the identifier.
  * Firebase-OTP login never creates accounts.

Route handlers in app/api/v1/auth.py stay thin and delegate here.
"""
import hashlib
import logging
import random
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    get_password_hash,
    verify_password,
)
from app.models.models import PasswordResetToken, RefreshToken, User, UserRole
from app.schemas.schemas import TokenResponse, UserCreate, UserResponse

logger = logging.getLogger(__name__)

# --- Policy constants -------------------------------------------------------
OTP_TTL_MINUTES = 10
OTP_MAX_ATTEMPTS = 5
OTP_RESEND_COOLDOWN_SECONDS = 60
RESET_TOKEN_TTL_MINUTES = 15

# Client-recognizable prefix: the app routes to the verification screen on it.
NOT_VERIFIED_DETAIL = (
    "ACCOUNT_NOT_VERIFIED: Please verify your account before logging in."
)


# --- Pure helpers ------------------------------------------------------------

def hash_otp(value: str) -> str:
    """One-way hash for OTPs / reset tokens — plain text is never persisted."""
    return hashlib.sha256(value.encode()).hexdigest()


def normalize_e164(phone: str) -> str:
    """9876543210 → +919876543210 (Indian numbers, pass through if already E.164)."""
    phone = phone.strip()
    if phone.startswith("+"):
        return phone
    if phone.startswith("91") and len(phone) == 12:
        return f"+{phone}"
    if len(phone) == 10:
        return f"+91{phone}"
    return phone


def strip_country_code(phone: str) -> str:
    """Match the plain 10-digit format stored in the DB."""
    phone = phone.strip()
    if phone.startswith("+91"):
        return phone[3:]
    if phone.startswith("91") and len(phone) == 12:
        return phone[2:]
    return phone


def _utc(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is not None and dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


class AuthService:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ------------------------------------------------------------------
    # Registration — always creates/updates a PENDING account
    # ------------------------------------------------------------------

    def register(self, user_in: UserCreate) -> Tuple[User, str]:
        """Create (or refresh) a pending account and dispatch verification.

        Returns (user, channel). Pending-account recovery: re-registering an
        email that exists but was never verified updates the pending row and
        re-sends the OTP instead of locking the user out with "already exists".
        """
        channel = (user_in.verification_method or "email").lower()
        if channel not in ("email", "phone"):
            channel = "email"

        plain_phone = strip_country_code(user_in.phone) if user_in.phone else None
        if channel == "phone" and not plain_phone:
            raise HTTPException(
                status_code=400,
                detail="A phone number is required for phone verification.",
            )

        existing = self.db.query(User).filter(User.email == user_in.email).first()
        if existing and existing.is_verified:
            raise HTTPException(
                status_code=400, detail="An account with this email already exists."
            )

        if plain_phone:
            phone_owner = self.db.query(User).filter(User.phone == plain_phone).first()
            if phone_owner and (existing is None or phone_owner.id != existing.id):
                raise HTTPException(
                    status_code=400,
                    detail="An account with this phone number already exists.",
                )

        if existing:
            # Pending-account recovery: refresh details and start verification over.
            user = existing
            user.full_name = user_in.full_name
            user.phone = plain_phone
            user.password_hash = get_password_hash(user_in.password)
        else:
            user = User(
                email=user_in.email,
                full_name=user_in.full_name,
                phone=plain_phone,
                password_hash=get_password_hash(user_in.password),
                role=UserRole.PATIENT,  # public signups are always PATIENT
                is_verified=False,
                is_active=False,
            )
            self.db.add(user)

        user.otp_channel = channel
        user.otp_hash = None
        user.otp_expires = None
        user.otp_attempts = 0
        self.db.commit()
        self.db.refresh(user)

        if channel == "email":
            self._issue_and_send_email_otp(user, enforce_cooldown=False)
        # phone channel: nothing to send — the app verifies through Firebase.

        return user, channel

    # ------------------------------------------------------------------
    # Email-OTP verification
    # ------------------------------------------------------------------

    def _issue_and_send_email_otp(self, user: User, *, enforce_cooldown: bool) -> None:
        now = datetime.now(timezone.utc)
        if enforce_cooldown and user.otp_last_sent is not None:
            elapsed = (now - _utc(user.otp_last_sent)).total_seconds()
            if elapsed < OTP_RESEND_COOLDOWN_SECONDS:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"Please wait {int(OTP_RESEND_COOLDOWN_SECONDS - elapsed)}s "
                           "before requesting another code.",
                )

        otp = f"{random.SystemRandom().randint(100000, 999999)}"
        user.otp_hash = hash_otp(otp)
        user.otp_expires = now + timedelta(minutes=OTP_TTL_MINUTES)
        user.otp_attempts = 0
        user.otp_last_sent = now
        self.db.commit()

        try:
            from app.core.email_service import send_verification_email
            send_verification_email(to_email=user.email, otp=otp)
            logger.info("Verification OTP emailed to %s", user.email)
        except Exception:
            logger.exception(
                "Verification email FAILED for %s — OTP saved but not delivered "
                "(check SMTP_USER / SMTP_PASSWORD).", user.email,
            )

    def verify_email_otp(self, email: str, otp: str) -> User:
        user = self.db.query(User).filter(User.email == email).first()
        if not user:
            raise HTTPException(status_code=400, detail="Invalid verification code.")
        if user.is_verified:
            raise HTTPException(
                status_code=400, detail="This account is already verified. Please log in."
            )
        if (user.otp_channel or "email") == "phone":
            raise HTTPException(
                status_code=400,
                detail="This account uses phone verification. Verify via SMS instead.",
            )
        if not user.otp_hash:
            raise HTTPException(
                status_code=400, detail="No active code. Please request a new one."
            )
        if user.otp_attempts >= OTP_MAX_ATTEMPTS:
            self._invalidate_otp(user)
            raise HTTPException(
                status_code=400,
                detail="Too many incorrect attempts. Please request a new code.",
            )
        expires = _utc(user.otp_expires)
        if expires is None or expires < datetime.now(timezone.utc):
            raise HTTPException(
                status_code=400,
                detail="Verification code has expired. Please request a new one.",
            )
        if hash_otp(otp) != user.otp_hash:
            user.otp_attempts += 1
            remaining = OTP_MAX_ATTEMPTS - user.otp_attempts
            if remaining <= 0:
                self._invalidate_otp(user)
                raise HTTPException(
                    status_code=400,
                    detail="Too many incorrect attempts. Please request a new code.",
                )
            self.db.commit()
            raise HTTPException(
                status_code=400,
                detail=f"Invalid verification code. {remaining} attempts remaining.",
            )

        return self._activate(user)

    def resend_verification(self, email: str) -> None:
        """Email channel only; phone verification is resent through Firebase.
        Silently no-ops for unknown/verified accounts (anti-enumeration).

        The 60s resend cooldown is still enforced, but a cooldown hit is
        swallowed rather than surfaced as 429: returning 429 only for real
        pending accounts (and 200 for everyone else) would let an attacker
        enumerate which emails have unverified accounts. The client gates
        resend behind its own 60s countdown, so legitimate users never rely
        on a 429 for feedback."""
        user = self.db.query(User).filter(User.email == email).first()
        if not user or user.is_verified:
            return
        if (user.otp_channel or "email") != "email":
            return
        try:
            self._issue_and_send_email_otp(user, enforce_cooldown=True)
        except HTTPException as exc:
            if exc.status_code == status.HTTP_429_TOO_MANY_REQUESTS:
                return  # cooldown active — a code was just sent; stay silent
            raise

    def _invalidate_otp(self, user: User) -> None:
        user.otp_hash = None
        user.otp_expires = None
        self.db.commit()

    # ------------------------------------------------------------------
    # Phone verification / login via Firebase
    # ------------------------------------------------------------------

    def activate_phone_account(self, email: str, firebase_claims: dict) -> User:
        """Activate a pending phone-channel registration. The Firebase token's
        verified phone number must match the phone registered on the account."""
        user = self.db.query(User).filter(User.email == email).first()
        if not user:
            raise HTTPException(status_code=404, detail="Account not found. Please register first.")
        if user.is_verified:
            raise HTTPException(
                status_code=400, detail="This account is already verified. Please log in."
            )
        token_phone = strip_country_code(firebase_claims.get("phone_number", ""))
        if not user.phone or token_phone != user.phone:
            raise HTTPException(
                status_code=400,
                detail="The verified phone number does not match this account.",
            )
        return self._activate(user)

    def login_firebase(self, firebase_claims: dict) -> User:
        """Phone-OTP login. Never creates an account."""
        phone = strip_country_code(firebase_claims.get("phone_number", ""))
        user = self.db.query(User).filter(User.phone == phone).first()
        if not user:
            raise HTTPException(
                status_code=404,
                detail="No account found. Please register first.",
            )
        if not user.is_verified:
            # Proving ownership of the phone IS the pending verification for
            # phone-channel accounts; email-channel accounts must verify email.
            if (user.otp_channel or "email") == "phone":
                return self._activate(user)
            raise HTTPException(status_code=403, detail=NOT_VERIFIED_DETAIL)
        if not user.is_active:
            raise HTTPException(
                status_code=400,
                detail="Your account has been deactivated. Please contact support.",
            )
        return user

    # ------------------------------------------------------------------
    # Password login (email OR phone identifier)
    # ------------------------------------------------------------------

    def login_password(self, identifier: str, password: str) -> User:
        identifier = identifier.strip()
        if "@" in identifier:
            user = self.db.query(User).filter(User.email == identifier).first()
        else:
            user = (
                self.db.query(User)
                .filter(User.phone == strip_country_code(identifier))
                .first()
            )
        if not user or not verify_password(password, user.password_hash):
            raise HTTPException(
                status_code=400, detail="Incorrect email/phone or password."
            )
        if not user.is_verified:
            raise HTTPException(status_code=403, detail=NOT_VERIFIED_DETAIL)
        if not user.is_active:
            raise HTTPException(
                status_code=400,
                detail="Your account has been deactivated. Please contact support.",
            )
        return user

    # ------------------------------------------------------------------
    # Token issuance / refresh
    # ------------------------------------------------------------------

    def issue_tokens(self, user: User) -> TokenResponse:
        access_token = create_access_token(subject=user.id)
        refresh_token = create_refresh_token(subject=user.id)
        expires_at = datetime.now(timezone.utc) + timedelta(
            days=settings.REFRESH_TOKEN_EXPIRE_DAYS
        )
        self.db.add(RefreshToken(user_id=user.id, token=refresh_token, expires_at=expires_at))
        self.db.commit()
        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            user=UserResponse.model_validate(user),
        )

    def refresh_tokens(self, refresh_token: str) -> TokenResponse:
        db_token = (
            self.db.query(RefreshToken)
            .filter(RefreshToken.token == refresh_token)
            .first()
        )
        if not db_token:
            raise HTTPException(status_code=401, detail="Invalid refresh token.")
        expires = _utc(db_token.expires_at)
        if expires < datetime.now(timezone.utc):
            self.db.delete(db_token)
            self.db.commit()
            raise HTTPException(status_code=401, detail="Refresh token expired.")
        user = self.db.query(User).filter(User.id == db_token.user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found.")

        db_token.token = create_refresh_token(subject=user.id)
        db_token.expires_at = datetime.now(timezone.utc) + timedelta(
            days=settings.REFRESH_TOKEN_EXPIRE_DAYS
        )
        self.db.commit()
        return TokenResponse(
            access_token=create_access_token(subject=user.id),
            refresh_token=db_token.token,
            user=UserResponse.model_validate(user),
        )

    # ------------------------------------------------------------------
    # Forgot password (email OTP → short-lived reset token → new password)
    # Tokens are stored hashed — a DB leak exposes nothing usable.
    # ------------------------------------------------------------------

    def start_password_reset(self, email: str) -> None:
        user = self.db.query(User).filter(User.email == email).first()
        if not user:
            logger.info("Forgot-password: unknown email %s (200 anyway)", email)
            return
        self.db.query(PasswordResetToken).filter(
            PasswordResetToken.user_id == user.id,
            PasswordResetToken.used == False,  # noqa: E712
        ).delete()
        otp = f"{random.SystemRandom().randint(100000, 999999)}"
        self.db.add(
            PasswordResetToken(
                user_id=user.id,
                token=hash_otp(otp),
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=OTP_TTL_MINUTES),
            )
        )
        self.db.commit()
        try:
            from app.core.email_service import send_otp_email
            send_otp_email(to_email=user.email, otp=otp)
            logger.info("Forgot-password OTP emailed to %s", user.email)
        except Exception:
            logger.exception("Forgot-password email FAILED for %s", user.email)

    def verify_password_reset_otp(self, email: str, otp: str) -> str:
        user = self.db.query(User).filter(User.email == email).first()
        if not user:
            raise HTTPException(status_code=400, detail="Invalid OTP.")
        db_token = (
            self.db.query(PasswordResetToken)
            .filter(
                PasswordResetToken.user_id == user.id,
                PasswordResetToken.token == hash_otp(otp),
                PasswordResetToken.used == False,  # noqa: E712
            )
            .first()
        )
        if not db_token:
            raise HTTPException(
                status_code=400, detail="Invalid OTP. Please check and try again."
            )
        if _utc(db_token.expires_at) < datetime.now(timezone.utc):
            self.db.delete(db_token)
            self.db.commit()
            raise HTTPException(
                status_code=400, detail="OTP has expired. Please request a new one."
            )
        import secrets
        reset_token = secrets.token_urlsafe(32)
        db_token.token = hash_otp(reset_token)
        db_token.expires_at = datetime.now(timezone.utc) + timedelta(
            minutes=RESET_TOKEN_TTL_MINUTES
        )
        self.db.commit()
        return reset_token

    def reset_password(self, token: str, new_password: str) -> None:
        db_token = (
            self.db.query(PasswordResetToken)
            .filter(
                PasswordResetToken.token == hash_otp(token),
                PasswordResetToken.used == False,  # noqa: E712
            )
            .first()
        )
        if not db_token:
            raise HTTPException(
                status_code=400, detail="Invalid or already-used reset token."
            )
        if _utc(db_token.expires_at) < datetime.now(timezone.utc):
            self.db.delete(db_token)
            self.db.commit()
            raise HTTPException(
                status_code=400,
                detail="Session expired. Please start the reset process again.",
            )
        user = self.db.query(User).filter(User.id == db_token.user_id).first()
        if not user:
            raise HTTPException(status_code=404, detail="User not found.")
        user.password_hash = get_password_hash(new_password)
        db_token.used = True
        self.db.commit()

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _activate(self, user: User) -> User:
        """Verification succeeded — the ONLY place a pending account becomes usable."""
        user.is_verified = True
        user.is_active = True
        user.otp_hash = None
        user.otp_expires = None
        user.otp_attempts = 0
        self.db.commit()
        self.db.refresh(user)
        logger.info("Account activated: %s (channel=%s)", user.email, user.otp_channel)
        return user
