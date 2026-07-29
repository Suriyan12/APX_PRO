"""
M8 / payments: the Notes purchase-verify endpoint must reject a bad Razorpay
signature, accept a correctly-signed one, and treat a replayed payment id as
already-granted (no duplicate grant). Runs with DEVELOPMENT_MODE off so the
real signature path is exercised; no live Razorpay call is made (verification
is a local HMAC check).
"""
import hashlib
import hmac

import pytest

from app.core.config import settings
from app.models.models import NotesPurchase
from tests.conftest import PATIENT_B_ID, _Session

ORDER_ID = "order_testM8"
PAYMENT_ID = "pay_testM8"


def _sign(order: str, payment: str) -> str:
    return hmac.new(
        settings.RAZORPAY_KEY_SECRET.encode(),
        f"{order}|{payment}".encode(),
        hashlib.sha256,
    ).hexdigest()


@pytest.fixture(autouse=True)
def _no_dev_mode(monkeypatch):
    # Force the production signature path even if a .env enabled dev mode.
    monkeypatch.setattr(settings, "DEVELOPMENT_MODE", False)
    yield
    with _Session() as db:
        db.query(NotesPurchase).filter(NotesPurchase.user_id == PATIENT_B_ID).delete()
        db.commit()


def test_bad_signature_rejected(api):
    api.as_user(PATIENT_B_ID)
    r = api.post(
        "/api/v1/notes/purchase/verify",
        json={
            "razorpay_order_id": ORDER_ID,
            "razorpay_payment_id": PAYMENT_ID,
            "razorpay_signature": "deadbeef-not-valid",
        },
    )
    assert r.status_code == 400
    assert "signature" in r.json()["detail"].lower()


def test_valid_signature_grants_then_replay_is_idempotent(api):
    api.as_user(PATIENT_B_ID)
    body = {
        "razorpay_order_id": ORDER_ID,
        "razorpay_payment_id": PAYMENT_ID,
        "razorpay_signature": _sign(ORDER_ID, PAYMENT_ID),
    }
    r1 = api.post("/api/v1/notes/purchase/verify", json=body)
    assert r1.status_code == 200
    assert r1.json()["status"] == "granted"

    # Replaying the same payment must not create a second grant.
    r2 = api.post("/api/v1/notes/purchase/verify", json=body)
    assert r2.status_code == 200
    assert r2.json()["status"] in ("granted", "already_granted")

    with _Session() as db:
        count = (
            db.query(NotesPurchase)
            .filter(NotesPurchase.razorpay_payment_id == PAYMENT_ID)
            .count()
        )
    assert count == 1
