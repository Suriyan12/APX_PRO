"""
Notification business logic.

Owns the rules for the Notification Center: registering/unregistering devices,
creating and reading notifications, and (best-effort) push delivery. Route
handlers delegate here and handle only HTTP concerns.

Push delivery is intentionally decoupled: a notification is ALWAYS persisted
first, then push is attempted. When Firebase is not configured
(`settings.push_notifications_enabled` is False), push is skipped gracefully —
logged, never raised — so the Notification Center works with or without it.
"""
import json
import logging
import uuid
from typing import List, Optional

from fastapi import BackgroundTasks, HTTPException

from app.models.models import DeviceToken, Notification, User
from app.repositories.notification_repository import (
    DeviceTokenRepository,
    NotificationRepository,
)
from app.services.push_service import FirebasePushService, get_push_service

logger = logging.getLogger(__name__)


class NotificationService:
    def __init__(
        self,
        notifications: NotificationRepository,
        devices: DeviceTokenRepository,
        push: Optional[FirebasePushService] = None,
    ) -> None:
        self.notifications = notifications
        self.devices = devices
        # Injected in tests; resolved lazily to the singleton otherwise so
        # Firebase initializes at most once per process.
        self._push = push

    def _push_service(self) -> FirebasePushService:
        if self._push is None:
            self._push = get_push_service()
        return self._push

    # ── Device registration ───────────────────────────────────────────────────

    def register_device(
        self, user: User, token: str, platform: Optional[str]
    ) -> DeviceToken:
        token = (token or "").strip()
        if not token:
            raise HTTPException(status_code=400, detail="A device token is required.")
        if platform is not None:
            platform = platform.strip().lower() or None
        row = self.devices.upsert(user.id, token, platform)
        logger.info("Registered device token for user %s (platform=%s)", user.id, platform)
        return row

    def unregister_device(self, user: User, token: str) -> None:
        token = (token or "").strip()
        if not token:
            raise HTTPException(status_code=400, detail="A device token is required.")
        # Idempotent: unregistering an unknown/already-removed token is a no-op
        # success, so a client can safely call it on logout without handling 404.
        removed = self.devices.deactivate(user.id, token)
        if removed:
            logger.info("Unregistered device token for user %s", user.id)

    # ── Notification reads ─────────────────────────────────────────────────────

    def list_notifications(
        self, user: User, limit: int, offset: int, unread_only: bool
    ) -> dict:
        rows, total = self.notifications.list_for_user(
            user.id, limit=limit, offset=offset, unread_only=unread_only
        )
        return {
            "items": [self._to_dict(n) for n in rows],
            "total": total,
            "limit": limit,
            "offset": offset,
        }

    def unread_count(self, user: User) -> int:
        return self.notifications.count_unread(user.id)

    def mark_read(self, user: User, notification_id: uuid.UUID) -> dict:
        row = self.notifications.get_by_id(notification_id)
        if not row:
            raise HTTPException(status_code=404, detail="Notification not found.")
        if row.user_id != user.id:
            # Do not leak existence of other users' notifications.
            raise HTTPException(status_code=404, detail="Notification not found.")
        row = self.notifications.mark_read(row)
        return self._to_dict(row)

    def mark_all_read(self, user: User) -> int:
        updated = self.notifications.mark_all_read(user.id)
        logger.info("Marked %d notification(s) read for user %s", updated, user.id)
        return updated

    # ── Notification creation (used by other modules in later phases) ──────────

    def create_notification(
        self,
        user_id: uuid.UUID,
        title: str,
        body: str,
        type: Optional[str] = None,
        data: Optional[dict] = None,
        *,
        background_tasks: Optional[BackgroundTasks] = None,
    ) -> Notification:
        """Persist a notification, then attempt push delivery.

        The DB write is the source of truth (the Notification Center always
        works). Push is best-effort: if `background_tasks` is supplied the
        dispatch runs after the response is sent; otherwise it runs inline.
        Either way a delivery problem never affects the persisted notification.
        """
        encoded = json.dumps(data) if data is not None else None
        row = self.notifications.create(
            user_id=user_id, title=title, body=body, type=type, data=encoded
        )
        if background_tasks is not None:
            # The in-app notification is already persisted above; background ONLY
            # the push, and only when a transport is actually enabled — otherwise
            # there is nothing to deliver and no need to open a background session.
            if self._push_service().enabled:
                from app.services.push_service import deliver_push
                background_tasks.add_task(deliver_push, row.id, user_id)
        else:
            self.dispatch_push(user_id, row.id)
        return row

    # ── Push delivery (best-effort; degrades gracefully without Firebase) ──────

    def dispatch_push(self, user_id: uuid.UUID, notification_id: uuid.UUID) -> None:
        """Deliver a persisted notification to the user's active devices via FCM.

        Best-effort: never raises. When the transport is disabled it logs and
        returns; invalid/unregistered tokens reported by Firebase are marked
        inactive, while delivery to the remaining devices still counts."""
        try:
            push = self._push_service()
            if not push.enabled:
                logger.debug(
                    "Push transport disabled; notification %s saved in-app only",
                    notification_id,
                )
                return

            devices = self.devices.get_active_for_user(user_id)
            if not devices:
                logger.debug(
                    "No active device tokens for user %s; push skipped", user_id
                )
                return

            notification = self.notifications.get_by_id(notification_id)
            if notification is None:
                logger.warning(
                    "Notification %s vanished before push dispatch", notification_id
                )
                return

            payload = {"notification_id": str(notification.id)}
            if notification.type:
                payload["type"] = notification.type
            extra = self._decode_data(notification.data)
            if extra:
                payload.update(extra)

            tokens = [d.token for d in devices]
            result = push.send_to_tokens(
                tokens, notification.title, notification.body, payload
            )
            if result.skipped:
                logger.debug("Push skipped for notification %s", notification_id)
                return

            # Remove dead tokens so they aren't retried; other devices are
            # unaffected and their deliveries already counted.
            for bad in result.invalid_tokens:
                self.devices.deactivate(user_id, bad)

            logger.info(
                "Push for notification %s: %d delivered, %d failed, %d token(s) deactivated",
                notification_id,
                result.success_count,
                result.failure_count,
                len(result.invalid_tokens),
            )
        except Exception:  # pragma: no cover - defensive; delivery is best-effort
            logger.exception("Push dispatch failed for notification %s", notification_id)

    # ── Helpers ────────────────────────────────────────────────────────────────

    @staticmethod
    def _to_dict(n: Notification) -> dict:
        return {
            "id": n.id,
            "title": n.title,
            "body": n.body,
            "type": n.type,
            "data": NotificationService._decode_data(n.data),
            "is_read": n.is_read,
            "read_at": n.read_at,
            "created_at": n.created_at,
        }

    @staticmethod
    def _decode_data(raw: Optional[str]) -> Optional[dict]:
        if not raw:
            return None
        try:
            value = json.loads(raw)
            return value if isinstance(value, dict) else None
        except (ValueError, TypeError):
            # A malformed payload must never break the list response.
            return None
