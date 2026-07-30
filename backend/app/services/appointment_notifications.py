"""
Appointment → notification wiring.

Bridges appointment events to the Notification Center. These functions build
content from the centralized templates and delegate to NotificationService —
the appointment adapter never touches Firebase or the notification tables
directly.

Each function:
  - creates the in-app notification synchronously on the caller's DB session
    (so it participates in the request and is immediately visible), and
  - lets NotificationService background only the push delivery via the supplied
    BackgroundTasks (Phase 1/2 contract).

Every function is wrapped so a notification failure is logged and swallowed — a
problem here must NEVER break the underlying appointment operation.
"""
import logging
from typing import Optional
from uuid import UUID

from fastapi import BackgroundTasks
from sqlalchemy.orm import Session

from app.models.models import User, UserRole
from app.repositories.notification_repository import (
    DeviceTokenRepository,
    NotificationRepository,
)
from app.services import notification_templates as templates
from app.services.notification_service import NotificationService

logger = logging.getLogger(__name__)


def _service(db: Session) -> NotificationService:
    return NotificationService(NotificationRepository(db), DeviceTokenRepository(db))


def _active_admin_ids(db: Session) -> list:
    rows = (
        db.query(User.id)
        .filter(User.role == UserRole.ADMIN, User.is_active == True)  # noqa: E712
        .all()
    )
    return [r[0] for r in rows]


def notify_appointment_requested(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_name: str,
    when_str: str,
) -> None:
    """Notify every active admin that a patient requested an appointment."""
    try:
        svc = _service(db)
        content = templates.appointment_requested(patient_name, appointment_id, when_str)
        for admin_id in _active_admin_ids(db):
            svc.create_notification(
                user_id=admin_id,
                title=content.title,
                body=content.body,
                type=content.type,
                data=content.data,
                background_tasks=background_tasks,
            )
    except Exception:
        logger.exception(
            "Failed to create appointment-requested notifications for %s", appointment_id
        )


def notify_appointment_approved(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_id: UUID,
    when_str: str,
    is_online: bool,
) -> None:
    """Notify the patient that their appointment was approved."""
    try:
        content = templates.appointment_approved(appointment_id, when_str, is_online)
        _service(db).create_notification(
            user_id=patient_id,
            title=content.title,
            body=content.body,
            type=content.type,
            data=content.data,
            background_tasks=background_tasks,
        )
    except Exception:
        logger.exception(
            "Failed to create appointment-approved notification for %s", appointment_id
        )


def notify_appointment_rejected(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_id: UUID,
    when_str: str,
    reason: Optional[str] = None,
) -> None:
    """Notify the patient that their appointment request was declined."""
    try:
        content = templates.appointment_rejected(appointment_id, when_str, reason)
        _service(db).create_notification(
            user_id=patient_id,
            title=content.title,
            body=content.body,
            type=content.type,
            data=content.data,
            background_tasks=background_tasks,
        )
    except Exception:
        logger.exception(
            "Failed to create appointment-rejected notification for %s", appointment_id
        )
