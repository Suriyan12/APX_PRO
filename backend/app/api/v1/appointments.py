"""
Appointment HTTP adapter.

Route handlers are intentionally thin — they own HTTP concerns only:
  - Parsing path/query params
  - Injecting FastAPI dependencies (DB session, current user, BackgroundTasks)
  - Returning the correct status code
  - Scheduling background work (email)

All domain logic lives in AppointmentService.
"""
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import APIRouter, BackgroundTasks, Depends, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.models import User, UserRole
from app.core.config import settings
from app.repositories.appointment_repository import AppointmentRepository
from app.services.appointment_service import AppointmentService, IST, SLOT_DURATION_MINUTES
from app.schemas.schemas import (
    AppointmentApproveRequest,
    AppointmentCancelRequest,
    AppointmentCreate,
    AppointmentRejectRequest,
    AppointmentRescheduleRequest,
    AppointmentResponse,
    DiscountValidateRequest,
    DiscountValidateResponse,
    SlotResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter()


def _svc(db: Session) -> AppointmentService:
    return AppointmentService(AppointmentRepository(db))


# ---------------------------------------------------------------------------
# Available Slots
# ---------------------------------------------------------------------------

@router.get("/available-slots", response_model=List[SlotResponse])
def get_available_slots(date_str: str, db: Session = Depends(get_db)):
    return _svc(db).get_available_slots(date_str)


# ---------------------------------------------------------------------------
# Meeting providers (for the admin approval UI — future-proof/swappable)
# ---------------------------------------------------------------------------

@router.get("/meeting-providers")
def list_meeting_providers(current_user: User = Depends(get_current_user)):
    from app.services.meeting_providers import available_providers
    return available_providers()


# ---------------------------------------------------------------------------
# My Appointments
# ---------------------------------------------------------------------------

@router.get("/my", response_model=List[AppointmentResponse])
def get_my_appointments(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return _svc(db).get_my_appointments(current_user)


# ---------------------------------------------------------------------------
# Validate Discount Code (preview, no side effects)
# ---------------------------------------------------------------------------

@router.post("/validate-discount", response_model=DiscountValidateResponse)
def validate_discount(
    req: DiscountValidateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return _svc(db).validate_discount(req.code)


# ---------------------------------------------------------------------------
# Book Appointment
# ---------------------------------------------------------------------------

@router.post("/book", response_model=AppointmentResponse, status_code=status.HTTP_201_CREATED)
def book_appointment(
    appointment_in: AppointmentCreate,
    bg: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    appt = _svc(db).book(appointment_in, current_user)
    bg.add_task(_send_booking_email, current_user.email, current_user.full_name, appt)
    return appt


# ---------------------------------------------------------------------------
# Reschedule Appointment
# ---------------------------------------------------------------------------

@router.put("/{id}/reschedule", response_model=AppointmentResponse)
def reschedule_appointment(
    id: UUID,
    appointment_in: AppointmentRescheduleRequest,
    bg: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    appt = _svc(db).reschedule(id, appointment_in, current_user)
    # Resolve the patient (email recipient) and therapist while the DB session
    # is still open — the row may be an admin acting on a patient's booking, so
    # the recipient is always the appointment's patient, never current_user.
    #
    # The reschedule returns the appointment to PENDING, so the patient email is
    # an "awaiting approval" acknowledgement (NOT a confirmation) and the admins
    # are notified that a request needs review.
    bg.add_task(
        _send_reschedule_requested_email,
        patient_email=appt.patient.email,
        patient_name=appt.patient.full_name,
        therapist_name=(appt.admin.full_name if appt.admin_id and appt.admin else None),
        old_start=appt.previous_start_time,
        old_end=appt.previous_end_time,
        new_start=appt.start_time,
        new_end=appt.end_time,
        consultation_type=appt.consultation_type.value,
        appointment_id=str(appt.id),
    )
    # Notify every active admin that a reschedule request is awaiting review.
    admins = (
        db.query(User)
        .filter(User.role == UserRole.ADMIN, User.is_active == True)  # noqa: E712
        .all()
    )
    patient_name = appt.patient.full_name
    for adm in admins:
        bg.add_task(
            _send_reschedule_admin_email,
            admin_email=adm.email,
            admin_name=adm.full_name,
            patient_name=patient_name,
            old_start=appt.previous_start_time,
            old_end=appt.previous_end_time,
            new_start=appt.start_time,
            new_end=appt.end_time,
            consultation_type=appt.consultation_type.value,
            appointment_id=str(appt.id),
        )
    return appt


# ---------------------------------------------------------------------------
# Approve / Reject Appointment (admin only)
# ---------------------------------------------------------------------------

@router.put("/{id}/approve", response_model=AppointmentResponse)
def approve_appointment(
    id: UUID,
    bg: BackgroundTasks,
    body: Optional[AppointmentApproveRequest] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    provider = body.meeting_provider if body else None
    link = body.meeting_link if body else None
    appt = _svc(db).approve(id, current_user, meeting_provider=provider, meeting_link=link)
    bg.add_task(
        _send_approval_email,
        patient_email=appt.patient.email,
        patient_name=appt.patient.full_name,
        therapist_name=(appt.admin.full_name if appt.admin_id and appt.admin else None),
        start=appt.start_time,
        end=appt.end_time,
        consultation_type=appt.consultation_type.value,
        meeting_link=appt.meeting_link,
        appointment_id=str(appt.id),
        is_reschedule=getattr(appt, "was_reschedule", False),
    )
    return appt


@router.put("/{id}/reject", response_model=AppointmentResponse)
def reject_appointment(
    id: UUID,
    bg: BackgroundTasks,
    payload: Optional[AppointmentRejectRequest] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    reason = payload.reason if payload else None
    appt = _svc(db).reject(id, current_user, reason=reason)
    bg.add_task(
        _send_reject_email,
        patient_email=appt.patient.email,
        patient_name=appt.patient.full_name,
        therapist_name=(appt.admin.full_name if appt.admin_id and appt.admin else None),
        start=appt.start_time,
        end=appt.end_time,
        reason=appt.cancellation_reason,
        appointment_id=str(appt.id),
        consultation_type=appt.consultation_type.value,
        is_reschedule=getattr(appt, "was_reschedule", False),
    )
    return appt


# ---------------------------------------------------------------------------
# Cancel Appointment
# ---------------------------------------------------------------------------

@router.put("/{id}/cancel", response_model=AppointmentResponse)
def cancel_appointment(
    id: UUID,
    bg: BackgroundTasks,
    payload: Optional[AppointmentCancelRequest] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    reason = payload.reason if payload else None
    appt = _svc(db).cancel(id, current_user, reason=reason)
    bg.add_task(
        _send_cancel_email,
        patient_email=appt.patient.email,
        patient_name=appt.patient.full_name,
        therapist_name=(appt.admin.full_name if appt.admin_id and appt.admin else None),
        start=appt.start_time,
        end=appt.end_time,
        reason=appt.cancellation_reason,
        appointment_id=str(appt.id),
    )
    return appt


# ---------------------------------------------------------------------------
# Email notifications (run in BackgroundTasks — never block the response, and
# only after the DB transaction has already committed inside the service).
#
# Each wrapper logs success and failure; a delivery failure is swallowed so the
# appointment operation the user requested still completes successfully.
# ---------------------------------------------------------------------------

def _as_utc(dt: datetime) -> datetime:
    """DB columns are DATETIME2 (timezone-naive) holding UTC wall-clock values.
    A naive datetime passed to .astimezone() would be interpreted as MACHINE
    LOCAL time — on an IST server that displayed every emailed time 5h30m off.
    Always tag naive datetimes as UTC before any timezone conversion."""
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt


def _fmt_slot(start: datetime, end: datetime) -> tuple[str, str]:
    """Format a UTC start/end pair into IST (date_str, time_str)."""
    start_ist = _as_utc(start).astimezone(IST)
    end_ist = _as_utc(end).astimezone(IST)
    date_str = start_ist.strftime("%A, %B %d, %Y")
    time_str = f"{start_ist.strftime('%I:%M %p')} – {end_ist.strftime('%I:%M %p')} IST"
    return date_str, time_str


def _send_booking_email(patient_email: str, patient_name: str, appt) -> None:
    try:
        from app.core.email_service import send_appointment_booked_email

        # Preserve the original booking email exactly: derive the end time from
        # the fixed slot duration rather than the stored end_time.
        start_ist = _as_utc(appt.start_time).astimezone(IST)
        end_ist = start_ist + timedelta(minutes=SLOT_DURATION_MINUTES)
        date_str = start_ist.strftime("%A, %B %d, %Y")
        time_str = f"{start_ist.strftime('%I:%M %p')} – {end_ist.strftime('%I:%M %p')} IST"

        send_appointment_booked_email(
            to_email=patient_email,
            patient_name=patient_name,
            date_str=date_str,
            time_str=time_str,
            consultation_type=getattr(appt.consultation_type, "value", None),
        )
        logger.info("Booking email sent to %s", patient_email)
    except Exception:
        logger.exception("Booking email FAILED for %s", patient_email)


def _send_approval_email(
    *,
    patient_email: str,
    patient_name: str,
    therapist_name: Optional[str],
    start: datetime,
    end: datetime,
    consultation_type: str,
    meeting_link: Optional[str],
    appointment_id: str,
    is_reschedule: bool = False,
) -> None:
    try:
        from app.core.email_service import send_appointment_approved_email

        date_str, time_str = _fmt_slot(start, end)
        send_appointment_approved_email(
            to_email=patient_email,
            patient_name=patient_name,
            therapist_name=therapist_name,
            date_str=date_str,
            time_str=time_str,
            consultation_type=consultation_type,
            meeting_link=meeting_link,
            appointment_id=appointment_id,
            is_reschedule=is_reschedule,
            clinic_address=settings.CLINIC_ADDRESS,
        )
        logger.info(
            "%s email sent to %s (appt %s)",
            "Reschedule-approval" if is_reschedule else "Approval",
            patient_email, appointment_id,
        )
    except Exception:
        logger.exception("Approval email FAILED for %s (appt %s)", patient_email, appointment_id)


def _send_reject_email(
    *,
    patient_email: str,
    patient_name: str,
    therapist_name: Optional[str],
    start: datetime,
    end: datetime,
    reason: Optional[str],
    appointment_id: str,
    consultation_type: Optional[str] = None,
    is_reschedule: bool = False,
) -> None:
    try:
        from app.core.email_service import send_appointment_rejected_email

        date_str, time_str = _fmt_slot(start, end)
        send_appointment_rejected_email(
            to_email=patient_email,
            patient_name=patient_name,
            therapist_name=therapist_name,
            date_str=date_str,
            time_str=time_str,
            reason=reason,
            appointment_id=appointment_id,
            consultation_type=consultation_type,
            is_reschedule=is_reschedule,
        )
        logger.info(
            "%s email sent to %s (appt %s)",
            "Reschedule-rejection" if is_reschedule else "Rejection",
            patient_email, appointment_id,
        )
    except Exception:
        logger.exception("Rejection email FAILED for %s (appt %s)", patient_email, appointment_id)


def _send_reschedule_requested_email(
    *,
    patient_email: str,
    patient_name: str,
    therapist_name: Optional[str],
    old_start: datetime,
    old_end: datetime,
    new_start: datetime,
    new_end: datetime,
    appointment_id: str,
    consultation_type: Optional[str] = None,
) -> None:
    """Patient-facing acknowledgement that a reschedule REQUEST was received and
    is awaiting admin approval (the appointment is back to PENDING)."""
    try:
        from app.core.email_service import send_reschedule_requested_email

        old_date, old_time = _fmt_slot(old_start, old_end)
        new_date, new_time = _fmt_slot(new_start, new_end)
        send_reschedule_requested_email(
            to_email=patient_email,
            patient_name=patient_name,
            therapist_name=therapist_name,
            old_date_str=old_date,
            old_time_str=old_time,
            new_date_str=new_date,
            new_time_str=new_time,
            appointment_id=appointment_id,
            consultation_type=consultation_type,
        )
        logger.info("Reschedule-request email sent to %s (appt %s)", patient_email, appointment_id)
    except Exception:
        logger.exception("Reschedule-request email FAILED for %s (appt %s)", patient_email, appointment_id)


def _send_reschedule_admin_email(
    *,
    admin_email: str,
    admin_name: Optional[str],
    patient_name: str,
    old_start: datetime,
    old_end: datetime,
    new_start: datetime,
    new_end: datetime,
    appointment_id: str,
    consultation_type: Optional[str] = None,
) -> None:
    """Admin-facing notification that a reschedule request awaits review."""
    try:
        from app.core.email_service import send_reschedule_admin_notification_email

        old_date, old_time = _fmt_slot(old_start, old_end)
        new_date, new_time = _fmt_slot(new_start, new_end)
        send_reschedule_admin_notification_email(
            to_email=admin_email,
            admin_name=admin_name,
            patient_name=patient_name,
            old_date_str=old_date,
            old_time_str=old_time,
            new_date_str=new_date,
            new_time_str=new_time,
            consultation_type=consultation_type,
            appointment_id=appointment_id,
        )
        logger.info("Reschedule admin-notification sent to %s (appt %s)", admin_email, appointment_id)
    except Exception:
        logger.exception("Reschedule admin-notification FAILED for %s (appt %s)", admin_email, appointment_id)


def _send_cancel_email(
    *,
    patient_email: str,
    patient_name: str,
    therapist_name: Optional[str],
    start: datetime,
    end: datetime,
    reason: Optional[str],
    appointment_id: str,
) -> None:
    try:
        from app.core.email_service import send_appointment_cancelled_email

        date_str, time_str = _fmt_slot(start, end)
        send_appointment_cancelled_email(
            to_email=patient_email,
            patient_name=patient_name,
            therapist_name=therapist_name,
            date_str=date_str,
            time_str=time_str,
            reason=reason,
            appointment_id=appointment_id,
        )
        logger.info("Cancellation email sent to %s (appt %s)", patient_email, appointment_id)
    except Exception:
        logger.exception("Cancellation email FAILED for %s (appt %s)", patient_email, appointment_id)
