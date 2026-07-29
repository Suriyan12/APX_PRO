"""
Appointment business logic layer.

This class owns all domain rules: time validation, slot conflict checks,
discount application, and ownership guards. Route handlers delegate here
and handle only HTTP concerns (status codes, BackgroundTasks).
"""
from datetime import datetime, timedelta, timezone
from typing import List
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.models import (
    Appointment,
    AppointmentStatus,
    ConsultationType,
    DiscountCode,
    DiscountType,
    User,
    UserRole,
)
from app.repositories.appointment_repository import AppointmentRepository
from app.schemas.schemas import (
    AppointmentCreate,
    AppointmentRescheduleRequest,
    SlotResponse,
)

IST = ZoneInfo("Asia/Kolkata")
SLOT_DURATION_MINUTES = 30
SLOT_START_HOUR = 9     # 9:00 AM IST
SLOT_END_HOUR = 22      # 10:00 PM IST (last slot ends at 10:00 PM)
CONSULTATION_FEE = 0.00
CANCEL_NOTICE_HOURS = 2


def _utc(dt: datetime) -> datetime:
    """Normalize any datetime to UTC.

    CRITICAL: aware datetimes must be CONVERTED with astimezone(), not returned
    as-is. The DB columns are naive DATETIME2 — pyodbc silently DROPS the tzinfo
    on insert, keeping only the wall-clock. Returning a +05:30 datetime here
    (Flutter sends the IST slot strings from /available-slots verbatim) stored
    the IST wall-clock as if it were UTC, shifting every app-made booking by
    5h30m in emails, slot-conflict checks and the availability grid.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _calc_discount(code: DiscountCode, fee: float) -> float:
    val = float(code.discount_value)
    if code.discount_type == DiscountType.PERCENTAGE:
        return min(round(val * fee / 100, 2), fee)
    return min(val, fee)


def _validate_discount_code(code_str: str, repo: AppointmentRepository, now: datetime) -> DiscountCode:
    code = (
        repo.db.query(DiscountCode)
        .filter(
            DiscountCode.code == code_str.upper().strip(),
            DiscountCode.is_active.is_(True),
        )
        .first()
    )
    if not code:
        raise HTTPException(status_code=404, detail="Invalid discount code.")
    if code.valid_from and _utc(code.valid_from) > now:
        raise HTTPException(status_code=400, detail="This discount code is not active yet.")
    if code.valid_until and _utc(code.valid_until) < now:
        raise HTTPException(status_code=400, detail="This discount code has expired.")
    if code.max_uses is not None and code.used_count >= code.max_uses:
        raise HTTPException(status_code=400, detail="This discount code has reached its usage limit.")
    return code


class AppointmentService:
    def __init__(self, repo: AppointmentRepository) -> None:
        self.repo = repo

    # ------------------------------------------------------------------
    # Available slots
    # ------------------------------------------------------------------

    def get_available_slots(self, date_str: str) -> List[SlotResponse]:
        try:
            base = datetime.strptime(date_str, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(
                status_code=400,
                detail="Invalid date format. Use YYYY-MM-DD.",
            )

        day_open = base.replace(
            hour=SLOT_START_HOUR, minute=0, second=0, microsecond=0, tzinfo=IST
        )
        day_close = base.replace(
            hour=SLOT_END_HOUR, minute=0, second=0, microsecond=0, tzinfo=IST
        )
        booked_utc = self.repo.booked_starts_in_window(day_open, day_close)

        now = datetime.now(timezone.utc)
        slots, current = [], day_open
        while current < day_close:
            end = current + timedelta(minutes=SLOT_DURATION_MINUTES)
            current_utc = current.astimezone(timezone.utc)
            if current_utc > now and current_utc not in booked_utc:
                slots.append(SlotResponse(start_time=current, end_time=end))
            current = end
        return slots

    # ------------------------------------------------------------------
    # My appointments
    # ------------------------------------------------------------------

    def get_my_appointments(self, current_user: User) -> List[Appointment]:
        if current_user.role == UserRole.ADMIN:
            # Admins see all appointments in the system
            return self.repo.get_all()
        return self.repo.get_for_patient(current_user.id)

    # ------------------------------------------------------------------
    # Book
    # ------------------------------------------------------------------

    def book(
        self,
        appointment_in: AppointmentCreate,
        current_user: User,
    ) -> Appointment:
        now = datetime.now(timezone.utc)
        start = _utc(appointment_in.start_time)
        end = _utc(appointment_in.end_time)

        if start <= now:
            raise HTTPException(
                status_code=400,
                detail="Cannot book an appointment in the past.",
            )
        if end <= start:
            raise HTTPException(
                status_code=400,
                detail="End time must be after start time.",
            )
        if self.repo.has_global_overlap(start, end):
            raise HTTPException(
                status_code=409,
                detail="This slot has just been taken. Please select another time.",
            )
        if self.repo.has_patient_overlap(current_user.id, start, end):
            raise HTTPException(
                status_code=400,
                detail="You already have an appointment during this time.",
            )

        discount_code_id = None
        discount_code_used = None
        discount_amount = 0.0
        final_amount = CONSULTATION_FEE

        if appointment_in.discount_code:
            code = _validate_discount_code(appointment_in.discount_code, self.repo, now)
            discount_amount = _calc_discount(code, CONSULTATION_FEE)
            final_amount = round(CONSULTATION_FEE - discount_amount, 2)
            discount_code_id = code.id
            discount_code_used = code.code
            # Atomic increment — handles concurrent requests with max_uses limits
            if not self.repo.increment_discount_count_safe(code):
                raise HTTPException(
                    status_code=400,
                    detail="This discount code has just reached its usage limit.",
                )

        try:
            return self.repo.create(
                patient_id=current_user.id,
                admin_id=appointment_in.admin_id,
                start_time=start,
                end_time=end,
                notes=appointment_in.notes,
                consultation_type=appointment_in.consultation_type,
                consultation_fee=CONSULTATION_FEE,
                discount_code_id=discount_code_id,
                discount_code_used=discount_code_used,
                discount_amount=discount_amount,
                final_amount=final_amount,
            )
        except Exception:
            # The discount count was already incremented above; if the booking
            # insert fails, give it back so the code isn't silently burned.
            if discount_code_id:
                self.repo.restore_discount_count(discount_code_id)
            raise

    # ------------------------------------------------------------------
    # Approve / Reject (admin only)
    # ------------------------------------------------------------------

    def approve(
        self,
        id: UUID,
        current_user: User,
        meeting_provider: str | None = None,
        meeting_link: str | None = None,
    ) -> Appointment:
        self._require_admin(current_user)
        appt = self.repo.get_by_id(id)
        if not appt:
            raise HTTPException(status_code=404, detail="Appointment not found.")
        if appt.status not in (AppointmentStatus.PENDING, AppointmentStatus.RESCHEDULED):
            raise HTTPException(
                status_code=400,
                detail=f"Only a pending appointment can be approved (current: {appt.status.value}).",
            )

        provider_id = None
        link = None
        if appt.consultation_type == ConsultationType.ONLINE:
            # Online consults require a validated meeting link. The provider is
            # abstracted so Google Meet can be swapped without touching this flow.
            from app.services.meeting_providers import (
                DEFAULT_PROVIDER_ID,
                MeetingProviderError,
                validate_meeting_link,
            )
            provider_id = (meeting_provider or DEFAULT_PROVIDER_ID).strip()
            if not meeting_link or not meeting_link.strip():
                raise HTTPException(
                    status_code=400,
                    detail="A meeting link is required to approve an online consultation.",
                )
            try:
                link = validate_meeting_link(provider_id, meeting_link)
            except MeetingProviderError as e:
                raise HTTPException(status_code=400, detail=str(e))
        # Physical visits never carry a meeting link, even if one was sent.

        # Capture BEFORE the repo clears it, so the route can pick the correct
        # email (reschedule-approval vs initial approval).
        was_reschedule = bool(appt.reschedule_pending)
        updated = self.repo.approve(appt, meeting_provider=provider_id, meeting_link=link)
        updated.was_reschedule = was_reschedule  # transient; ignored by response schema
        return updated

    def reject(self, id: UUID, current_user: User, reason: str | None = None) -> Appointment:
        self._require_admin(current_user)
        appt = self.repo.get_by_id(id)
        if not appt:
            raise HTTPException(status_code=404, detail="Appointment not found.")
        if appt.status in (
            AppointmentStatus.CANCELLED,
            AppointmentStatus.REJECTED,
            AppointmentStatus.COMPLETED,
        ):
            raise HTTPException(
                status_code=400,
                detail=f"This appointment cannot be rejected (current: {appt.status.value}).",
            )
        # Free any discount hold, mirroring cancellation.
        if appt.discount_code_id:
            self.repo.restore_discount_count(appt.discount_code_id)
        was_reschedule = bool(appt.reschedule_pending)
        updated = self.repo.reject(appt, reason=(reason.strip() if reason and reason.strip() else None))
        updated.was_reschedule = was_reschedule  # transient; ignored by response schema
        return updated

    # ------------------------------------------------------------------
    # Cancel
    # ------------------------------------------------------------------

    def cancel(
        self,
        id: UUID,
        current_user: User,
        reason: str | None = None,
    ) -> Appointment:
        appt = self._require_owned(id, current_user)
        now = datetime.now(timezone.utc)
        start = _utc(appt.start_time)

        if start <= now:
            raise HTTPException(
                status_code=400,
                detail="Cannot cancel a past appointment.",
            )
        if start < now + timedelta(hours=CANCEL_NOTICE_HOURS):
            raise HTTPException(
                status_code=400,
                detail=f"Appointments must be cancelled at least {CANCEL_NOTICE_HOURS} hours in advance.",
            )
        if appt.status == AppointmentStatus.CANCELLED:
            raise HTTPException(status_code=400, detail="Appointment is already cancelled.")

        if appt.discount_code_id:
            self.repo.restore_discount_count(appt.discount_code_id)

        return self.repo.set_status(
            appt,
            AppointmentStatus.CANCELLED,
            cancellation_reason=(reason.strip() if reason and reason.strip() else None),
        )

    # ------------------------------------------------------------------
    # Reschedule
    # ------------------------------------------------------------------

    def reschedule(
        self,
        id: UUID,
        appointment_in: AppointmentRescheduleRequest,
        current_user: User,
    ) -> Appointment:
        appt = self._require_owned(id, current_user)
        now = datetime.now(timezone.utc)

        if _utc(appt.start_time) <= now:
            raise HTTPException(
                status_code=400,
                detail="Cannot reschedule a past appointment.",
            )

        new_start = _utc(appointment_in.start_time)
        new_end = _utc(appointment_in.end_time)

        if new_start <= now:
            raise HTTPException(status_code=400, detail="New slot must be in the future.")
        if new_end <= new_start:
            raise HTTPException(status_code=400, detail="End time must be after start time.")
        if self.repo.has_global_overlap(new_start, new_end, exclude_id=id):
            raise HTTPException(
                status_code=409,
                detail="This slot has just been taken. Please select another time.",
            )

        # Capture the pre-reschedule slot BEFORE the repo mutates the row, so the
        # notification email can show the patient both the old and new times.
        previous_start = _utc(appt.start_time)
        previous_end = _utc(appt.end_time)

        updated = self.repo.reschedule(
            appt, new_start, new_end, appointment_in.notes,
            consultation_type=appointment_in.consultation_type,
        )
        # Transient (non-persisted) attributes — read by the route to build the
        # email. Pydantic's AppointmentResponse ignores them, so they never leak
        # into the API response.
        updated.previous_start_time = previous_start
        updated.previous_end_time = previous_end
        return updated

    # ------------------------------------------------------------------
    # Validate discount (preview only — does not mutate)
    # ------------------------------------------------------------------

    def validate_discount(self, code_str: str) -> dict:
        now = datetime.now(timezone.utc)
        code = _validate_discount_code(code_str, self.repo, now)
        discount_amount = _calc_discount(code, CONSULTATION_FEE)
        final = round(CONSULTATION_FEE - discount_amount, 2)
        if code.discount_type == DiscountType.PERCENTAGE:
            msg = f"{int(code.discount_value)}% off applied — you save ₹{discount_amount:.0f}"
        else:
            msg = f"₹{discount_amount:.0f} flat discount applied"
        return {
            "code": code.code,
            "discount_type": code.discount_type,
            "discount_value": float(code.discount_value),
            "discount_amount": discount_amount,
            "original_fee": CONSULTATION_FEE,
            "final_amount": final,
            "message": msg,
        }

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _require_owned(self, id: UUID, current_user: User) -> Appointment:
        appt = self.repo.get_by_id(id)
        if not appt:
            raise HTTPException(status_code=404, detail="Appointment not found.")
        if appt.patient_id != current_user.id and current_user.role != UserRole.ADMIN:
            raise HTTPException(status_code=403, detail="Not authorized.")
        return appt

    @staticmethod
    def _require_admin(current_user: User) -> None:
        if current_user.role != UserRole.ADMIN:
            raise HTTPException(status_code=403, detail="Admin access required.")
