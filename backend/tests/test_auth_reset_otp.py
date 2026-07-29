"""
Regression tests for password-reset OTP brute-force protection (C3).

The 6-digit reset OTP (1,000,000 combinations, 10-minute TTL) must lock after
RESET_OTP_MAX_ATTEMPTS wrong guesses, otherwise it is brute-forceable into a
full account takeover. These tests drive AuthService directly so they are
deterministic (no dependency on the randomly generated OTP).
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import HTTPException

from app.models.models import PasswordResetToken
from app.services.auth_service import (
    AuthService,
    RESET_OTP_MAX_ATTEMPTS,
    hash_otp,
)
from tests.conftest import PATIENT_A_ID, _Session

KNOWN_OTP = "123456"
WRONG_OTP = "999999"


@pytest.fixture
def reset_token():
    """Seed a fresh, known reset OTP for Patient A and clean up afterwards."""
    with _Session() as db:
        db.query(PasswordResetToken).filter(
            PasswordResetToken.user_id == PATIENT_A_ID
        ).delete()
        db.add(
            PasswordResetToken(
                user_id=PATIENT_A_ID,
                token=hash_otp(KNOWN_OTP),
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
                used=False,
                attempts=0,
            )
        )
        db.commit()
    yield
    with _Session() as db:
        db.query(PasswordResetToken).filter(
            PasswordResetToken.user_id == PATIENT_A_ID
        ).delete()
        db.commit()


def test_reset_otp_locks_after_max_attempts(db, reset_token):
    svc = AuthService(db)
    # The first (MAX - 1) wrong guesses report remaining attempts...
    for expected_remaining in range(RESET_OTP_MAX_ATTEMPTS - 1, 0, -1):
        with pytest.raises(HTTPException) as exc:
            svc.verify_password_reset_otp("patient_a@test.com", WRONG_OTP)
        assert exc.value.status_code == 400
        assert f"{expected_remaining} attempts remaining" in exc.value.detail

    # ...the final wrong guess locks the token out and destroys it.
    with pytest.raises(HTTPException) as exc:
        svc.verify_password_reset_otp("patient_a@test.com", WRONG_OTP)
    assert "Too many incorrect attempts" in exc.value.detail

    # Even the CORRECT OTP no longer works — the token is gone.
    with pytest.raises(HTTPException) as exc:
        svc.verify_password_reset_otp("patient_a@test.com", KNOWN_OTP)
    assert exc.value.status_code == 400
    remaining = (
        db.query(PasswordResetToken)
        .filter(PasswordResetToken.user_id == PATIENT_A_ID)
        .count()
    )
    assert remaining == 0


def test_correct_otp_succeeds_and_resets_attempts(db, reset_token):
    svc = AuthService(db)
    # A couple of wrong guesses (still under the cap)...
    for _ in range(2):
        with pytest.raises(HTTPException):
            svc.verify_password_reset_otp("patient_a@test.com", WRONG_OTP)

    # ...then the correct OTP is exchanged for an opaque reset token.
    reset = svc.verify_password_reset_otp("patient_a@test.com", KNOWN_OTP)
    assert isinstance(reset, str) and len(reset) > 20

    row = (
        db.query(PasswordResetToken)
        .filter(PasswordResetToken.user_id == PATIENT_A_ID)
        .first()
    )
    # Attempts reset for the new token's lifetime, and it now stores the
    # reset-token hash (not the OTP hash).
    assert row.attempts == 0
    assert row.token == hash_otp(reset)
