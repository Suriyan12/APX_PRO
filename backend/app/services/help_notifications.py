"""
Help Center → notification wiring.

Bridges a "new help video published" event to the Notification Center, mirroring
the appointment adapter: content comes from the centralized templates and
delivery goes through NotificationService — this module never touches Firebase
or the notification tables directly.

This producer is OPTIONAL and DISABLED by default. The route only calls it when
`settings.HELP_CENTER_NOTIFY_ON_PUBLISH` is True, so the architecture is present
but dormant until a clinic explicitly enables it. As with every producer, a
failure here is logged and swallowed — it must NEVER break the publish itself.
"""
import logging
from uuid import UUID

from fastapi import BackgroundTasks
from sqlalchemy.orm import Session

from app.models.models import HelpVideo, User, UserRole
from app.repositories.notification_repository import (
    DeviceTokenRepository,
    NotificationRepository,
)
from app.services import notification_templates as templates
from app.services.notification_service import NotificationService

logger = logging.getLogger(__name__)


def _service(db: Session) -> NotificationService:
    return NotificationService(NotificationRepository(db), DeviceTokenRepository(db))


def _active_patient_ids(db: Session) -> list:
    rows = (
        db.query(User.id)
        .filter(User.role == UserRole.PATIENT, User.is_active == True)  # noqa: E712
        .all()
    )
    return [r[0] for r in rows]


def notify_help_video_published(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    video: HelpVideo,
) -> None:
    """Notify every active patient that a new Help Center video is available.

    One notification per patient, deep-linked to the video (/help/{id}). Guarded
    by the caller behind settings.HELP_CENTER_NOTIFY_ON_PUBLISH."""
    try:
        content = templates.help_video_published(video.title, video.id)
        svc = _service(db)
        recipient_ids = _active_patient_ids(db)
        for user_id in recipient_ids:
            svc.create_notification(
                user_id=user_id,
                title=content.title,
                body=content.body,
                type=content.type,
                data=content.data,
                background_tasks=background_tasks,
            )
        logger.info(
            "Help-video-published notifications created for %d patient(s) (video=%s)",
            len(recipient_ids), video.id,
        )
    except Exception:
        logger.exception(
            "Failed to create help-video-published notifications for %s", video.id
        )
