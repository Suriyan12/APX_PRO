"""
Study Materials free/view-only feature flag (STUDY_MATERIALS_REQUIRE_PAYMENT).

When the flag is False (the shipped default) study materials are free for every
authenticated user: the access gate is bypassed and access-status reports free.
When True the paid model resumes unchanged — a non-purchaser is denied, while an
admin, a manually-granted user, or a purchaser still passes.

We assert the gate through both the /notes/access-status endpoint and the exact
helper used by the file-serving endpoint (_require_notes_access, called at the
top of view_note), so the content gate is covered without touching Google Drive.
"""
import pytest
from fastapi import HTTPException

from app.api.v1.notes import _has_notes_access, _require_notes_access
from app.core.config import settings
from app.models.models import NotesPurchase, User
from tests.conftest import ADMIN_ID, PATIENT_A_ID, _Session


@pytest.fixture(autouse=True)
def _clean_notes_access():
    """Guarantee the test patient starts with no purchase and no manual grant,
    so paid-mode assertions are meaningful."""
    def _reset():
        with _Session() as db:
            db.query(NotesPurchase).delete()
            for uid in (PATIENT_A_ID,):
                u = db.get(User, uid)
                if u:
                    u.has_notes_access = False
            db.commit()
    _reset()
    yield
    _reset()


# ── access-status endpoint ────────────────────────────────────────────────────

def test_free_mode_grants_access_to_non_purchaser(api):
    # Default flag is False → free for everyone.
    api.as_user(PATIENT_A_ID)
    r = api.get("/api/v1/notes/access-status")
    assert r.status_code == 200
    body = r.json()
    assert body["has_access"] is True
    assert body["is_admin"] is False
    assert body["require_payment"] is False


def test_paid_mode_denies_non_purchaser(api, monkeypatch):
    monkeypatch.setattr(settings, "STUDY_MATERIALS_REQUIRE_PAYMENT", True)
    api.as_user(PATIENT_A_ID)
    r = api.get("/api/v1/notes/access-status")
    assert r.status_code == 200
    body = r.json()
    assert body["has_access"] is False
    assert body["require_payment"] is True


# ── the exact view_note content gate ──────────────────────────────────────────

def test_view_gate_open_when_free(db):
    # Flag False (default): the gate the /viewer endpoint calls must NOT raise
    # for a plain patient with no purchase.
    user = db.get(User, PATIENT_A_ID)
    assert _has_notes_access(user, db) is True
    _require_notes_access(user, db)  # must not raise


def test_view_gate_blocks_non_purchaser_when_paid(db, monkeypatch):
    monkeypatch.setattr(settings, "STUDY_MATERIALS_REQUIRE_PAYMENT", True)
    user = db.get(User, PATIENT_A_ID)
    assert _has_notes_access(user, db) is False
    with pytest.raises(HTTPException) as exc:
        _require_notes_access(user, db)
    assert exc.value.status_code == 403


def test_paid_mode_still_allows_admin_and_granted_and_purchaser(db, monkeypatch):
    monkeypatch.setattr(settings, "STUDY_MATERIALS_REQUIRE_PAYMENT", True)

    # Admin always passes.
    admin = db.get(User, ADMIN_ID)
    assert _has_notes_access(admin, db) is True

    # Manual grant passes.
    patient = db.get(User, PATIENT_A_ID)
    patient.has_notes_access = True
    db.commit()
    assert _has_notes_access(patient, db) is True

    # A real active purchase passes (reset the manual grant first to isolate).
    patient.has_notes_access = False
    db.add(NotesPurchase(
        user_id=PATIENT_A_ID,
        razorpay_order_id="order_x",
        razorpay_payment_id="pay_x",
        amount=1.0,
        is_active=True,
    ))
    db.commit()
    assert _has_notes_access(patient, db) is True
