"""
Integration tests for appointment → notification wiring (Phase 3).

Exercises the real HTTP endpoints (book / approve / reject) and asserts the
correct in-app notifications are produced with the right deep-link payloads,
that they go to the right recipients, and that repeated requests cannot
generate duplicates. Firebase is never involved (FCM disabled by default).
"""
import pytest

from tests.conftest import PATIENT_A_ID, ADMIN_ID, future_slot, _Session
from app.models.models import Notification, DeviceToken

APPTS = "/api/v1/appointments"
NOTIF = "/api/v1/notifications"


@pytest.fixture(autouse=True)
def _clean_notifications():
    def _wipe():
        with _Session() as db:
            db.query(Notification).delete()
            db.query(DeviceToken).delete()
            db.commit()
    _wipe()
    yield
    _wipe()


def _book(api, days):
    start, end = future_slot(days=days)
    api.as_user(PATIENT_A_ID)
    r = api.post(f"{APPTS}/book", json={"start_time": start, "end_time": end})
    assert r.status_code == 201, r.text
    return r.json()


def test_booking_notifies_admins(api):
    appt = _book(api, days=1)

    api.as_user(ADMIN_ID)
    listing = api.get(NOTIF).json()
    assert listing["total"] == 1
    n = listing["items"][0]
    assert n["type"] == "appointment"
    assert n["data"]["event"] == "requested"
    assert n["data"]["appointment_id"] == appt["id"]
    assert n["data"]["route"] == f"/appointments/{appt['id']}"
    assert n["is_read"] is False

    # The patient themselves receives nothing on booking.
    api.as_user(PATIENT_A_ID)
    assert api.get(f"{NOTIF}/unread-count").json()["count"] == 0


def test_approve_notifies_patient(api):
    appt = _book(api, days=2)

    api.as_user(ADMIN_ID)
    assert api.put(f"{APPTS}/{appt['id']}/approve").status_code == 200

    api.as_user(PATIENT_A_ID)
    listing = api.get(NOTIF).json()
    assert listing["total"] == 1
    n = listing["items"][0]
    assert n["data"]["event"] == "approved"
    assert n["data"]["appointment_id"] == appt["id"]
    assert "approved" in n["body"].lower()


def test_reject_notifies_patient_with_reason(api):
    appt = _book(api, days=3)

    api.as_user(ADMIN_ID)
    r = api.put(f"{APPTS}/{appt['id']}/reject", json={"reason": "Slot unavailable"})
    assert r.status_code == 200, r.text

    api.as_user(PATIENT_A_ID)
    listing = api.get(NOTIF).json()
    assert listing["total"] == 1
    n = listing["items"][0]
    assert n["data"]["event"] == "rejected"
    assert "Slot unavailable" in n["body"]


def test_repeated_approve_does_not_duplicate_notifications(api):
    appt = _book(api, days=4)

    api.as_user(ADMIN_ID)
    assert api.put(f"{APPTS}/{appt['id']}/approve").status_code == 200
    # The state machine rejects a second approval, so no second notification.
    assert api.put(f"{APPTS}/{appt['id']}/approve").status_code == 400

    api.as_user(PATIENT_A_ID)
    listing = api.get(NOTIF).json()
    approved = [i for i in listing["items"] if i["data"]["event"] == "approved"]
    assert len(approved) == 1


def test_booking_then_reject_leaves_single_admin_and_single_patient_notification(api):
    appt = _book(api, days=5)

    # One admin notification from booking.
    api.as_user(ADMIN_ID)
    assert api.get(f"{NOTIF}/unread-count").json()["count"] == 1

    api.as_user(ADMIN_ID)
    assert api.put(f"{APPTS}/{appt['id']}/reject").status_code == 200

    # Patient gets exactly one (the rejection).
    api.as_user(PATIENT_A_ID)
    assert api.get(f"{NOTIF}/unread-count").json()["count"] == 1
