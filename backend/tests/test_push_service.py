"""
Unit tests for the Firebase push transport (Phase 2).

Firebase is NEVER contacted: the firebase_admin.messaging module is replaced
with a fake, and NotificationService is exercised with an injected fake push
service. Verifies:
  - multicast response handling (success / invalid-token / other-failure)
  - a total send failure is reported without deactivating tokens
  - a disabled transport is a no-op (skipped)
  - NotificationService deactivates invalid tokens and leaves others active
  - push failures never break notification creation / persistence
"""
import pytest

from tests.conftest import PATIENT_A_ID, _Session
from app.models.models import DeviceToken, Notification
from app.repositories.notification_repository import (
    DeviceTokenRepository,
    NotificationRepository,
)
from app.services.notification_service import NotificationService
from app.services.push_service import FirebasePushService, PushResult


@pytest.fixture(autouse=True)
def _clean():
    def _wipe():
        with _Session() as db:
            db.query(DeviceToken).delete()
            db.query(Notification).delete()
            db.commit()
    _wipe()
    yield
    _wipe()


# ── Fakes (no real Firebase) ────────────────────────────────────────────────

class _UnregisteredError(Exception):
    code = "registration-token-not-registered"


class _InternalError(Exception):
    code = "internal-error"


class _FakeResp:
    def __init__(self, success, exception=None):
        self.success = success
        self.exception = exception


class _FakeBatch:
    def __init__(self, responses):
        self.responses = responses


class _FakeMessaging:
    """Stand-in for firebase_admin.messaging."""

    def __init__(self, batch=None, raise_on_send=False):
        self._batch = batch
        self._raise = raise_on_send
        self.sent = []

    # The SDK constructors — just record/return placeholders.
    def Notification(self, **kw):
        return ("notification", kw)

    def MulticastMessage(self, **kw):
        self.sent.append(kw)
        return ("message", kw)

    def send_each_for_multicast(self, message, app=None):
        # Production sends to a NAMED app (send_each_for_multicast(msg, app=...));
        # the fake must accept that kwarg or every send raises TypeError.
        if self._raise:
            raise RuntimeError("network down")
        return self._batch


def _service_with(messaging):
    """A FirebasePushService with Firebase init bypassed and a fake messaging."""
    svc = FirebasePushService()  # FCM disabled by default → no real init
    svc._messaging = messaging
    return svc


# ── FirebasePushService.send_to_tokens ──────────────────────────────────────

def test_send_classifies_success_invalid_and_failure():
    batch = _FakeBatch([
        _FakeResp(True),                                  # good
        _FakeResp(False, _UnregisteredError()),           # dead → deactivate
        _FakeResp(False, _InternalError()),               # transient failure
    ])
    svc = _service_with(_FakeMessaging(batch=batch))

    result = svc.send_to_tokens(["good", "dead", "fail"], "T", "B", {"k": 1})

    assert result.success_count == 1
    assert result.failure_count == 2
    assert result.invalid_tokens == ["dead"]
    assert result.skipped is False
    # data values were stringified for FCM.
    assert svc._messaging.sent[0]["data"] == {"k": "1"}


def test_total_send_failure_reports_all_failed_without_deactivating():
    svc = _service_with(_FakeMessaging(raise_on_send=True))
    result = svc.send_to_tokens(["a", "b"], "T", "B")
    assert result.failure_count == 2
    assert result.invalid_tokens == []
    assert result.skipped is False


def test_disabled_transport_skips(monkeypatch):
    # Force FCM off so the test is deterministic regardless of the machine's
    # local .env (a dev box configured for real push would otherwise init it).
    from app.services import push_service as ps
    monkeypatch.setattr(ps.settings, "FCM_ENABLED", False)
    svc = FirebasePushService()  # FCM disabled → _messaging is None
    assert svc.enabled is False
    result = svc.send_to_tokens(["a"], "T", "B")
    assert result.skipped is True


def test_no_tokens_is_a_noop():
    svc = _service_with(_FakeMessaging(batch=_FakeBatch([])))
    result = svc.send_to_tokens([], "T", "B")
    assert result.success_count == 0 and result.skipped is False


def test_invalid_token_classification():
    assert FirebasePushService._is_invalid_token(_UnregisteredError()) is True
    assert FirebasePushService._is_invalid_token(_InternalError()) is False
    assert FirebasePushService._is_invalid_token(None) is False


# ── NotificationService orchestration with an injected fake push ────────────

class _FakePush:
    def __init__(self, result=None, enabled=True, raise_on_send=False):
        self.enabled = enabled
        self._result = result or PushResult(success_count=1)
        self._raise = raise_on_send
        self.calls = []

    def send_to_tokens(self, tokens, title, body, data=None):
        self.calls.append({"tokens": list(tokens), "title": title, "data": data})
        if self._raise:
            raise RuntimeError("boom")
        return self._result


def _seed_tokens_and_notification(db, tokens):
    devices = DeviceTokenRepository(db)
    for t in tokens:
        devices.upsert(PATIENT_A_ID, t, "android")
    notif = NotificationRepository(db).create(
        PATIENT_A_ID, "Title", "Body", type="system", data=None
    )
    return notif


def test_dispatch_deactivates_invalid_tokens_only(db):
    notif = _seed_tokens_and_notification(db, ["tok-good", "tok-dead"])
    push = _FakePush(result=PushResult(
        success_count=1, failure_count=1, invalid_tokens=["tok-dead"]
    ))
    svc = NotificationService(
        NotificationRepository(db), DeviceTokenRepository(db), push=push
    )

    svc.dispatch_push(PATIENT_A_ID, notif.id)

    # Both tokens were sent to; only the dead one is deactivated.
    assert set(push.calls[0]["tokens"]) == {"tok-good", "tok-dead"}
    with _Session() as s:
        good = s.query(DeviceToken).filter(DeviceToken.token == "tok-good").one()
        dead = s.query(DeviceToken).filter(DeviceToken.token == "tok-dead").one()
        assert good.is_active is True
        assert dead.is_active is False


def test_dispatch_skips_when_transport_disabled(db):
    notif = _seed_tokens_and_notification(db, ["tok-1"])
    push = _FakePush(enabled=False)
    svc = NotificationService(
        NotificationRepository(db), DeviceTokenRepository(db), push=push
    )

    svc.dispatch_push(PATIENT_A_ID, notif.id)

    assert push.calls == []  # nothing attempted
    with _Session() as s:
        assert s.query(DeviceToken).filter(DeviceToken.token == "tok-1").one().is_active is True


def test_push_failure_never_breaks_creation(db):
    push = _FakePush(raise_on_send=True)
    DeviceTokenRepository(db).upsert(PATIENT_A_ID, "tok-1", "android")
    svc = NotificationService(
        NotificationRepository(db), DeviceTokenRepository(db), push=push
    )

    # create_notification dispatches inline; the raising push must be swallowed.
    row = svc.create_notification(
        user_id=PATIENT_A_ID, title="Hi", body="There", type="system"
    )

    assert row.id is not None
    with _Session() as s:
        assert s.query(Notification).filter(Notification.id == row.id).count() == 1
