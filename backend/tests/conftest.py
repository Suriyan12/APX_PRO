"""
Test configuration for the APX PRO appointment module.

Uses SQLite (in-process, no external service) to run fully isolated from the
production MSSQL database.  A single switchable TestClient lets multi-user
scenarios (slot conflict tests) work without clashing dependency overrides.
"""

import os
import uuid
import pytest
from datetime import datetime, timezone, timedelta

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.core.database import Base, get_db
from app.api.deps import get_current_user
from app.models.models import User, UserRole, Appointment

# ─── SQLite test database ─────────────────────────────────────────────────────

TEST_DB_PATH = "./test_apx_appointments.db"
TEST_DB_URL  = f"sqlite:///{TEST_DB_PATH}"

_engine  = create_engine(TEST_DB_URL, connect_args={"check_same_thread": False})
_Session = sessionmaker(bind=_engine, autocommit=False, autoflush=False)

# ─── Fixed user IDs ───────────────────────────────────────────────────────────

PATIENT_A_ID = uuid.UUID("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
PATIENT_B_ID = uuid.UUID("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
ADMIN_ID     = uuid.UUID("cccccccc-cccc-cccc-cccc-cccccccccccc")

# ─── Session-scoped setup: create tables + seed users once ───────────────────

@pytest.fixture(scope="session", autouse=True)
def _db_setup():
    Base.metadata.create_all(bind=_engine)

    with _Session() as db:
        seeds = [
            (PATIENT_A_ID, "patient_a@test.com", "Patient A", UserRole.PATIENT),
            (PATIENT_B_ID, "patient_b@test.com", "Patient B", UserRole.PATIENT),
            (ADMIN_ID,     "admin@test.com",     "Test Admin", UserRole.ADMIN),
        ]
        for uid, email, name, role in seeds:
            if not db.get(User, uid):
                db.add(User(
                    id=uid,
                    email=email,
                    full_name=name,
                    password_hash="test-hash",
                    role=role,
                    is_active=True,
                ))
        db.commit()

    yield

    Base.metadata.drop_all(bind=_engine)
    _engine.dispose()          # release all pooled connections before deleting
    if os.path.exists(TEST_DB_PATH):
        try:
            os.remove(TEST_DB_PATH)
        except PermissionError:
            pass               # Windows: file still open by OS — safe to ignore


# ─── Email guard: NEVER send real SMTP from tests ────────────────────────────
#
# Without this, every pytest run fired dozens of real Gmail sends to fake
# addresses (patient_a@test.com …), which bounce and poison the SMTP sender
# reputation — causing real production emails to be throttled/spam-filtered.
# All outbound email is captured here instead; tests can assert on it via the
# `emails` fixture.

@pytest.fixture(autouse=True)
def _email_outbox(monkeypatch):
    captured: list[dict] = []
    import app.core.email_service as es

    def _fake_send_email(to_email: str, subject: str, html_body: str) -> None:
        captured.append({"to": to_email, "subject": subject, "html": html_body})

    monkeypatch.setattr(es, "send_email", _fake_send_email)
    yield captured


@pytest.fixture
def emails(_email_outbox):
    """Outbound emails captured during the test (list of {to, subject, html})."""
    return _email_outbox


# ─── Function-scoped: wipe appointments before every test ────────────────────

@pytest.fixture(autouse=True)
def _clean_appointments():
    """Guarantee a clean slate — no leftover appointments between tests."""
    with _Session() as db:
        db.query(Appointment).delete()
        db.commit()
    yield
    with _Session() as db:
        db.query(Appointment).delete()
        db.commit()


# ─── Per-test DB session ─────────────────────────────────────────────────────

@pytest.fixture
def db():
    session = _Session()
    try:
        yield session
    finally:
        session.close()


# ─── Switchable multi-user TestClient ────────────────────────────────────────

class SwitchableClient:
    """
    A thin wrapper around TestClient that lets tests switch the active user
    mid-test without recreating the client or resetting dependency overrides.

    Usage:
        def test_conflict(api):
            api.as_user(PATIENT_A_ID)
            r1 = api.post("/api/v1/appointments/book", json={...})
            api.as_user(PATIENT_B_ID)
            r2 = api.post("/api/v1/appointments/book", json={...})
    """

    def __init__(self, client: TestClient, db_session, state: dict):
        self._client  = client
        self._db      = db_session
        self._state   = state  # mutable dict read by the dependency override

    def as_user(self, user_id: uuid.UUID) -> "SwitchableClient":
        self._state["user"] = self._db.get(User, user_id)
        return self

    # Proxy HTTP verbs
    def get(self, *a, **kw):    return self._client.get(*a, **kw)
    def post(self, *a, **kw):   return self._client.post(*a, **kw)
    def put(self, *a, **kw):    return self._client.put(*a, **kw)
    def delete(self, *a, **kw): return self._client.delete(*a, **kw)
    def patch(self, *a, **kw):  return self._client.patch(*a, **kw)


@pytest.fixture
def api(db):
    """
    Returns a SwitchableClient.  Call api.as_user(USER_ID) before each request.
    """
    state = {"user": None}

    def _override_db():
        yield db

    def _override_user():
        if state["user"] is None:
            raise RuntimeError("Call api.as_user(user_id) before making a request.")
        return state["user"]

    app.dependency_overrides[get_db]           = _override_db
    app.dependency_overrides[get_current_user] = _override_user

    with TestClient(app, raise_server_exceptions=True) as client:
        yield SwitchableClient(client, db, state)

    app.dependency_overrides.clear()


# ─── Slot-time helpers ────────────────────────────────────────────────────────

def future_slot(*, days: int = 1, hour: int = 5, minute: int = 0):
    """
    Return (start_iso, end_iso) for a 30-minute slot in the future (UTC).

    UTC hour=5 → IST 10:30 AM, safely within the 9 AM–10 PM IST booking window.
    Use different `days` values in each test to avoid cross-test slot collisions.
    """
    base = datetime.now(timezone.utc).replace(
        hour=hour, minute=minute, second=0, microsecond=0
    ) + timedelta(days=days)
    return base.isoformat(), (base + timedelta(minutes=30)).isoformat()


def past_slot():
    """Return a slot that already ended 2 hours ago."""
    start = datetime.now(timezone.utc) - timedelta(hours=2, minutes=30)
    return start.isoformat(), (start + timedelta(minutes=30)).isoformat()
