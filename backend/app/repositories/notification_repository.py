"""
Notification data access layer.

All raw SQLAlchemy queries for device tokens and notifications live here. The
service layer calls these methods; route handlers never touch the ORM directly.
Each write commits and refreshes, matching the other repositories in the project.
"""
import uuid
from datetime import datetime, timezone
from typing import List, Optional, Tuple

from sqlalchemy.orm import Session

from app.models.models import DeviceToken, Notification


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class DeviceTokenRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_by_token(self, token: str) -> Optional[DeviceToken]:
        return (
            self.db.query(DeviceToken)
            .filter(DeviceToken.token == token)
            .first()
        )

    def upsert(
        self,
        user_id: uuid.UUID,
        token: str,
        platform: Optional[str],
    ) -> DeviceToken:
        """Register a device. A token is globally unique, so if it already
        exists it is reassigned to this user, reactivated, and its last-seen
        timestamp refreshed; otherwise a new row is created."""
        existing = self.get_by_token(token)
        now = _utcnow()
        if existing:
            existing.user_id = user_id
            existing.platform = platform
            existing.is_active = True
            existing.last_seen_at = now
            self.db.commit()
            self.db.refresh(existing)
            return existing

        row = DeviceToken(
            user_id=user_id,
            token=token,
            platform=platform,
            is_active=True,
            last_seen_at=now,
        )
        self.db.add(row)
        self.db.commit()
        self.db.refresh(row)
        return row

    def deactivate(self, user_id: uuid.UUID, token: str) -> bool:
        """Unregister a device for this user. Returns True if a row was
        deactivated. Scoped to the owner so one user cannot unregister
        another user's device."""
        row = (
            self.db.query(DeviceToken)
            .filter(
                DeviceToken.token == token,
                DeviceToken.user_id == user_id,
                DeviceToken.is_active == True,  # noqa: E712
            )
            .first()
        )
        if not row:
            return False
        row.is_active = False
        self.db.commit()
        return True

    def get_active_for_user(self, user_id: uuid.UUID) -> List[DeviceToken]:
        """Active push tokens for a user — the delivery targets used once a
        push transport is wired up."""
        return (
            self.db.query(DeviceToken)
            .filter(
                DeviceToken.user_id == user_id,
                DeviceToken.is_active == True,  # noqa: E712
            )
            .all()
        )


class NotificationRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create(
        self,
        user_id: uuid.UUID,
        title: str,
        body: str,
        type: Optional[str] = None,
        data: Optional[str] = None,
    ) -> Notification:
        row = Notification(
            user_id=user_id,
            title=title,
            body=body,
            type=type,
            data=data,
            is_read=False,
        )
        self.db.add(row)
        self.db.commit()
        self.db.refresh(row)
        return row

    def get_by_id(self, notification_id: uuid.UUID) -> Optional[Notification]:
        return (
            self.db.query(Notification)
            .filter(Notification.id == notification_id)
            .first()
        )

    def list_for_user(
        self,
        user_id: uuid.UUID,
        limit: int,
        offset: int,
        unread_only: bool = False,
    ) -> Tuple[List[Notification], int]:
        """One page of a user's notifications, newest first, with the total for
        pagination."""
        q = self.db.query(Notification).filter(Notification.user_id == user_id)
        if unread_only:
            q = q.filter(Notification.is_read == False)  # noqa: E712
        total = q.count()
        rows = (
            q.order_by(Notification.created_at.desc())
            .offset(offset)
            .limit(limit)
            .all()
        )
        return rows, total

    def count_unread(self, user_id: uuid.UUID) -> int:
        return (
            self.db.query(Notification)
            .filter(
                Notification.user_id == user_id,
                Notification.is_read == False,  # noqa: E712
            )
            .count()
        )

    def mark_read(self, notification: Notification) -> Notification:
        if not notification.is_read:
            notification.is_read = True
            notification.read_at = _utcnow()
            self.db.commit()
            self.db.refresh(notification)
        return notification

    def mark_all_read(self, user_id: uuid.UUID) -> int:
        """Mark every unread notification for a user as read. Returns the number
        of rows updated."""
        updated = (
            self.db.query(Notification)
            .filter(
                Notification.user_id == user_id,
                Notification.is_read == False,  # noqa: E712
            )
            .update(
                {"is_read": True, "read_at": _utcnow()},
                synchronize_session=False,
            )
        )
        self.db.commit()
        return updated
