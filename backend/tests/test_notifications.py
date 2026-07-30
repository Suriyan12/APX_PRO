"""
Tests for the Notification Center backend (Phase 1).

Covers device register/unregister, listing + pagination + unread filter,
unread count, mark-one-read (incl. cross-user ownership), mark-all-read, and
that notification creation persists AND gracefully skips push when Firebase is
not configured (the default).

Runs on the shared SQLite TestClient from conftest.py.
"""
import pytest

from tests.conftest import PATIENT_A_ID, PATIENT_B_ID, _Session
from app.models.models import DeviceToken, Notification, User
from app.repositories.notification_repository import (
    DeviceTokenRepository,
    NotificationRepository,
)
from app.services.notification_service import NotificationService

BASE = "/api/v1/notifications"


@pytest.fixture(autouse=True)
def _clean_notifications():
    def _wipe():
        with _Session() as db:
            db.query(DeviceToken).delete()
            db.query(Notification).delete()
            db.commit()
    _wipe()
    yield
    _wipe()


def _svc(db):
    return NotificationService(NotificationRepository(db), DeviceTokenRepository(db))


def _seed(db, user_id, n=1, title="Hello"):
    """Create n notifications for a user via the service (also exercises the
    graceful push-skip path)."""
    svc = _svc(db)
    created = []
    for i in range(n):
        created.append(
            svc.create_notification(
                user_id=user_id,
                title=f"{title} {i}",
                body=f"Body {i}",
                type="system",
                data={"index": i},
            )
        )
    return created


# ── Device registration ─────────────────────────────────────────────────────

def test_register_and_reregister_device_is_idempotent(api, db):
    api.as_user(PATIENT_A_ID)
    r = api.post(f"{BASE}/devices", json={"token": "tok-123", "platform": "android"})
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["platform"] == "android"
    assert body["is_active"] is True

    # Re-registering the same token must not create a duplicate row.
    r2 = api.post(f"{BASE}/devices", json={"token": "tok-123", "platform": "android"})
    assert r2.status_code == 201
    with _Session() as s:
        assert s.query(DeviceToken).filter(DeviceToken.token == "tok-123").count() == 1


def test_unregister_device_is_idempotent(api):
    api.as_user(PATIENT_A_ID)
    api.post(f"{BASE}/devices", json={"token": "tok-x"})
    r = api.post(f"{BASE}/devices/unregister", json={"token": "tok-x"})
    assert r.status_code == 204
    # Second call on an already-removed token is still a success (no 404).
    r2 = api.post(f"{BASE}/devices/unregister", json={"token": "tok-x"})
    assert r2.status_code == 204


# ── Listing / unread count ──────────────────────────────────────────────────

def test_list_notifications_and_unread_count(api, db):
    _seed(db, PATIENT_A_ID, n=3)

    api.as_user(PATIENT_A_ID)
    listing = api.get(f"{BASE}").json()
    assert listing["total"] == 3
    assert len(listing["items"]) == 3
    # data payload round-trips as a dict (order-independent to avoid tie flake).
    assert {it["data"]["index"] for it in listing["items"]} == {0, 1, 2}

    count = api.get(f"{BASE}/unread-count").json()
    assert count["count"] == 3


def test_list_pagination_and_unread_only(api, db):
    _seed(db, PATIENT_A_ID, n=5)
    api.as_user(PATIENT_A_ID)

    page = api.get(f"{BASE}?limit=2&offset=0").json()
    assert page["total"] == 5 and len(page["items"]) == 2

    # Mark one read, then filter to unread only.
    first_id = page["items"][0]["id"]
    api.put(f"{BASE}/{first_id}/read")
    unread = api.get(f"{BASE}?unread_only=true").json()
    assert unread["total"] == 4


def test_mark_read_decrements_unread(api, db):
    created = _seed(db, PATIENT_A_ID, n=2)
    target = str(created[0].id)

    api.as_user(PATIENT_A_ID)
    r = api.put(f"{BASE}/{target}/read")
    assert r.status_code == 200
    assert r.json()["is_read"] is True
    assert r.json()["read_at"] is not None
    assert api.get(f"{BASE}/unread-count").json()["count"] == 1


def test_mark_all_read(api, db):
    _seed(db, PATIENT_A_ID, n=4)
    api.as_user(PATIENT_A_ID)
    r = api.put(f"{BASE}/read-all")
    assert r.status_code == 200
    assert r.json()["updated"] == 4
    assert api.get(f"{BASE}/unread-count").json()["count"] == 0


def test_cannot_read_another_users_notification(api, db):
    created = _seed(db, PATIENT_A_ID, n=1)
    foreign_id = str(created[0].id)

    # Patient B must not be able to mark Patient A's notification read.
    api.as_user(PATIENT_B_ID)
    r = api.put(f"{BASE}/{foreign_id}/read")
    assert r.status_code == 404
    # And it stays unread for A.
    api.as_user(PATIENT_A_ID)
    assert api.get(f"{BASE}/unread-count").json()["count"] == 1


def test_notifications_are_user_scoped(api, db):
    _seed(db, PATIENT_A_ID, n=2)
    _seed(db, PATIENT_B_ID, n=1)

    api.as_user(PATIENT_B_ID)
    listing = api.get(f"{BASE}").json()
    assert listing["total"] == 1


# ── Graceful push-skip (no Firebase configured) ─────────────────────────────

def test_create_notification_persists_and_skips_push_without_firebase(db):
    # FCM is disabled by default → create must not raise, and must persist.
    n = _svc(db).create_notification(
        user_id=PATIENT_A_ID, title="No push", body="saved anyway", type="system"
    )
    assert n.id is not None
    with _Session() as s:
        assert s.query(Notification).filter(Notification.id == n.id).count() == 1
