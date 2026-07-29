"""
M6: password strength — min 8, max 72 (bcrypt byte limit), at least one letter
and one number. Enforced on registration, admin-create, and password reset.
"""
import pytest
from pydantic import ValidationError

from app.schemas.schemas import AdminCreateUserRequest, ResetPasswordRequest, UserCreate


@pytest.mark.parametrize("pw", ["short1", "allletters", "12345678", "x" * 73 + "1"])
def test_weak_passwords_rejected(pw):
    with pytest.raises(ValidationError):
        UserCreate(email="a@b.com", full_name="A", password=pw)


def test_strong_password_accepted():
    u = UserCreate(email="a@b.com", full_name="A", password="Rehab2026")
    assert u.password == "Rehab2026"


def test_policy_applies_to_admin_create_and_reset():
    with pytest.raises(ValidationError):
        AdminCreateUserRequest(full_name="Ad", email="a@b.com", password="onlyletters")
    with pytest.raises(ValidationError):
        ResetPasswordRequest(token="t", new_password="1234567")
    # Valid ones construct fine.
    AdminCreateUserRequest(full_name="Ad", email="a@b.com", password="Admin1234")
    ResetPasswordRequest(token="t", new_password="Reset123")
