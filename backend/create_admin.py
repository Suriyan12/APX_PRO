"""
Run this script once from the backend/ directory to create an admin user:

    cd backend
    python create_admin.py

If the email already exists it updates the role to ADMIN and resets the password.
"""
import sys
import os

# Allow importing app modules from backend/
sys.path.insert(0, os.path.dirname(__file__))

from app.core.database import SessionLocal
from app.core.security import get_password_hash
from app.models.models import User, UserRole

ADMIN_EMAIL    = "admin@apxpro.com"
ADMIN_NAME     = "APX Admin"
ADMIN_PHONE    = "0000000000"
ADMIN_PASSWORD = "Admin@123456"   # change after first login

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

        print(f"     Password : {ADMIN_PASSWORD}")
        print(f"     Role     : ADMIN")
        print()
        print("Log in with these credentials and change the password immediately.")
    finally:
        db.close()


if __name__ == "__main__":
    create_or_promote_admin()
