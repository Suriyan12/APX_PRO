"""
Help Center tests.

Covers:
  - YouTube URL parsing (pure unit, every supported form + rejections)
  - Admin CRUD, activate/deactivate, reorder
  - The single-featured invariant
  - User visibility (active-only) + authorization (403 for non-admins)
  - Pagination and search
  - The optional publish notification: disabled by default, and, when enabled,
    one deep-linked in-app notification per active patient.

Uses the shared SQLite TestClient harness (conftest.py). A local autouse
fixture wipes help_videos + notifications between tests for isolation.
"""
import uuid

import pytest

from app.core.youtube import extract_youtube_id
from app.models.models import HelpVideo, Notification
from tests.conftest import ADMIN_ID, PATIENT_A_ID, PATIENT_B_ID, _Session

BASE = "/api/v1/help-videos"
VID = "dQw4w9WgXcQ"  # a valid 11-char id used across tests


# ── Isolation: clean Help Center tables around every test ────────────────────

@pytest.fixture(autouse=True)
def _clean_help():
    def _wipe():
        with _Session() as db:
            db.query(Notification).delete()
            db.query(HelpVideo).delete()
            db.commit()
    _wipe()
    yield
    _wipe()


# ── Helpers ──────────────────────────────────────────────────────────────────

def _payload(**overrides) -> dict:
    body = {
        "title": "How to Use APX PRO",
        "description": "Complete introduction to APX PRO",
        "category": "Getting Started",
        "youtube_url": f"https://youtube.com/watch?v={VID}",
        "is_active": True,
    }
    body.update(overrides)
    return body


def _create(api, **overrides) -> dict:
    api.as_user(ADMIN_ID)
    r = api.post(BASE, json=_payload(**overrides))
    assert r.status_code == 201, r.text
    return r.json()


# ── YouTube parsing (pure unit) ──────────────────────────────────────────────

@pytest.mark.parametrize(
    "url",
    [
        f"https://www.youtube.com/watch?v={VID}",
        f"https://youtube.com/watch?v={VID}&t=30s",
        f"http://youtube.com/watch?v={VID}",
        f"https://youtu.be/{VID}",
        f"https://youtu.be/{VID}?si=abc",
        f"https://www.youtube.com/embed/{VID}",
        f"https://www.youtube.com/shorts/{VID}",
        f"https://m.youtube.com/watch?v={VID}",
        f"youtu.be/{VID}",
        f"youtube.com/watch?v={VID}",
    ],
)
def test_extract_youtube_id_accepts_valid_forms(url):
    assert extract_youtube_id(url) == VID


@pytest.mark.parametrize(
    "url",
    [
        "",
        "not a url",
        "https://vimeo.com/123456",
        "https://example.com/watch?v=" + VID,
        "https://youtube.com/watch?v=tooShort",
        "https://youtube.com/watch",
        "https://youtu.be/",
        None,
    ],
)
def test_extract_youtube_id_rejects_invalid(url):
    assert extract_youtube_id(url) is None


# ── Authorization ────────────────────────────────────────────────────────────

def test_patient_cannot_create(api):
    api.as_user(PATIENT_A_ID)
    r = api.post(BASE, json=_payload())
    assert r.status_code == 403


def test_patient_cannot_list_admin(api):
    api.as_user(PATIENT_A_ID)
    r = api.get(f"{BASE}/admin")
    assert r.status_code == 403


def test_patient_cannot_delete(api):
    created = _create(api)
    api.as_user(PATIENT_A_ID)
    r = api.delete(f"{BASE}/{created['id']}")
    assert r.status_code == 403


# ── Create / validation ──────────────────────────────────────────────────────

def test_admin_create_extracts_id_and_thumbnail(api):
    data = _create(api)
    assert data["youtube_video_id"] == VID
    assert data["thumbnail_url"].endswith(f"/vi/{VID}/hqdefault.jpg")
    assert data["display_order"] == 0  # first video → 0
    assert data["is_active"] is True
    assert data["is_featured"] is False


def test_create_rejects_invalid_url(api):
    api.as_user(ADMIN_ID)
    r = api.post(BASE, json=_payload(youtube_url="https://vimeo.com/123"))
    assert r.status_code == 422


def test_create_rejects_unknown_category(api):
    api.as_user(ADMIN_ID)
    r = api.post(BASE, json=_payload(category="Nonexistent"))
    assert r.status_code == 422


def test_display_order_auto_increments(api):
    a = _create(api, title="A")
    b = _create(api, title="B")
    assert a["display_order"] == 0
    assert b["display_order"] == 1


# ── User visibility ──────────────────────────────────────────────────────────

def test_user_sees_only_active(api):
    _create(api, title="Active one", is_active=True)
    _create(api, title="Hidden one", is_active=False)
    api.as_user(PATIENT_A_ID)
    r = api.get(BASE)
    assert r.status_code == 200
    body = r.json()
    titles = [v["title"] for v in body["items"]]
    assert "Active one" in titles
    assert "Hidden one" not in titles
    assert body["total"] == 1


def test_user_detail_404_for_inactive_but_admin_ok(api):
    hidden = _create(api, is_active=False)
    api.as_user(PATIENT_A_ID)
    assert api.get(f"{BASE}/{hidden['id']}").status_code == 404
    api.as_user(ADMIN_ID)
    r = api.get(f"{BASE}/{hidden['id']}")
    assert r.status_code == 200
    assert r.json()["video"]["id"] == hidden["id"]


def test_detail_returns_related_same_category(api):
    v1 = _create(api, title="Intro", category="Rehabilitation")
    _create(api, title="Exercises", category="Rehabilitation")
    _create(api, title="Booking", category="Appointments")
    api.as_user(PATIENT_A_ID)
    r = api.get(f"{BASE}/{v1['id']}")
    assert r.status_code == 200
    related_titles = [v["title"] for v in r.json()["related"]]
    assert "Exercises" in related_titles
    assert "Booking" not in related_titles
    assert v1["title"] not in related_titles


def test_admin_list_includes_inactive(api):
    _create(api, title="Active", is_active=True)
    _create(api, title="Hidden", is_active=False)
    api.as_user(ADMIN_ID)
    r = api.get(f"{BASE}/admin")
    assert r.status_code == 200
    assert r.json()["total"] == 2


# ── Featured invariant ───────────────────────────────────────────────────────

def _featured_id():
    with _Session() as db:
        row = (
            db.query(HelpVideo)
            .filter(HelpVideo.is_featured == True)  # noqa: E712
            .all()
        )
        assert len(row) <= 1, "invariant violated: more than one featured video"
        return str(row[0].id) if row else None


def test_only_one_video_featured_on_create(api):
    a = _create(api, title="A", is_featured=True)
    b = _create(api, title="B", is_featured=True)
    assert _featured_id() == b["id"]  # the latest featured wins


def test_update_to_featured_moves_the_flag(api):
    a = _create(api, title="A", is_featured=True)
    b = _create(api, title="B")
    api.as_user(ADMIN_ID)
    r = api.put(f"{BASE}/{b['id']}", json={"is_featured": True})
    assert r.status_code == 200
    assert r.json()["is_featured"] is True
    assert _featured_id() == b["id"]


def test_featured_must_be_active_on_update(api):
    hidden = _create(api, is_active=False)
    api.as_user(ADMIN_ID)
    r = api.put(f"{BASE}/{hidden['id']}", json={"is_featured": True})
    assert r.status_code == 422


def test_deactivating_featured_clears_flag(api):
    a = _create(api, is_featured=True)
    api.as_user(ADMIN_ID)
    r = api.patch(f"{BASE}/{a['id']}/active", json={"is_active": False})
    assert r.status_code == 200
    assert r.json()["is_featured"] is False
    assert _featured_id() is None


# ── Update / activate / delete / reorder ─────────────────────────────────────

def test_partial_update(api):
    v = _create(api, title="Old")
    api.as_user(ADMIN_ID)
    r = api.put(f"{BASE}/{v['id']}", json={"title": "New", "category": "Appointments"})
    assert r.status_code == 200
    body = r.json()
    assert body["title"] == "New"
    assert body["category"] == "Appointments"
    assert body["youtube_video_id"] == VID  # unchanged


def test_update_url_reextracts_id(api):
    v = _create(api)
    new_id = "abcdefghijk"
    api.as_user(ADMIN_ID)
    r = api.put(f"{BASE}/{v['id']}", json={"youtube_url": f"https://youtu.be/{new_id}"})
    assert r.status_code == 200
    assert r.json()["youtube_video_id"] == new_id


def test_activate_deactivate(api):
    v = _create(api, is_active=True)
    api.as_user(ADMIN_ID)
    assert api.patch(f"{BASE}/{v['id']}/active", json={"is_active": False}).json()["is_active"] is False
    assert api.patch(f"{BASE}/{v['id']}/active", json={"is_active": True}).json()["is_active"] is True


def test_delete_then_404(api):
    v = _create(api)
    api.as_user(ADMIN_ID)
    assert api.delete(f"{BASE}/{v['id']}").status_code == 204
    assert api.get(f"{BASE}/{v['id']}").status_code == 404


def test_reorder(api):
    a = _create(api, title="A")
    b = _create(api, title="B")
    c = _create(api, title="C")
    api.as_user(ADMIN_ID)
    r = api.put(f"{BASE}/reorder", json={"items": [
        {"id": a["id"], "display_order": 2},
        {"id": b["id"], "display_order": 0},
        {"id": c["id"], "display_order": 1},
    ]})
    assert r.status_code == 200
    assert r.json()["updated"] == 3
    listing = api.get(f"{BASE}/admin").json()["items"]
    order = {v["title"]: v["display_order"] for v in listing}
    assert order == {"A": 2, "B": 0, "C": 1}


def test_reorder_unknown_id_404(api):
    a = _create(api, title="A")
    api.as_user(ADMIN_ID)
    r = api.put(f"{BASE}/reorder", json={"items": [
        {"id": a["id"], "display_order": 0},
        {"id": str(uuid.uuid4()), "display_order": 1},
    ]})
    assert r.status_code == 404


# ── Pagination / search / categories ─────────────────────────────────────────

def test_pagination(api):
    for i in range(5):
        _create(api, title=f"V{i}", category="Getting Started")
    api.as_user(PATIENT_A_ID)
    page1 = api.get(f"{BASE}?limit=2&offset=0").json()
    page2 = api.get(f"{BASE}?limit=2&offset=2").json()
    assert page1["total"] == 5
    assert len(page1["items"]) == 2
    assert len(page2["items"]) == 2
    ids1 = {v["id"] for v in page1["items"]}
    ids2 = {v["id"] for v in page2["items"]}
    assert ids1.isdisjoint(ids2)


def test_search_by_title(api):
    _create(api, title="Booking Appointments", category="Appointments")
    _create(api, title="Completing Exercises", category="Rehabilitation")
    api.as_user(PATIENT_A_ID)
    r = api.get(f"{BASE}?search=booking")
    titles = [v["title"] for v in r.json()["items"]]
    assert titles == ["Booking Appointments"]


def test_filter_by_category(api):
    _create(api, title="A", category="Appointments")
    _create(api, title="B", category="Rehabilitation")
    api.as_user(PATIENT_A_ID)
    r = api.get(f"{BASE}?category=Rehabilitation")
    titles = [v["title"] for v in r.json()["items"]]
    assert titles == ["B"]


def test_categories_endpoint(api):
    api.as_user(PATIENT_A_ID)
    r = api.get(f"{BASE}/categories")
    assert r.status_code == 200
    cats = r.json()["categories"]
    assert "Getting Started" in cats
    assert "Other" in cats


# ── Optional publish notification ────────────────────────────────────────────

def _notifications_for(user_id) -> list:
    with _Session() as db:
        return (
            db.query(Notification)
            .filter(Notification.user_id == user_id)
            .all()
        )


def test_publish_notification_disabled_by_default(api):
    # Flag defaults to False → creating an active video notifies nobody.
    _create(api, is_active=True)
    assert _notifications_for(PATIENT_A_ID) == []
    assert _notifications_for(PATIENT_B_ID) == []


def test_publish_notification_when_enabled(api, monkeypatch):
    import app.core.config as cfg
    monkeypatch.setattr(cfg.settings, "HELP_CENTER_NOTIFY_ON_PUBLISH", True)

    created = _create(api, title="Rehab Basics", is_active=True)

    for pid in (PATIENT_A_ID, PATIENT_B_ID):
        notes = _notifications_for(pid)
        assert len(notes) == 1
        n = notes[0]
        assert n.type == "help"
        assert "Rehab Basics" in n.body
        assert f"/help/{created['id']}" in (n.data or "")
    # Admins are not spammed with the patient-facing tutorial notification.
    assert _notifications_for(ADMIN_ID) == []


def test_inactive_create_does_not_notify_even_when_enabled(api, monkeypatch):
    import app.core.config as cfg
    monkeypatch.setattr(cfg.settings, "HELP_CENTER_NOTIFY_ON_PUBLISH", True)
    _create(api, is_active=False)
    assert _notifications_for(PATIENT_A_ID) == []
