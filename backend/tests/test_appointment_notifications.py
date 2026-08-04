"""
Integration tests for appointment → notification wiring (Phase 3).

Exercises the real HTTP endpoints (book / approve / reject) and asserts the
correct in-app notifications are produced with the right deep-link payloads,
that they go to the right recipients, and that repeated requests cannot
generate duplicates. Firebase is never involved (FCM disabled by default).
"""
import uuid

import pytest

from tests.conftest import PATIENT_A_ID, ADMIN_ID, future_slot, _Session
from app.models.models import Notification, DeviceToken
from app.repositories.notification_repository import (
    DeviceTokenRepository,
    NotificationRepository,
)
from app.services.notification_service import NotificationService
from app.services.push_service import PushResult
from app.services import notification_templates as templates

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


def _reschedule(api, appt_id, days):
    """Patient A moves an existing appointment to a new future slot."""
    start, end = future_slot(days=days)
    api.as_user(PATIENT_A_ID)
    r = api.put(
        f"{APPTS}/{appt_id}/reschedule",
        json={"start_time": start, "end_time": end},
    )
    assert r.status_code == 200, r.text
    return r.json()


def _events(listing, event):
    return [i for i in listing["items"] if i["data"].get("event") == event]


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


# ── Reschedule flow (the previously-missing notifications) ────────────────────

def test_reschedule_request_notifies_admins(api):
    """The reported bug: rescheduling a still-pending appointment must notify
    admins in-app, not only by email."""
    appt = _book(api, days=6)
    _reschedule(api, appt["id"], days=7)

    api.as_user(ADMIN_ID)
    listing = api.get(NOTIF).json()
    resched = _events(listing, "reschedule_requested")
    assert len(resched) == 1
    n = resched[0]
    assert n["type"] == "appointment"
    assert n["data"]["appointment_id"] == appt["id"]
    assert "reschedule" in n["title"].lower()
    # The patient (requester) receives nothing for their own reschedule request.
    api.as_user(PATIENT_A_ID)
    assert api.get(f"{NOTIF}/unread-count").json()["count"] == 0


def test_reschedule_approved_notifies_patient_with_reschedule_copy(api):
    appt = _book(api, days=8)
    _reschedule(api, appt["id"], days=9)

    api.as_user(ADMIN_ID)
    assert api.put(f"{APPTS}/{appt['id']}/approve").status_code == 200

    api.as_user(PATIENT_A_ID)
    listing = api.get(NOTIF).json()
    approved = _events(listing, "reschedule_approved")
    assert len(approved) == 1
    # It must NOT be tagged as an initial approval.
    assert _events(listing, "approved") == []
    assert "reschedul" in approved[0]["body"].lower()


def test_reschedule_rejected_notifies_patient_with_reschedule_copy(api):
    appt = _book(api, days=10)
    _reschedule(api, appt["id"], days=11)

    api.as_user(ADMIN_ID)
    r = api.put(f"{APPTS}/{appt['id']}/reject", json={"reason": "No slots that day"})
    assert r.status_code == 200, r.text

    api.as_user(PATIENT_A_ID)
    listing = api.get(NOTIF).json()
    rejected = _events(listing, "reschedule_rejected")
    assert len(rejected) == 1
    assert _events(listing, "rejected") == []
    assert "No slots that day" in rejected[0]["body"]


# ── Cancellation flow ─────────────────────────────────────────────────────────

def test_patient_cancel_notifies_admins(api):
    appt = _book(api, days=12)

    api.as_user(PATIENT_A_ID)
    r = api.put(f"{APPTS}/{appt['id']}/cancel", json={"reason": "Feeling better"})
    assert r.status_code == 200, r.text

    api.as_user(ADMIN_ID)
    listing = api.get(NOTIF).json()
    cancelled = _events(listing, "cancelled_by_patient")
    assert len(cancelled) == 1
    assert cancelled[0]["data"]["appointment_id"] == appt["id"]
    assert "Feeling better" in cancelled[0]["body"]


def test_admin_cancel_notifies_patient(api):
    appt = _book(api, days=13)

    api.as_user(ADMIN_ID)
    r = api.put(f"{APPTS}/{appt['id']}/cancel", json={"reason": "Therapist unavailable"})
    assert r.status_code == 200, r.text

    api.as_user(PATIENT_A_ID)
    listing = api.get(NOTIF).json()
    cancelled = _events(listing, "cancelled_by_admin")
    assert len(cancelled) == 1
    assert cancelled[0]["data"]["appointment_id"] == appt["id"]
    assert "clinic" in cancelled[0]["body"].lower()


def test_reschedule_does_not_produce_a_duplicate_admin_notification(api):
    """Each successful reschedule is one event → exactly one admin notification
    for it (on top of the original booking notification)."""
    appt = _book(api, days=14)          # 1 admin notification: requested
    _reschedule(api, appt["id"], days=15)  # +1 admin notification: reschedule_requested

    api.as_user(ADMIN_ID)
    listing = api.get(NOTIF).json()
    assert len(_events(listing, "requested")) == 1
    assert len(_events(listing, "reschedule_requested")) == 1
    assert listing["total"] == 2


def test_reschedule_after_approval_notifies_admins(api):
    """A reschedule must notify admins even when the appointment was ALREADY
    approved (the valid APPROVED → PENDING transition), not only when pending."""
    appt = _book(api, days=16)

    # Admin approves first — appointment is now APPROVED.
    api.as_user(ADMIN_ID)
    assert api.put(f"{APPTS}/{appt['id']}/approve").status_code == 200

    # Patient reschedules the already-approved appointment.
    _reschedule(api, appt["id"], days=17)

    api.as_user(ADMIN_ID)
    listing = api.get(NOTIF).json()
    resched = _events(listing, "reschedule_requested")
    assert len(resched) == 1
    assert resched[0]["data"]["appointment_id"] == appt["id"]


# ── Push transport (FCM): the event reaches the device with its deep-link ─────

class _FakePush:
    """Enabled fake FCM transport that records what it was asked to deliver."""

    def __init__(self):
        self.enabled = True
        self.calls = []

    def send_to_tokens(self, tokens, title, body, data=None):
        self.calls.append(
            {"tokens": list(tokens), "title": title, "body": body, "data": data}
        )
        return PushResult(success_count=len(tokens))


def test_reschedule_notification_reaches_push_with_deeplink(db):
    """Verify the FCM path (not just the in-app row): an appointment reschedule
    event is delivered to the recipient's active device token carrying the
    deep-link payload the client routes on. Firebase itself is faked."""
    DeviceTokenRepository(db).upsert(ADMIN_ID, "tok-admin", "android")
    fake = _FakePush()
    svc = NotificationService(
        NotificationRepository(db), DeviceTokenRepository(db), push=fake
    )

    appt_id = uuid.uuid4()
    content = templates.appointment_reschedule_requested(
        "Patient A", appt_id, "old when", "new when"
    )
    # No background_tasks → dispatch runs inline through the injected fake push,
    # exercising exactly the transport the route backgrounds in production.
    svc.create_notification(
        ADMIN_ID, content.title, content.body, content.type, content.data
    )

    assert len(fake.calls) == 1
    call = fake.calls[0]
    assert call["tokens"] == ["tok-admin"]
    assert call["title"] == "Reschedule requested"
    payload = call["data"]
    assert payload["type"] == "appointment"
    assert payload["event"] == "reschedule_requested"
    assert payload["appointment_id"] == str(appt_id)
    # notification_id is included so the client can auto-mark-read after opening.
    assert "notification_id" in payload


def test_admin_cancel_notification_reaches_patient_push(db):
    """The patient's cancellation push carries the cancelled_by_admin deep-link."""
    DeviceTokenRepository(db).upsert(PATIENT_A_ID, "tok-patient", "android")
    fake = _FakePush()
    svc = NotificationService(
        NotificationRepository(db), DeviceTokenRepository(db), push=fake
    )

    appt_id = uuid.uuid4()
    content = templates.appointment_cancelled_by_admin(appt_id, "some when", "Clinic closed")
    svc.create_notification(
        PATIENT_A_ID, content.title, content.body, content.type, content.data
    )

    assert len(fake.calls) == 1
    payload = fake.calls[0]["data"]
    assert fake.calls[0]["tokens"] == ["tok-patient"]
    assert payload["event"] == "cancelled_by_admin"
    assert payload["appointment_id"] == str(appt_id)
