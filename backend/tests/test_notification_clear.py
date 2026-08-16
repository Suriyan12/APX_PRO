"""
Clear-all notifications + 90-day retention cleanup.

Covers:
  - DELETE /notifications/clear-all removes ONLY the caller's notifications and
    returns the deleted count (other users are never touched — security).
  - The endpoint is scoped to the authenticated user; no user id is accepted
    from the client.
  - The repository's retention delete removes old rows and keeps recent ones.

Uses the shared SQLite TestClient harness (conftest.py). A local autouse
fixture wipes notifications between tests.
"""
from datetime import datetime, timedelta, timezone


def _utcnaive() -> datetime:
    """Naive UTC 'now', matching how created_at values are compared."""
    return datetime.now(timezone.utc).replace(tzinfo=None)

import pytest

from app.models.models import Notification
from app.repositories.notification_repository import NotificationRepository
from tests.conftest import ADMIN_ID, PATIENT_A_ID, PATIENT_B_ID, _Session

BASE = "/api/v1/notifications"


@pytest.fixture(autouse=True)
def _clean_notifications():
    def _wipe():
        with _Session() as db:
            db.query(Notification).delete()
            db.commit()
    _wipe()
    yield
    _wipe()


def _seed(user_id, n, *, created_at=None):
    with _Session() as db:
        for i in range(n):
            row = Notification(
                user_id=user_id,
                title=f"N{i}",
                body="body",
                type="system",
                is_read=False,
            )
            if created_at is not None:
                row.created_at = created_at
            db.add(row)
        db.commit()


def _count(user_id=None) -> int:
    with _Session() as db:
        q = db.query(Notification)
        if user_id is not None:
            q = q.filter(Notification.user_id == user_id)
        return q.count()


# ── clear-all endpoint ─────────────────────────────────────────────────────────

def test_clear_all_deletes_only_callers_notifications(api):
    _seed(PATIENT_A_ID, 5)
    _seed(PATIENT_B_ID, 3)

    api.as_user(PATIENT_A_ID)
    r = api.delete(f"{BASE}/clear-all")
    assert r.status_code == 200
    body = r.json()
    assert body["success"] is True
    assert body["deleted_count"] == 5

    # A's notifications are gone; B's remain untouched.
    assert _count(PATIENT_A_ID) == 0
    assert _count(PATIENT_B_ID) == 3


def test_clear_all_on_empty_returns_zero(api):
    api.as_user(PATIENT_A_ID)
    r = api.delete(f"{BASE}/clear-all")
    assert r.status_code == 200
    assert r.json() == {"success": True, "deleted_count": 0}


def test_clear_all_admin_scoped_to_admin(api):
    # Admin clearing must not affect patients (and vice-versa).
    _seed(ADMIN_ID, 4)
    _seed(PATIENT_A_ID, 2)
    api.as_user(ADMIN_ID)
    r = api.delete(f"{BASE}/clear-all")
    assert r.json()["deleted_count"] == 4
    assert _count(ADMIN_ID) == 0
    assert _count(PATIENT_A_ID) == 2


def test_clear_all_then_unread_count_zero(api):
    _seed(PATIENT_A_ID, 6)
    api.as_user(PATIENT_A_ID)
    api.delete(f"{BASE}/clear-all")
    r = api.get(f"{BASE}/unread-count")
    assert r.json()["count"] == 0


# ── retention delete (repository) ──────────────────────────────────────────────

def test_delete_older_than_removes_old_keeps_recent(db):
    old = _utcnaive() - timedelta(days=120)
    recent = _utcnaive() - timedelta(days=1)
    _seed(PATIENT_A_ID, 3, created_at=old)
    _seed(PATIENT_A_ID, 2, created_at=recent)

    cutoff = _utcnaive() - timedelta(days=90)
    removed = NotificationRepository(db).delete_older_than(cutoff)

    assert removed == 3
    assert _count(PATIENT_A_ID) == 2  # the recent ones survive


def test_delete_all_for_user_is_scoped(db):
    _seed(PATIENT_A_ID, 4)
    _seed(PATIENT_B_ID, 2)
    removed = NotificationRepository(db).delete_all_for_user(PATIENT_A_ID)
    assert removed == 4
    assert _count(PATIENT_A_ID) == 0
    assert _count(PATIENT_B_ID) == 2
