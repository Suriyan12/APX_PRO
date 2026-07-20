"""
Authentication HTTP adapter.

Route handlers are intentionally thin — they own HTTP concerns only and
delegate all domain logic to AuthService. Phone OTPs are handled end-to-end
by Firebase Authentication in the app; the backend only ever validates the
resulting Firebase ID token (see app/services/firebase_auth_service.py).

Flow overview:
  POST /register            → PENDING account (is_verified=False, is_active=False)
  POST /verify-email        → email-channel activation (hashed OTP, expiry, retry cap)
  POST /verify-phone        → phone-channel activation (Firebase ID token)
  POST /resend-verification → email channel only, 60 s cooldown, anti-enumeration
  POST /login               → password login with email OR phone as username
  POST /login/firebase      → phone-OTP login (never creates accounts)
  POST /refresh             → refresh-token rotation
  POST /forgot-password/*   → hashed OTP → hashed short-lived reset token
"""
from fastapi import APIRouter, Depends, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.services import firebase_auth_service
from app.services.auth_service import AuthService, normalize_e164
from app.schemas.schemas import (
    FirebaseLoginRequest,
    ForgotPasswordRequest,
    ForgotPasswordVerifyRequest,
    RegistrationResponse,
    ResendVerificationRequest,
    ResetPasswordRequest,
    TokenRefreshRequest,
    TokenResponse,
    UserCreate,
    VerifyEmailRequest,
    VerifyPhoneRequest,
)

router = APIRouter()


def _svc(db: Session) -> AuthService:
    return AuthService(db)


# ---------------------------------------------------------------------------
# Registration → pending account + verification dispatch
# ---------------------------------------------------------------------------

@router.post("/register", response_model=RegistrationResponse, status_code=status.HTTP_201_CREATED)
def register(user_in: UserCreate, db: Session = Depends(get_db)):
    user, channel = _svc(db).register(user_in)
    return RegistrationResponse(
        message=(
            "Account created. Enter the code we emailed you to verify."
            if channel == "email"
            else "Account created. Verify your phone number via SMS to continue."
        ),
        email=user.email,
        channel=channel,
        phone_e164=normalize_e164(user.phone) if user.phone else None,
        verification_required=True,
    )


# ---------------------------------------------------------------------------
# Verification (activation) — one channel is enough, never both
# ---------------------------------------------------------------------------

@router.post("/verify-email", response_model=TokenResponse)
def verify_email(request: VerifyEmailRequest, db: Session = Depends(get_db)):
    svc = _svc(db)
    user = svc.verify_email_otp(request.email, request.otp)
    return svc.issue_tokens(user)  # activation auto-logs the user in


@router.post("/verify-phone", response_model=TokenResponse)
def verify_phone(request: VerifyPhoneRequest, db: Session = Depends(get_db)):
    claims = firebase_auth_service.verify_firebase_token(request.id_token)
    svc = _svc(db)
    user = svc.activate_phone_account(request.email, claims)
    return svc.issue_tokens(user)


@router.post("/resend-verification", status_code=status.HTTP_200_OK)
def resend_verification(request: ResendVerificationRequest, db: Session = Depends(get_db)):
    _svc(db).resend_verification(request.email)
    return {"message": "If that account needs verification, a new code has been sent."}


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------

@router.post("/login", response_model=TokenResponse)
def login(login_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """Password login. `username` may be an email address or a phone number."""
    svc = _svc(db)
    user = svc.login_password(login_data.username, login_data.password)
    return svc.issue_tokens(user)


@router.post("/login/firebase", response_model=TokenResponse)
def login_firebase(request: FirebaseLoginRequest, db: Session = Depends(get_db)):
    """Phone-OTP login: Firebase verified the SMS code; we validate its ID
    token and sign in the matching account. No password, no account creation."""
    claims = firebase_auth_service.verify_firebase_token(request.id_token)
    svc = _svc(db)
    user = svc.login_firebase(claims)
    return svc.issue_tokens(user)


# ---------------------------------------------------------------------------
# Token refresh
# ---------------------------------------------------------------------------

@router.post("/refresh", response_model=TokenResponse)
def refresh(refresh_in: TokenRefreshRequest, db: Session = Depends(get_db)):
    return _svc(db).refresh_tokens(refresh_in.refresh_token)


# ---------------------------------------------------------------------------
# Forgot password
# ---------------------------------------------------------------------------

@router.post("/forgot-password", status_code=status.HTTP_200_OK)
def forgot_password(request: ForgotPasswordRequest, db: Session = Depends(get_db)):
    _svc(db).start_password_reset(request.email)
    # Always 200 to prevent email enumeration.
    return {"message": "If that email is registered, an OTP has been sent to it."}


@router.post("/forgot-password/verify", status_code=status.HTTP_200_OK)
def verify_forgot_password_otp(request: ForgotPasswordVerifyRequest, db: Session = Depends(get_db)):
    reset_token = _svc(db).verify_password_reset_otp(request.email, request.otp)
    return {"reset_token": reset_token}


@router.post("/reset-password", status_code=status.HTTP_200_OK)
def reset_password(request: ResetPasswordRequest, db: Session = Depends(get_db)):
    _svc(db).reset_password(request.token, request.new_password)
    return {"message": "Password reset successfully. Please log in with your new password."}
