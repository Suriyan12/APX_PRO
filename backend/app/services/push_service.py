"""
Firebase Cloud Messaging transport.

Encapsulates all Firebase Admin SDK usage behind a small, mockable surface. The
rest of the app talks to `FirebasePushService`; nothing else imports
firebase_admin.

Design guarantees (see Phase 2 requirements):
  - Credentials come only from settings.FIREBASE_CREDENTIALS_PATH — never
    hardcoded.
  - If the SDK is not installed, or the credentials file is missing/invalid, or
    initialization fails for any reason, push is disabled and the app keeps
    running. Persisted (in-app) notifications are unaffected and no API request
    ever fails because Firebase is unavailable.
  - A send never raises to the caller; it returns a PushResult describing what
    happened, including which tokens are dead and should be deactivated.
"""
import logging
import os
from dataclasses import dataclass, field
from typing import List, Optional

from app.core.config import settings

logger = logging.getLogger(__name__)


@dataclass
class PushResult:
    """Outcome of a multicast send."""
    success_count: int = 0
    failure_count: int = 0
    invalid_tokens: List[str] = field(default_factory=list)
    # True when nothing was attempted (transport disabled/uninitialized).
    skipped: bool = False


class FirebasePushService:
    """Thin wrapper over firebase_admin.messaging.

    Initialization is best-effort and happens once per instance. `enabled` is
    True only when the SDK initialized successfully; otherwise every send is a
    no-op that reports `skipped=True`.
    """

    APP_NAME = "apx-push"

    def __init__(self) -> None:
        self._messaging = None  # the firebase_admin.messaging module when ready
        self._init()

    # ── Initialization ─────────────────────────────────────────────────────────

    def _init(self) -> None:
        if not settings.FCM_ENABLED:
            logger.info("FCM disabled (FCM_ENABLED is false); push delivery is off.")
            return

        path = settings.FIREBASE_CREDENTIALS_PATH
        if not path or not os.path.isfile(path):
            logger.warning(
                "Firebase credentials file not found at %r; push delivery disabled. "
                "Notifications will still be saved and served in-app.",
                path,
            )
            return

        try:
            import firebase_admin
            from firebase_admin import credentials, messaging

            # initialize_app can only run once per app name; reuse if present so
            # repeated construction (or a reload) does not raise.
            try:
                app = firebase_admin.get_app(self.APP_NAME)
            except ValueError:
                app = firebase_admin.initialize_app(
                    credentials.Certificate(path), name=self.APP_NAME
                )
            self._app = app
            self._messaging = messaging
            logger.info("Firebase push transport initialized (app=%s).", self.APP_NAME)
        except Exception:
            # ImportError (SDK absent), invalid JSON, bad key — all non-fatal.
            logger.warning(
                "Firebase initialization failed; push delivery disabled. "
                "Notifications remain available in-app.",
                exc_info=True,
            )
            self._messaging = None

    @property
    def enabled(self) -> bool:
        return self._messaging is not None

    # ── Sending ────────────────────────────────────────────────────────────────

    def send_to_tokens(
        self,
        tokens: List[str],
        title: str,
        body: str,
        data: Optional[dict] = None,
    ) -> PushResult:
        """Send one notification to many device tokens in a single multicast.

        Never raises. Returns a PushResult; `invalid_tokens` lists tokens the
        caller should deactivate (unregistered / invalid-argument)."""
        if not self.enabled:
            return PushResult(skipped=True)
        if not tokens:
            return PushResult()

        messaging = self._messaging
        # FCM data values must all be strings.
        str_data = {str(k): str(v) for k, v in (data or {}).items()}

        try:
            message = messaging.MulticastMessage(
                tokens=list(tokens),
                notification=messaging.Notification(title=title, body=body),
                data=str_data,
            )
            # Pass the named app explicitly — the SDK otherwise targets the
            # "default" app, which we never create (we init a named app so we
            # don't collide with phone-auth's Firebase usage).
            batch = messaging.send_each_for_multicast(message, app=self._app)
        except Exception:
            # A total send failure (network/auth) — report all as failed but
            # deactivate nothing (the tokens may be fine; the transport wasn't).
            logger.exception("Firebase multicast send failed for %d token(s).", len(tokens))
            return PushResult(failure_count=len(tokens))

        success = 0
        invalid: List[str] = []
        for token, resp in zip(tokens, batch.responses):
            if getattr(resp, "success", False):
                success += 1
                continue
            exc = getattr(resp, "exception", None)
            code = self._error_code(exc)
            if self._is_invalid_token(exc):
                invalid.append(token)
                logger.info("Push token invalid/unregistered (…%s): %s", token[-6:], code)
            else:
                logger.warning("Push delivery failed (…%s): %s", token[-6:], code)

        failure = len(tokens) - success
        logger.info(
            "Push multicast complete: %d delivered, %d failed, %d invalid token(s).",
            success, failure, len(invalid),
        )
        return PushResult(success_count=success, failure_count=failure, invalid_tokens=invalid)

    # ── Error classification ───────────────────────────────────────────────────

    @staticmethod
    def _error_code(exc) -> str:
        if exc is None:
            return "unknown"
        return str(getattr(exc, "code", "") or type(exc).__name__)

    @staticmethod
    def _is_invalid_token(exc) -> bool:
        """True when the error means the token is permanently dead and should be
        removed. Covers both the typed exceptions (UnregisteredError,
        SenderIdMismatchError) and string error codes, so it works regardless of
        the exact SDK version."""
        if exc is None:
            return False
        name = type(exc).__name__
        if name in {"UnregisteredError", "SenderIdMismatchError"}:
            return True
        code = str(getattr(exc, "code", "") or "").lower()
        return (
            "unregistered" in code
            or "not-registered" in code
            or "invalid-argument" in code
            or "invalid-registration-token" in code
        )


# ── Cached singleton ────────────────────────────────────────────────────────

_push_service: Optional[FirebasePushService] = None


def get_push_service() -> FirebasePushService:
    """Return the process-wide push service, initializing Firebase once."""
    global _push_service
    if _push_service is None:
        _push_service = FirebasePushService()
    return _push_service


# ── Background delivery helper ──────────────────────────────────────────────

def deliver_push(notification_id, user_id) -> None:
    """Deliver push for an already-persisted notification, in its OWN DB session.

    Scheduled via BackgroundTasks, so it runs after the request session has been
    closed — it must not reuse the request's session. Best-effort: never raises.
    """
    from app.core.database import SessionLocal
    from app.repositories.notification_repository import (
        DeviceTokenRepository,
        NotificationRepository,
    )
    from app.services.notification_service import NotificationService

    db = SessionLocal()
    try:
        service = NotificationService(
            NotificationRepository(db), DeviceTokenRepository(db)
        )
        service.dispatch_push(user_id, notification_id)
    except Exception:
        logger.exception("Background push delivery failed for notification %s", notification_id)
    finally:
        db.close()
