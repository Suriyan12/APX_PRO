"""
Notification retention cleanup.

A lightweight background job that hard-deletes notifications older than the
configured retention window (default 90 days), so the notifications table does
not grow without bound. Notifications are operational messages — the underlying
appointment / program / help-center records live in their own tables — so
removing old ones is safe.

The job is:
  - single bulk DELETE (see NotificationRepository.delete_older_than),
  - safe to run repeatedly (idempotent — a second run simply finds nothing),
  - self-contained (opens its own short-lived Session), and
  - fully logged (removed count per run).

It is wired to run on startup and then daily (see app/main.py). No external
scheduler is required; disable it with NOTIFICATION_CLEANUP_ENABLED=False.
"""
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from app.core.config import settings
from app.core.database import SessionLocal
from app.repositories.notification_repository import NotificationRepository

logger = logging.getLogger(__name__)


def purge_old_notifications(days: Optional[int] = None) -> int:
    """Delete notifications older than `days` (defaults to the configured
    retention window). Opens and closes its own Session. Returns the number of
    rows removed. Never raises — a cleanup failure must not affect the app."""
    retention = days if days is not None else settings.NOTIFICATION_RETENTION_DAYS
    # Naive UTC cutoff to match the naive DATETIME2 values stored in created_at.
    cutoff = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=retention)

    db = SessionLocal()
    try:
        deleted = NotificationRepository(db).delete_older_than(cutoff)
        logger.info(
            "Notification retention purge: removed %d notification(s) older than %d day(s)",
            deleted, retention,
        )
        return deleted
    except Exception:
        logger.exception("Notification retention purge failed")
        return 0
    finally:
        db.close()
