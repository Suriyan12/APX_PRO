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


def _notify_admins(
    db: Session,
    background_tasks: BackgroundTasks,
    content: "templates.NotificationContent",
) -> None:
    """Fan a single piece of content out to every active admin (one notification
    each). Exactly one notification per admin — never duplicated."""
    svc = _service(db)
    for admin_id in _active_admin_ids(db):
        svc.create_notification(
            user_id=admin_id,
            title=content.title,
            body=content.body,
            type=content.type,
            data=content.data,
            background_tasks=background_tasks,
        )


def _notify_user(
    db: Session,
    background_tasks: BackgroundTasks,
    user_id: UUID,
    content: "templates.NotificationContent",
) -> None:
    """Deliver a single notification to one user."""
    _service(db).create_notification(
        user_id=user_id,
        title=content.title,
        body=content.body,
        type=content.type,
        data=content.data,
        background_tasks=background_tasks,
    )


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
        content = templates.appointment_requested(patient_name, appointment_id, when_str)
        _notify_admins(db, background_tasks, content)
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
        _notify_user(db, background_tasks, patient_id, content)
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
        _notify_user(db, background_tasks, patient_id, content)
    except Exception:
        logger.exception(
            "Failed to create appointment-rejected notification for %s", appointment_id
        )


# ── Reschedule ────────────────────────────────────────────────────────────────

def notify_appointment_reschedule_requested(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_name: str,
    old_when: str,
    new_when: str,
) -> None:
    """Notify every active admin that a patient requested a reschedule.

    Wired to the reschedule route so the admins' Notification Center reflects the
    request the same way an initial booking does — this closes the gap where a
    reschedule only sent email and produced no in-app/push notification.
    """
    try:
        content = templates.appointment_reschedule_requested(
            patient_name, appointment_id, old_when, new_when
        )
        _notify_admins(db, background_tasks, content)
    except Exception:
        logger.exception(
            "Failed to create reschedule-requested notifications for %s", appointment_id
        )


def notify_appointment_reschedule_approved(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_id: UUID,
    when_str: str,
    is_online: bool,
) -> None:
    """Notify the patient that their reschedule request was approved."""
    try:
        content = templates.appointment_reschedule_approved(
            appointment_id, when_str, is_online
        )
        _notify_user(db, background_tasks, patient_id, content)
    except Exception:
        logger.exception(
            "Failed to create reschedule-approved notification for %s", appointment_id
        )


def notify_appointment_reschedule_rejected(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_id: UUID,
    when_str: str,
    reason: Optional[str] = None,
) -> None:
    """Notify the patient that their reschedule request was declined."""
    try:
        content = templates.appointment_reschedule_rejected(
            appointment_id, when_str, reason
        )
        _notify_user(db, background_tasks, patient_id, content)
    except Exception:
        logger.exception(
            "Failed to create reschedule-rejected notification for %s", appointment_id
        )


# ── Cancellation ──────────────────────────────────────────────────────────────

def notify_appointment_cancelled_by_patient(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_name: str,
    when_str: str,
    reason: Optional[str] = None,
) -> None:
    """Notify every active admin that a patient cancelled their appointment."""
    try:
        content = templates.appointment_cancelled_by_patient(
            patient_name, appointment_id, when_str, reason
        )
        _notify_admins(db, background_tasks, content)
    except Exception:
        logger.exception(
            "Failed to create patient-cancellation notifications for %s", appointment_id
        )


def notify_appointment_cancelled_by_admin(
    db: Session,
    background_tasks: BackgroundTasks,
    *,
    appointment_id: UUID,
    patient_id: UUID,
    when_str: str,
    reason: Optional[str] = None,
) -> None:
    """Notify the patient that the clinic cancelled their appointment."""
    try:
        content = templates.appointment_cancelled_by_admin(
            appointment_id, when_str, reason
        )
        _notify_user(db, background_tasks, patient_id, content)
    except Exception:
        logger.exception(
            "Failed to create admin-cancellation notification for %s", appointment_id
        )
