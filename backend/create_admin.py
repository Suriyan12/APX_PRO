r"""
Run this script once from the backend/ directory to create an admin user.

Credentials are read from the environment so they are never stored in the repo
(this file is public). Nothing is created unless BOTH values are supplied:

    PowerShell:
        $env:ADMIN_EMAIL="you@example.com"
        $env:ADMIN_PASSWORD="<strong password>"
        python create_admin.py
        Remove-Item Env:\ADMIN_EMAIL, Env:\ADMIN_PASSWORD

    bash:
        ADMIN_EMAIL="you@example.com" ADMIN_PASSWORD="<strong password>" python create_admin.py

Optional: ADMIN_NAME (default "APX Admin"), ADMIN_PHONE (default "0000000000").

To target a non-local database (e.g. Azure SQL), set DATABASE_URL as well - an OS
environment variable overrides backend/.env, so your local config is untouched.

If the email already exists it promotes that user to ADMIN and resets the password.
"""
import sys
import os

# Allow importing app modules from backend/
sys.path.insert(0, os.path.dirname(__file__))

from app.core.database import SessionLocal
from app.core.security import get_password_hash
from app.models.models import User, UserRole
# Reuse the app's own password policy so the admin account is held to exactly
# the same bar as any user registering through the API.
from app.schemas.schemas import validate_password_strength

ADMIN_EMAIL    = os.environ.get("ADMIN_EMAIL", "").strip()
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "")
ADMIN_NAME     = os.environ.get("ADMIN_NAME", "APX Admin").strip()
ADMIN_PHONE    = os.environ.get("ADMIN_PHONE", "0000000000").strip()


def _require_credentials():
    """Refuse to run without explicit credentials, so this script can never
    silently create a well-known admin account on a public deployment."""
    missing = [
        name
        for name, value in (("ADMIN_EMAIL", ADMIN_EMAIL), ("ADMIN_PASSWORD", ADMIN_PASSWORD))
        if not value
    ]
    if missing:
        sys.exit(
            f"ERROR: {' and '.join(missing)} must be set in the environment.\n"
            "       See the usage examples at the top of this file.\n"
            "       Nothing was created."
        )
    if "@" not in ADMIN_EMAIL or ADMIN_EMAIL.startswith("@") or ADMIN_EMAIL.endswith("@"):
        sys.exit(f"ERROR: ADMIN_EMAIL is not a valid email address: {ADMIN_EMAIL}")
    try:
        validate_password_strength(ADMIN_PASSWORD)
    except ValueError as e:
        sys.exit(f"ERROR: ADMIN_PASSWORD rejected - {e}")


def create_or_promote_admin():
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == ADMIN_EMAIL).first()
        if user:
            user.role = UserRole.ADMIN
            user.password_hash = get_password_hash(ADMIN_PASSWORD)
            user.is_active = True
            user.is_verified = True   # admin login is blocked without this
            db.commit()
            print(f"[OK] Existing user promoted to ADMIN: {ADMIN_EMAIL}")
        else:
            user = User(
                email=ADMIN_EMAIL,
                full_name=ADMIN_NAME,
                phone=ADMIN_PHONE,
                password_hash=get_password_hash(ADMIN_PASSWORD),
                role=UserRole.ADMIN,
                is_active=True,
                is_verified=True,   # admin login is blocked without this
            )
            db.add(user)
            db.commit()
            print(f"[OK] Admin user created: {ADMIN_EMAIL}")

        # The password is deliberately NOT printed - it would land in shell
        # history, terminal scrollback and CI logs.
        print(f"     Role     : ADMIN")
        print()
        print("Log in with the password you supplied via ADMIN_PASSWORD.")
    finally:
        db.close()


if __name__ == "__main__":
    _require_credentials()
    create_or_promote_admin()
