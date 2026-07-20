"""
Appointment data access layer.

All raw SQLAlchemy queries live here. The service layer calls these methods;
route handlers never touch the ORM directly.
"""
from datetime import datetime, timezone
from typing import List, Optional, Set
from uuid import UUID

from sqlalchemy.orm import Session, joinedload

from app.models.models import Appointment, AppointmentStatus, ConsultationType, DiscountCode

# Statuses that occupy a slot (prevent double-booking). REJECTED and CANCELLED
# free the slot; APPROVED (admin-confirmed) holds it like SCHEDULED/PENDING.
_ACTIVE = [
    AppointmentStatus.SCHEDULED,
    AppointmentStatus.RESCHEDULED,
    AppointmentStatus.PENDING,
    AppointmentStatus.APPROVED,
]


def _utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


class AppointmentRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ------------------------------------------------------------------
    # Reads
    # ------------------------------------------------------------------

    def get_by_id(self, id: UUID) -> Optional[Appointment]:
        return self.db.query(Appointment).filter(Appointment.id == id).first()

    def get_for_patient(self, patient_id: UUID) -> List[Appointment]:
        return (
            self.db.query(Appointment)
            .options(joinedload(Appointment.patient))
            .filter(Appointment.patient_id == patient_id)
            .order_by(Appointment.start_time.desc())
            .all()
        )

    def get_all(self) -> List[Appointment]:
        """Admin view — all appointments in the system."""
        return (
            self.db.query(Appointment)
            .options(joinedload(Appointment.patient))  # avoid N+1 on patient_name
            .order_by(Appointment.start_time.desc())
            .all()
        )

    def booked_starts_in_window(
        self, day_open: datetime, day_close: datetime
    ) -> Set[datetime]:
        """UTC datetimes of every active appointment start inside [day_open, day_close)."""
        rows = (
            self.db.query(Appointment.start_time)
            .filter(
                Appointment.start_time >= day_open.astimezone(timezone.utc),
                Appointment.start_time < day_close.astimezone(timezone.utc),
                Appointment.status.in_(_ACTIVE),
            )
            .all()
        )
        return {_utc(r[0]) for r in rows}

    def has_global_overlap(
        self,
        start: datetime,
        end: datetime,
        exclude_id: Optional[UUID] = None,
    ) -> bool:
        """True if any active appointment overlaps [start, end).

        A PENDING request reserves its slot exactly like an APPROVED one, so a
        slot is held from the moment a booking/reschedule request is submitted
        until it is rejected or cancelled (see _ACTIVE).

        On MSSQL the UPDLOCK+HOLDLOCK hint takes a range lock on the checked
        window until the surrounding transaction commits, so two concurrent
        requests for the same slot serialize instead of both passing the check
        and double-booking (check-then-insert race). No-op on other dialects.
        """
        q = self.db.query(Appointment).with_hint(
            Appointment, "WITH (UPDLOCK, HOLDLOCK)", dialect_name="mssql"
        ).filter(
            Appointment.start_time < end,
            Appointment.end_time > start,
            Appointment.status.in_(_ACTIVE),
        )
        if exclude_id:
            q = q.filter(Appointment.id != exclude_id)
        return q.first() is not None

    def has_patient_overlap(
        self, patient_id: UUID, start: datetime, end: datetime
    ) -> bool:
        """True if this patient already has a non-cancelled appointment in the window."""
        return (
            self.db.query(Appointment)
            .filter(
                Appointment.patient_id == patient_id,
                Appointment.start_time < end,
                Appointment.end_time > start,
                Appointment.status.notin_(
                    [AppointmentStatus.CANCELLED, AppointmentStatus.REJECTED]
                ),
            )
            .first()
            is not None
        )

    # ------------------------------------------------------------------
    # Writes
    # ------------------------------------------------------------------

    def create(
        self,
        *,
        patient_id: UUID,
        start_time: datetime,
        end_time: datetime,
        admin_id: Optional[UUID] = None,
        notes: Optional[str] = None,
        consultation_type: ConsultationType = ConsultationType.PHYSICAL,
        consultation_fee: float = 0.0,
        discount_code_id: Optional[UUID] = None,
        discount_code_used: Optional[str] = None,
        discount_amount: float = 0.0,
        final_amount: float = 0.0,
    ) -> Appointment:
        appt = Appointment(
            patient_id=patient_id,
            admin_id=admin_id,
            start_time=start_time,
            end_time=end_time,
            notes=notes,
            # New bookings await admin approval.
            status=AppointmentStatus.PENDING,
            consultation_type=consultation_type,
            consultation_fee=consultation_fee,
            discount_code_id=discount_code_id,
            discount_code_used=discount_code_used,
            discount_amount=discount_amount,
            final_amount=final_amount,
        )
        self.db.add(appt)
        self.db.commit()
        self.db.refresh(appt)
        return appt

    def approve(
        self,
        appt: Appointment,
        *,
        meeting_provider: Optional[str] = None,
        meeting_link: Optional[str] = None,
    ) -> Appointment:
        appt.status = AppointmentStatus.APPROVED
        appt.meeting_provider = meeting_provider
        appt.meeting_link = meeting_link
        # Re-approval consumed: no longer a pending reschedule.
        appt.reschedule_pending = False
        self.db.commit()
        self.db.refresh(appt)
        return appt

    def reject(self, appt: Appointment, reason: Optional[str] = None) -> Appointment:
        appt.status = AppointmentStatus.REJECTED
        appt.cancellation_reason = reason
        # A rejected online consult has no valid meeting.
        appt.meeting_provider = None
        appt.meeting_link = None
        appt.reschedule_pending = False
        self.db.commit()
        self.db.refresh(appt)
        return appt

    def set_status(
        self,
        appt: Appointment,
        new_status: AppointmentStatus,
        cancellation_reason: Optional[str] = None,
    ) -> Appointment:
        appt.status = new_status
        if new_status == AppointmentStatus.CANCELLED:
            appt.cancellation_reason = cancellation_reason
        self.db.commit()
        self.db.refresh(appt)
        return appt

    def reschedule(
        self,
        appt: Appointment,
        new_start: datetime,
        new_end: datetime,
        notes: Optional[str],
        consultation_type: Optional[ConsultationType] = None,
    ) -> Appointment:
        appt.start_time = new_start
        appt.end_time = new_end
        # Only overwrite notes when the request actually sent them — a
        # date/time-only reschedule must not wipe the patient's booking notes.
        if notes is not None:
            appt.notes = notes
        if consultation_type is not None:
            appt.consultation_type = consultation_type
        # Any change to the appointment invalidates the prior approval: it goes
        # back to PENDING for admin re-review, and (if it was online) the
        # meeting link/metadata is cleared so the patient can't join a stale call.
        appt.status = AppointmentStatus.PENDING
        appt.meeting_provider = None
        appt.meeting_link = None
        # Mark that this PENDING is a patient-initiated reschedule awaiting
        # re-approval, so approve/reject send the reschedule-specific emails.
        appt.reschedule_pending = True
        self.db.commit()
        self.db.refresh(appt)
        return appt

    def restore_discount_count(self, discount_code_id: UUID) -> None:
        """Decrement used_count when an appointment with a discount is cancelled."""
        code = (
            self.db.query(DiscountCode)
            .filter(DiscountCode.id == discount_code_id)
            .first()
        )
        if code and code.used_count > 0:
            code.used_count -= 1
            self.db.commit()

    def increment_discount_count_safe(self, code: DiscountCode) -> bool:
        """
        Atomically increment used_count only if max_uses is not yet reached.
        Returns True on success, False if the code is now exhausted.
        """
        from sqlalchemy import update
        result = self.db.execute(
            update(DiscountCode)
            .where(
                DiscountCode.id == code.id,
                (DiscountCode.max_uses.is_(None))
                | (DiscountCode.used_count < DiscountCode.max_uses),
            )
            .values(used_count=DiscountCode.used_count + 1)
        )
        self.db.commit()
        return result.rowcount == 1
