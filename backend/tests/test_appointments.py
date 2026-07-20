"""
Appointment module — comprehensive test suite.

Tests cover:
  • Available slots endpoint
  • Booking: success, past rejection, end-before-start rejection
  • Slot conflict: same slot blocked for different users (core requirement)
  • Decimal serialization: GET /appointments/my must not return 500
  • GET /appointments/my: isolation, field presence
  • Cancellation: success, slot freed, double-cancel, unauthorised cancel
  • Reschedule: success, conflict detection (includes PENDING — bug fix)
"""

import pytest
from datetime import datetime, timezone, timedelta

from .conftest import (
    PATIENT_A_ID, PATIENT_B_ID, ADMIN_ID,
    future_slot, past_slot,
)

BASE = "/api/v1/appointments"


# ══════════════════════════════════════════════════════════════════════════════
# Available Slots
# ══════════════════════════════════════════════════════════════════════════════

class TestAvailableSlots:

    def test_returns_list_for_future_date(self, api):
        api.as_user(PATIENT_A_ID)
        date = (datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y-%m-%d")
        r = api.get(f"{BASE}/available-slots?date_str={date}")
        assert r.status_code == 200
        assert isinstance(r.json(), list)

    def test_invalid_date_format_returns_400(self, api):
        api.as_user(PATIENT_A_ID)
        r = api.get(f"{BASE}/available-slots?date_str=32-99-2099")
        assert r.status_code == 400

    def test_booked_slot_disappears_from_available(self, api):
        """After booking, that time slot must vanish from the available list."""
        start, end = future_slot(days=1, hour=5, minute=0)   # IST 10:30 AM
        api.as_user(PATIENT_A_ID)
        api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})

        date = (datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y-%m-%d")
        r = api.get(f"{BASE}/available-slots?date_str={date}")
        assert r.status_code == 200

        slot_starts = [s["start_time"] for s in r.json()]
        # None of the returned slots should match the booked start time
        assert not any(start[:16] in s for s in slot_starts), \
            "Booked slot still appears as available"


# ══════════════════════════════════════════════════════════════════════════════
# Book Appointment
# ══════════════════════════════════════════════════════════════════════════════

class TestBookAppointment:

    def test_book_future_slot_returns_201(self, api):
        start, end = future_slot(days=2, hour=5)
        api.as_user(PATIENT_A_ID)
        r = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})

        assert r.status_code == 201
        data = r.json()
        # Bookings now start as PENDING and await admin approval.
        assert data["status"] == "pending"

    def test_booking_response_has_all_required_fields(self, api):
        start, end = future_slot(days=3, hour=5)
        api.as_user(PATIENT_A_ID)
        r = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r.status_code == 201

        data = r.json()
        required = [
            "id", "patient_id", "status",
            "start_time", "end_time", "created_at",
            "consultation_fee", "discount_amount", "final_amount",
        ]
        for field in required:
            assert field in data, f"Missing field in booking response: '{field}'"

    def test_fee_is_zero_for_free_consultation(self, api):
        start, end = future_slot(days=4, hour=5)
        api.as_user(PATIENT_A_ID)
        r = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r.status_code == 201
        data = r.json()
        assert data["consultation_fee"] == 0.0
        assert data["final_amount"] == 0.0

    def test_booking_past_slot_returns_400(self, api):
        start, end = past_slot()
        api.as_user(PATIENT_A_ID)
        r = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r.status_code == 400
        assert "past" in r.json()["detail"].lower()

    def test_booking_end_before_start_returns_400(self, api):
        start, end = future_slot(days=5, hour=5)
        api.as_user(PATIENT_A_ID)
        # Swap start/end deliberately
        r = api.post(f"{BASE}/book", json={"start_time": end, "end_time": start})
        assert r.status_code == 400

    # ── Core slot-conflict requirement ────────────────────────────────────────

    def test_same_slot_blocked_for_different_user(self, api):
        """
        PRIMARY REQUIREMENT:
        If patient A books 10:00–10:30, patient B must NOT be able to book
        the same slot.  The response must be 409 Conflict.
        """
        start, end = future_slot(days=6, hour=5)

        api.as_user(PATIENT_A_ID)
        r1 = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r1.status_code == 201, "Patient A booking failed (test precondition)"

        api.as_user(PATIENT_B_ID)
        r2 = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r2.status_code == 409, \
            f"Expected 409 for slot taken by another user, got {r2.status_code}: {r2.text}"
        assert "taken" in r2.json()["detail"].lower()

    def test_overlapping_slot_also_blocked(self, api):
        """
        A slot that *partially overlaps* a booked one must also be rejected.
        Patient A: 10:00–10:30.  Patient B attempts 10:15–10:45 (overlaps 15 min).
        """
        start_a, end_a = future_slot(days=7, hour=5, minute=0)    # 10:30 IST
        # Build an overlapping slot 15 min into the same window
        s_b = (datetime.now(timezone.utc).replace(
            hour=5, minute=15, second=0, microsecond=0
        ) + timedelta(days=7)).isoformat()
        e_b = (datetime.now(timezone.utc).replace(
            hour=5, minute=45, second=0, microsecond=0
        ) + timedelta(days=7)).isoformat()

        api.as_user(PATIENT_A_ID)
        r1 = api.post(f"{BASE}/book", json={"start_time": start_a, "end_time": end_a})
        assert r1.status_code == 201

        api.as_user(PATIENT_B_ID)
        r2 = api.post(f"{BASE}/book", json={"start_time": s_b, "end_time": e_b})
        assert r2.status_code == 409

    def test_adjacent_non_overlapping_slots_both_succeed(self, api):
        """Two patients can book back-to-back slots (10:00–10:30 and 10:30–11:00)."""
        start_a, end_a = future_slot(days=8, hour=5, minute=0)
        start_b, end_b = future_slot(days=8, hour=5, minute=30)

        api.as_user(PATIENT_A_ID)
        r1 = api.post(f"{BASE}/book", json={"start_time": start_a, "end_time": end_a})
        assert r1.status_code == 201

        api.as_user(PATIENT_B_ID)
        r2 = api.post(f"{BASE}/book", json={"start_time": start_b, "end_time": end_b})
        assert r2.status_code == 201

    def test_same_user_cannot_double_book_same_slot(self, api):
        start, end = future_slot(days=9, hour=5)
        api.as_user(PATIENT_A_ID)
        r1 = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r1.status_code == 201

        r2 = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r2.status_code in (400, 409)

    def test_booking_includes_notes(self, api):
        start, end = future_slot(days=10, hour=5)
        api.as_user(PATIENT_A_ID)
        r = api.post(f"{BASE}/book", json={
            "start_time": start,
            "end_time": end,
            "notes": "Lower back pain",
        })
        assert r.status_code == 201
        assert r.json()["notes"] == "Lower back pain"


# ══════════════════════════════════════════════════════════════════════════════
# GET /appointments/my  (serialisation + isolation)
# ══════════════════════════════════════════════════════════════════════════════

class TestGetMyAppointments:

    def test_returns_empty_list_before_any_booking(self, api):
        api.as_user(PATIENT_A_ID)
        r = api.get(f"{BASE}/my")
        assert r.status_code == 200
        assert r.json() == []

    def test_returns_booked_appointment(self, api):
        start, end = future_slot(days=1, hour=6)
        api.as_user(PATIENT_A_ID)
        api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})

        r = api.get(f"{BASE}/my")
        assert r.status_code == 200
        assert len(r.json()) == 1

    def test_decimal_fields_are_floats_not_500(self, api):
        """
        CRITICAL: consultation_fee / discount_amount / final_amount are stored
        as Numeric(10,2) in the DB (Python Decimal).  Pydantic v2 must coerce
        them to float via the field_validator — if it doesn't, FastAPI returns 500.
        """
        start, end = future_slot(days=2, hour=6)
        api.as_user(PATIENT_A_ID)
        api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})

        r = api.get(f"{BASE}/my")
        assert r.status_code == 200, \
            f"GET /appointments/my returned {r.status_code} — likely Decimal serialisation error"

        appt = r.json()[0]
        for field in ("consultation_fee", "discount_amount", "final_amount"):
            val = appt[field]
            assert isinstance(val, (int, float)), \
                f"Field '{field}' is {type(val).__name__} instead of float: {val!r}"

    def test_patient_sees_only_own_appointments(self, api):
        """Appointments booked by Patient A must not appear for Patient B."""
        start, end = future_slot(days=3, hour=6)
        api.as_user(PATIENT_A_ID)
        api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})

        api.as_user(PATIENT_B_ID)
        r = api.get(f"{BASE}/my")
        assert r.status_code == 200
        assert r.json() == [], "Patient B should not see Patient A's appointments"

    def test_multiple_appointments_all_returned(self, api):
        api.as_user(PATIENT_A_ID)
        for day in [4, 5, 6]:
            start, end = future_slot(days=day, hour=6)
            api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})

        r = api.get(f"{BASE}/my")
        assert r.status_code == 200
        assert len(r.json()) == 3


# ══════════════════════════════════════════════════════════════════════════════
# Cancel Appointment
# ══════════════════════════════════════════════════════════════════════════════

class TestCancelAppointment:

    def _book(self, api, days, hour=7):
        start, end = future_slot(days=days, hour=hour)
        r = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r.status_code == 201
        return r.json()["id"], start, end

    def test_cancel_future_appointment_succeeds(self, api):
        api.as_user(PATIENT_A_ID)
        appt_id, *_ = self._book(api, days=1)

        r = api.put(f"{BASE}/{appt_id}/cancel")
        assert r.status_code == 200
        assert r.json()["status"] == "cancelled"

    def test_cancelled_slot_becomes_bookable_again(self, api):
        """After Patient A cancels, Patient B should be able to take that slot."""
        api.as_user(PATIENT_A_ID)
        appt_id, start, end = self._book(api, days=2)
        api.put(f"{BASE}/{appt_id}/cancel")

        api.as_user(PATIENT_B_ID)
        r = api.post(f"{BASE}/book", json={"start_time": start, "end_time": end})
        assert r.status_code == 201, \
            f"Slot should be free after cancellation; got {r.status_code}: {r.text}"

    def test_cancel_already_cancelled_returns_400(self, api):
        api.as_user(PATIENT_A_ID)
        appt_id, *_ = self._book(api, days=3)
        api.put(f"{BASE}/{appt_id}/cancel")

        r = api.put(f"{BASE}/{appt_id}/cancel")
        assert r.status_code == 400

    def test_other_patient_cannot_cancel(self, api):
        """Patient B must not be able to cancel Patient A's appointment."""
        api.as_user(PATIENT_A_ID)
        appt_id, *_ = self._book(api, days=4)

        api.as_user(PATIENT_B_ID)
        r = api.put(f"{BASE}/{appt_id}/cancel")
        assert r.status_code == 403

    def test_cancel_nonexistent_appointment_returns_404(self, api):
        import uuid
        api.as_user(PATIENT_A_ID)
        r = api.put(f"{BASE}/{uuid.uuid4()}/cancel")
        assert r.status_code == 404


# ══════════════════════════════════════════════════════════════════════════════
# Reschedule Appointment
# ══════════════════════════════════════════════════════════════════════════════

class TestRescheduleAppointment:

    def test_reschedule_to_free_slot_succeeds(self, api):
        start1, end1 = future_slot(days=1, hour=8)
        api.as_user(PATIENT_A_ID)
        r1 = api.post(f"{BASE}/book", json={"start_time": start1, "end_time": end1})
        appt_id = r1.json()["id"]

        start2, end2 = future_slot(days=10, hour=8)
        r2 = api.put(f"{BASE}/{appt_id}/reschedule",
                     json={"start_time": start2, "end_time": end2})
        assert r2.status_code == 200
        # Any reschedule invalidates the prior approval and returns to PENDING
        # for admin re-review.
        assert r2.json()["status"] == "pending"

    def test_reschedule_into_taken_slot_returns_409(self, api):
        """Patient B holds a slot; Patient A cannot reschedule into it."""
        shared_start, shared_end = future_slot(days=2, hour=8)

        # Patient B books the slot
        api.as_user(PATIENT_B_ID)
        r = api.post(f"{BASE}/book", json={
            "start_time": shared_start, "end_time": shared_end
        })
        assert r.status_code == 201

        # Patient A books a different slot
        api.as_user(PATIENT_A_ID)
        own_start, own_end = future_slot(days=3, hour=8)
        r2 = api.post(f"{BASE}/book", json={"start_time": own_start, "end_time": own_end})
        appt_a_id = r2.json()["id"]

        # Patient A tries to move into Patient B's slot
        r3 = api.put(f"{BASE}/{appt_a_id}/reschedule", json={
            "start_time": shared_start, "end_time": shared_end
        })
        assert r3.status_code == 409

    def test_reschedule_to_past_returns_400(self, api):
        start1, end1 = future_slot(days=4, hour=8)
        api.as_user(PATIENT_A_ID)
        r1 = api.post(f"{BASE}/book", json={"start_time": start1, "end_time": end1})
        appt_id = r1.json()["id"]

        p_start, p_end = past_slot()
        r2 = api.put(f"{BASE}/{appt_id}/reschedule",
                     json={"start_time": p_start, "end_time": p_end})
        assert r2.status_code == 400


# ══════════════════════════════════════════════════════════════════════════════
# Reschedule — Consultation Type preservation  (HIGH-SEV regression)
#
# Bug: rescheduling an ONLINE consultation silently forced it to PHYSICAL,
# because the reschedule endpoint bound to AppointmentCreate, whose
# consultation_type is non-optional with default PHYSICAL — so the omitted
# field always arrived as PHYSICAL and overwrote the stored type.
#
# Contract now: consultation_type is PRESERVED unless the patient explicitly
# sends a new one. Meeting link/provider are cleared on any reschedule (so a
# stale Join is impossible) and re-approval is required.
# ══════════════════════════════════════════════════════════════════════════════

class TestRescheduleConsultationType:

    def _book(self, api, *, days, hour, consultation_type=None):
        start, end = future_slot(days=days, hour=hour)
        api.as_user(PATIENT_A_ID)
        body = {"start_time": start, "end_time": end}
        if consultation_type is not None:
            body["consultation_type"] = consultation_type
        r = api.post(f"{BASE}/book", json=body)
        assert r.status_code == 201, r.text
        return r.json()

    def _reschedule(self, api, appt_id, *, days, hour, consultation_type=None):
        s2, e2 = future_slot(days=days, hour=hour)
        api.as_user(PATIENT_A_ID)
        body = {"start_time": s2, "end_time": e2}
        if consultation_type is not None:
            body["consultation_type"] = consultation_type
        r = api.put(f"{BASE}/{appt_id}/reschedule", json=body)
        assert r.status_code == 200, r.text
        return r.json()

    def _approve_online(self, api, appt_id):
        api.as_user(ADMIN_ID)
        r = api.put(f"{BASE}/{appt_id}/approve",
                    json={"meeting_provider": "google_meet", "meeting_link": "abc-defg-hij"})
        assert r.status_code == 200, r.text
        return r.json()

    def _get_my(self, api, user_id, appt_id):
        api.as_user(user_id)
        r = api.get(f"{BASE}/my")
        assert r.status_code == 200
        for a in r.json():
            if a["id"] == appt_id:
                return a
        raise AssertionError(f"appointment {appt_id} not visible in /my for {user_id}")

    # 1. Online → Reschedule (date/time only) → Online  (the reported bug)
    def test_online_reschedule_preserves_online(self, api):
        appt = self._book(api, days=1, hour=8, consultation_type="online")
        assert appt["consultation_type"] == "online"
        out = self._reschedule(api, appt["id"], days=11, hour=8)
        assert out["consultation_type"] == "online", "reschedule must NOT flip online→physical"
        assert out["status"] == "pending"

    # 2. Physical → Reschedule → Physical
    def test_physical_reschedule_preserves_physical(self, api):
        appt = self._book(api, days=2, hour=8)  # default = physical
        assert appt["consultation_type"] == "physical"
        out = self._reschedule(api, appt["id"], days=12, hour=8)
        assert out["consultation_type"] == "physical"
        assert out["status"] == "pending"

    # 3. Online → explicitly Change to Physical
    def test_reschedule_explicit_online_to_physical(self, api):
        appt = self._book(api, days=3, hour=8, consultation_type="online")
        out = self._reschedule(api, appt["id"], days=13, hour=8,
                               consultation_type="physical")
        assert out["consultation_type"] == "physical"
        assert out["meeting_link"] is None

    # 4. Physical → explicitly Change to Online
    def test_reschedule_explicit_physical_to_online(self, api):
        appt = self._book(api, days=4, hour=8)
        out = self._reschedule(api, appt["id"], days=14, hour=8,
                               consultation_type="online")
        assert out["consultation_type"] == "online"

    # Online reschedule clears the Meet link and forces re-approval (no stale Join)
    def test_online_reschedule_clears_link_and_requires_reapproval(self, api):
        appt = self._book(api, days=5, hour=8, consultation_type="online")
        approved = self._approve_online(api, appt["id"])
        assert approved["status"] == "approved"
        assert approved["meeting_link"], "approval should set a meeting link"
        out = self._reschedule(api, appt["id"], days=15, hour=8)
        assert out["consultation_type"] == "online"
        assert out["status"] == "pending"          # re-approval required
        assert out["meeting_link"] is None          # stale link cleared → Join hidden
        assert out["meeting_provider"] is None

    # Physical appointments never carry a meeting link, before or after reschedule
    def test_physical_never_has_meeting_link(self, api):
        appt = self._book(api, days=6, hour=8)
        mine = self._get_my(api, PATIENT_A_ID, appt["id"])
        assert mine["consultation_type"] == "physical"
        assert mine["meeting_link"] is None
        out = self._reschedule(api, appt["id"], days=16, hour=8)
        assert out["meeting_link"] is None

    # Admin sees the correct (preserved) type after a patient reschedule
    def test_admin_sees_preserved_type_after_reschedule(self, api):
        appt = self._book(api, days=7, hour=8, consultation_type="online")
        self._reschedule(api, appt["id"], days=17, hour=8)
        admin_view = self._get_my(api, ADMIN_ID, appt["id"])
        assert admin_view["consultation_type"] == "online"
        assert admin_view["status"] == "pending"


# ══════════════════════════════════════════════════════════════════════════════
# Email workflow — every email must match the ACTUAL business state
#
# Bug: a reschedule (which returns the appointment to PENDING) sent the patient a
# "successfully rescheduled" confirmation, no admin notification was sent, and the
# later approval was not distinguished as a reschedule approval. These tests pin
# the exact email (by subject + recipient) emitted for each state transition.
# ══════════════════════════════════════════════════════════════════════════════

MEET = {"meeting_provider": "google_meet", "meeting_link": "abc-defg-hij"}


class TestAppointmentEmails:

    @staticmethod
    def _subjects_to(emails, to):
        return [e["subject"] for e in emails if e["to"] == to]

    def _book(self, api, *, days, hour, online):
        start, end = future_slot(days=days, hour=hour)
        api.as_user(PATIENT_A_ID)
        body = {"start_time": start, "end_time": end,
                "consultation_type": "online" if online else "physical"}
        r = api.post(f"{BASE}/book", json=body)
        assert r.status_code == 201, r.text
        return r.json()["id"]

    # --- Booking ------------------------------------------------------------
    def test_booking_sends_request_received_not_confirmation(self, api, emails):
        self._book(api, days=1, hour=8, online=True)
        subs = self._subjects_to(emails, "patient_a@test.com")
        assert subs == ["Appointment Requested — APX PRO"]

    # --- Initial approval ---------------------------------------------------
    def test_initial_approval_online_email(self, api, emails):
        aid = self._book(api, days=2, hour=8, online=True)
        emails.clear()
        api.as_user(ADMIN_ID)
        r = api.put(f"{BASE}/{aid}/approve", json=MEET)
        assert r.status_code == 200, r.text
        assert self._subjects_to(emails, "patient_a@test.com") == ["Appointment Confirmed — APX PRO"]

    def test_initial_approval_physical_email_has_clinic_address(self, api, emails):
        aid = self._book(api, days=3, hour=8, online=False)
        emails.clear()
        api.as_user(ADMIN_ID)
        r = api.put(f"{BASE}/{aid}/approve")
        assert r.status_code == 200, r.text
        patient_emails = [e for e in emails if e["to"] == "patient_a@test.com"]
        assert [e["subject"] for e in patient_emails] == ["Appointment Confirmed — APX PRO"]
        # Physical confirmation includes the clinic address.
        assert "Location" in patient_emails[0]["html"] or "arrive" in patient_emails[0]["html"]

    # --- Reschedule request -------------------------------------------------
    def test_reschedule_request_patient_and_admin_emails(self, api, emails):
        aid = self._book(api, days=4, hour=8, online=True)
        api.as_user(ADMIN_ID)
        api.put(f"{BASE}/{aid}/approve", json=MEET)
        emails.clear()
        api.as_user(PATIENT_A_ID)
        s2, e2 = future_slot(days=14, hour=8)
        r = api.put(f"{BASE}/{aid}/reschedule", json={"start_time": s2, "end_time": e2})
        assert r.status_code == 200, r.text
        patient_subs = self._subjects_to(emails, "patient_a@test.com")
        admin_subs = self._subjects_to(emails, "admin@test.com")
        # Patient: awaiting-approval acknowledgement — NOT a success confirmation.
        assert patient_subs == ["Reschedule Requested — APX PRO"]
        assert "Appointment Rescheduled — APX PRO" not in patient_subs
        assert "Appointment Confirmed — APX PRO" not in patient_subs
        # Admin: notified that a request awaits review.
        assert "Reschedule Request — Action Needed — APX PRO" in admin_subs

    # --- Reschedule approval ------------------------------------------------
    def test_reschedule_approval_sends_reschedule_approved_email(self, api, emails):
        aid = self._book(api, days=5, hour=8, online=True)
        api.as_user(ADMIN_ID)
        api.put(f"{BASE}/{aid}/approve", json=MEET)
        api.as_user(PATIENT_A_ID)
        s2, e2 = future_slot(days=15, hour=8)
        api.put(f"{BASE}/{aid}/reschedule", json={"start_time": s2, "end_time": e2})
        emails.clear()
        api.as_user(ADMIN_ID)
        r = api.put(f"{BASE}/{aid}/approve",
                    json={"meeting_provider": "google_meet", "meeting_link": "xyz-mnop-qrs"})
        assert r.status_code == 200, r.text
        # THE reported bug: an approval email IS sent, and it's the reschedule variant.
        assert self._subjects_to(emails, "patient_a@test.com") == \
            ["Rescheduled Appointment Approved — APX PRO"]

    # --- Reschedule rejection ----------------------------------------------
    def test_reschedule_rejection_email(self, api, emails):
        aid = self._book(api, days=6, hour=8, online=True)
        api.as_user(ADMIN_ID)
        api.put(f"{BASE}/{aid}/approve", json=MEET)
        api.as_user(PATIENT_A_ID)
        s2, e2 = future_slot(days=16, hour=8)
        api.put(f"{BASE}/{aid}/reschedule", json={"start_time": s2, "end_time": e2})
        emails.clear()
        api.as_user(ADMIN_ID)
        r = api.put(f"{BASE}/{aid}/reject", json={"reason": "Slot no longer available"})
        assert r.status_code == 200, r.text
        subs = self._subjects_to(emails, "patient_a@test.com")
        assert subs == ["Reschedule Request Update — APX PRO"]

    # --- Initial rejection --------------------------------------------------
    def test_initial_rejection_email(self, api, emails):
        aid = self._book(api, days=7, hour=8, online=False)
        emails.clear()
        api.as_user(ADMIN_ID)
        r = api.put(f"{BASE}/{aid}/reject", json={"reason": "Fully booked"})
        assert r.status_code == 200, r.text
        assert self._subjects_to(emails, "patient_a@test.com") == ["Appointment Update — APX PRO"]

    # --- Cancellation -------------------------------------------------------
    def test_cancellation_email(self, api, emails):
        aid = self._book(api, days=8, hour=8, online=False)
        emails.clear()
        api.as_user(PATIENT_A_ID)
        r = api.put(f"{BASE}/{aid}/cancel", json={"reason": "Changed plans"})
        assert r.status_code == 200, r.text
        assert self._subjects_to(emails, "patient_a@test.com") == ["Appointment Cancelled — APX PRO"]


# ══════════════════════════════════════════════════════════════════════════════
# Email TIMES + "Previous" slot correctness
#
# Bug: DB datetime columns are timezone-naive (UTC wall-clock). Formatting them
# with .astimezone(IST) directly interpreted them as MACHINE-LOCAL time, so the
# approval email and the reschedule email's "Requested" row displayed the raw
# UTC clock time labelled IST (5h30m early) while "Previous" (which was
# UTC-tagged) displayed correctly — producing nonsensical old/new comparisons.
# ══════════════════════════════════════════════════════════════════════════════

class TestEmailTimesAndPreviousSlot:

    # UTC 09:00 → IST 14:30. The buggy path would print "09:00 AM" instead.
    H9_IST, H9_UTC_RAW = "02:30 PM", "09:00 AM"
    H10_IST = "03:30 PM"   # UTC 10:00
    H11_IST = "04:30 PM"   # UTC 11:00

    @staticmethod
    def _html_to(emails, to, subject):
        for e in emails:
            if e["to"] == to and e["subject"] == subject:
                return e["html"]
        raise AssertionError(f"no email to {to} with subject {subject!r}: "
                             f"{[(e['to'], e['subject']) for e in emails]}")

    def test_approval_email_shows_ist_time(self, api, emails):
        start, end = future_slot(days=9, hour=9)
        api.as_user(PATIENT_A_ID)
        aid = api.post(f"{BASE}/book", json={
            "start_time": start, "end_time": end, "consultation_type": "online",
        }).json()["id"]
        emails.clear()
        api.as_user(ADMIN_ID)
        api.put(f"{BASE}/{aid}/approve", json=MEET)
        html = self._html_to(emails, "patient_a@test.com", "Appointment Confirmed — APX PRO")
        assert self.H9_IST in html, "approval email must show the IST slot time"
        assert self.H9_UTC_RAW not in html, "approval email leaked the raw UTC clock time"

    def test_reschedule_email_previous_is_most_recent_approved_slot(self, api, emails):
        """book A → approve → reschedule to B → approve → reschedule to C:
        the second reschedule email must compare B (current approved) → C."""
        start_a, end_a = future_slot(days=10, hour=9)
        api.as_user(PATIENT_A_ID)
        aid = api.post(f"{BASE}/book", json={
            "start_time": start_a, "end_time": end_a, "consultation_type": "online",
        }).json()["id"]
        api.as_user(ADMIN_ID)
        api.put(f"{BASE}/{aid}/approve", json=MEET)

        # Reschedule #1: A → B, then approve B (B becomes the current approved slot)
        start_b, end_b = future_slot(days=11, hour=10)
        api.as_user(PATIENT_A_ID)
        assert api.put(f"{BASE}/{aid}/reschedule",
                       json={"start_time": start_b, "end_time": end_b}).status_code == 200
        api.as_user(ADMIN_ID)
        assert api.put(f"{BASE}/{aid}/approve", json=MEET).status_code == 200

        # Reschedule #2: B → C. Email must show Previous=B (NOT A) and Requested=C.
        emails.clear()
        start_c, end_c = future_slot(days=12, hour=11)
        api.as_user(PATIENT_A_ID)
        assert api.put(f"{BASE}/{aid}/reschedule",
                       json={"start_time": start_c, "end_time": end_c}).status_code == 200
        html = self._html_to(emails, "patient_a@test.com", "Reschedule Requested — APX PRO")
        assert self.H10_IST in html, "'Previous' must be the most recent approved slot (B)"
        assert self.H11_IST in html, "'Requested' must be the newly requested slot (C)"
        assert self.H9_IST not in html, "'Previous' wrongly shows the ORIGINAL slot (A)"

    def test_reschedule_preserves_notes_when_not_sent(self, api):
        start, end = future_slot(days=13, hour=9)
        api.as_user(PATIENT_A_ID)
        aid = api.post(f"{BASE}/book", json={
            "start_time": start, "end_time": end, "notes": "knee pain follow-up",
        }).json()["id"]
        s2, e2 = future_slot(days=23, hour=9)
        r = api.put(f"{BASE}/{aid}/reschedule", json={"start_time": s2, "end_time": e2})
        assert r.status_code == 200
        assert r.json()["notes"] == "knee pain follow-up", \
            "a date/time-only reschedule must not wipe the booking notes"


# ══════════════════════════════════════════════════════════════════════════════
# Slot reservation lifecycle
#
# Business rule: a slot is RESERVED from the moment a booking/reschedule request
# is submitted (PENDING) — other patients cannot take it. Approval confirms the
# hold; rejection/cancellation releases it.
# ══════════════════════════════════════════════════════════════════════════════

class TestSlotReservation:

    def _book(self, api, user, start, end, extra=None):
        api.as_user(user)
        body = {"start_time": start, "end_time": end}
        if extra:
            body.update(extra)
        return api.post(f"{BASE}/book", json=body)

    def test_pending_request_blocks_other_patients(self, api):
        start, end = future_slot(days=20, hour=6)
        assert self._book(api, PATIENT_A_ID, start, end).status_code == 201  # PENDING
        r = self._book(api, PATIENT_B_ID, start, end)
        assert r.status_code == 409, "a PENDING (unapproved) request must reserve the slot"

    def test_approval_keeps_slot_reserved(self, api):
        start, end = future_slot(days=21, hour=6)
        aid = self._book(api, PATIENT_A_ID, start, end).json()["id"]
        api.as_user(ADMIN_ID)
        assert api.put(f"{BASE}/{aid}/approve").status_code == 200
        assert self._book(api, PATIENT_B_ID, start, end).status_code == 409

    def test_rejection_releases_slot(self, api):
        start, end = future_slot(days=22, hour=6)
        aid = self._book(api, PATIENT_A_ID, start, end).json()["id"]
        api.as_user(ADMIN_ID)
        assert api.put(f"{BASE}/{aid}/reject", json={"reason": "unavailable"}).status_code == 200
        r = self._book(api, PATIENT_B_ID, start, end)
        assert r.status_code == 201, "a REJECTED request must release the slot"

    def test_cancellation_releases_slot(self, api):
        start, end = future_slot(days=24, hour=6)
        aid = self._book(api, PATIENT_A_ID, start, end).json()["id"]
        api.as_user(PATIENT_A_ID)
        assert api.put(f"{BASE}/{aid}/cancel").status_code == 200
        assert self._book(api, PATIENT_B_ID, start, end).status_code == 201

    def test_reschedule_request_reserves_new_slot_and_frees_old(self, api):
        old_s, old_e = future_slot(days=25, hour=6)
        new_s, new_e = future_slot(days=26, hour=6)
        aid = self._book(api, PATIENT_A_ID, old_s, old_e).json()["id"]
        api.as_user(ADMIN_ID)
        api.put(f"{BASE}/{aid}/approve")
        api.as_user(PATIENT_A_ID)
        assert api.put(f"{BASE}/{aid}/reschedule",
                       json={"start_time": new_s, "end_time": new_e}).status_code == 200
        # Requested slot is now reserved even though not yet approved …
        assert self._book(api, PATIENT_B_ID, new_s, new_e).status_code == 409
        # … and the old slot is released.
        assert self._book(api, PATIENT_B_ID, old_s, old_e).status_code == 201

    def test_rejected_reschedule_releases_requested_slot(self, api):
        old_s, old_e = future_slot(days=27, hour=6)
        new_s, new_e = future_slot(days=28, hour=6)
        aid = self._book(api, PATIENT_A_ID, old_s, old_e).json()["id"]
        api.as_user(ADMIN_ID)
        api.put(f"{BASE}/{aid}/approve")
        api.as_user(PATIENT_A_ID)
        api.put(f"{BASE}/{aid}/reschedule", json={"start_time": new_s, "end_time": new_e})
        api.as_user(ADMIN_ID)
        assert api.put(f"{BASE}/{aid}/reject", json={"reason": "slot conflict"}).status_code == 200
        assert self._book(api, PATIENT_B_ID, new_s, new_e).status_code == 201

    def test_ist_offset_booking_reserves_the_real_slot(self, api):
        """Flutter sends +05:30 slot strings. The same instant expressed in UTC
        must conflict — previously the offset was dropped and the two 'same'
        slots occupied different rows."""
        from zoneinfo import ZoneInfo
        ist = ZoneInfo("Asia/Kolkata")
        base = (datetime.now(ist) + timedelta(days=30)).replace(
            hour=14, minute=30, second=0, microsecond=0)          # 2:30 PM IST
        s_ist, e_ist = base.isoformat(), (base + timedelta(minutes=30)).isoformat()
        base_utc = base.astimezone(timezone.utc)                   # 09:00 UTC
        s_utc, e_utc = base_utc.isoformat(), (base_utc + timedelta(minutes=30)).isoformat()

        api.as_user(PATIENT_A_ID)
        assert api.post(f"{BASE}/book", json={"start_time": s_ist, "end_time": e_ist}).status_code == 201
        api.as_user(PATIENT_B_ID)
        r = api.post(f"{BASE}/book", json={"start_time": s_utc, "end_time": e_utc})
        assert r.status_code == 409, "the +05:30 and +00:00 forms of the SAME instant must conflict"

    def test_pending_slot_hidden_from_available_slots(self, api):
        from datetime import datetime, timezone, timedelta
        start, end = future_slot(days=29, hour=6)   # UTC 06:00 → IST 11:30 slot
        self._book(api, PATIENT_A_ID, start, end)
        date = (datetime.now(timezone.utc) + timedelta(days=29)).strftime("%Y-%m-%d")
        api.as_user(PATIENT_B_ID)
        r = api.get(f"{BASE}/available-slots?date_str={date}")
        assert r.status_code == 200
        assert not any(start[:16] in s["start_time"] for s in r.json()), \
            "a PENDING slot must not appear as available"


# ══════════════════════════════════════════════════════════════════════════════
# Timezone-offset bookings + email/appointment identity
#
# Bug: Flutter books with the IST slot strings ("…+05:30") returned by
# /available-slots. _utc() only TAGGED naive datetimes and returned aware ones
# unchanged; pyodbc then silently DROPPED the offset writing to the naive
# DATETIME2 column — storing the IST wall-clock as if UTC. Every app-made
# booking was shifted +5h30m in emails ("cancelled 9:00 AM appointment, email
# says 2:30 PM"), conflict checks, and the availability grid.
# ══════════════════════════════════════════════════════════════════════════════

class TestOffsetBookingAndEmailIdentity:

    @staticmethod
    def _ist_slot(days, hour_ist, minute=0):
        """ISO strings with +05:30 offset — exactly what the Flutter app sends."""
        from zoneinfo import ZoneInfo
        base = (datetime.now(ZoneInfo("Asia/Kolkata")) + timedelta(days=days)).replace(
            hour=hour_ist, minute=minute, second=0, microsecond=0)
        return base.isoformat(), (base + timedelta(minutes=30)).isoformat()

    @staticmethod
    def _mail(emails, to, subject):
        for e in emails:
            if e["to"] == to and e["subject"] == subject:
                return e["html"]
        raise AssertionError(f"missing {subject!r} to {to}: "
                             f"{[(e['to'], e['subject']) for e in emails]}")

    def test_ist_booking_stored_and_returned_as_utc(self, api):
        s, e = self._ist_slot(34, 14, 30)                     # 2:30 PM IST = 09:00 UTC
        api.as_user(PATIENT_A_ID)
        r = api.post(f"{BASE}/book", json={"start_time": s, "end_time": e})
        assert r.status_code == 201, r.text
        returned = datetime.fromisoformat(r.json()["start_time"])
        assert returned.tzinfo is not None, "API must return an explicit UTC offset"
        assert returned.astimezone(timezone.utc).strftime("%H:%M") == "09:00", \
            "stored instant must be the UTC equivalent of the IST slot"

    def test_cancellation_email_shows_the_booked_time(self, api, emails):
        """THE reported bug: cancel a 2:30 PM IST appointment — the email said
        8:00 PM (the +5:30-shifted phantom). It must say 02:30 PM."""
        s, e = self._ist_slot(35, 14, 30)
        api.as_user(PATIENT_A_ID)
        aid = api.post(f"{BASE}/book", json={"start_time": s, "end_time": e}).json()["id"]
        emails.clear()
        r = api.put(f"{BASE}/{aid}/cancel", json={"reason": "test"})
        assert r.status_code == 200
        html = self._mail(emails, "patient_a@test.com", "Appointment Cancelled — APX PRO")
        assert "02:30 PM" in html, "cancellation email must show the actual booked IST time"
        assert "08:00 PM" not in html, "cancellation email shows the +5:30-shifted phantom time"

    def test_every_email_references_its_triggering_appointment(self, api, emails):
        """Two appointments for the same patient — each workflow email must carry
        THAT appointment's ID and time, never the other one's."""
        s1, e1 = self._ist_slot(36, 10, 30)                   # A: 10:30 AM IST
        s2, e2 = self._ist_slot(37, 16, 0)                    # B: 04:00 PM IST
        api.as_user(PATIENT_A_ID)
        a1 = api.post(f"{BASE}/book", json={"start_time": s1, "end_time": e1,
                                            "consultation_type": "online"}).json()["id"]
        a2 = api.post(f"{BASE}/book", json={"start_time": s2, "end_time": e2}).json()["id"]

        # Approve A (online) → email must reference A only.
        emails.clear()
        api.as_user(ADMIN_ID)
        assert api.put(f"{BASE}/{a1}/approve", json=MEET).status_code == 200
        html = self._mail(emails, "patient_a@test.com", "Appointment Confirmed — APX PRO")
        assert a1 in html and a2 not in html
        assert "10:30 AM" in html and "04:00 PM" not in html

        # Approve B (physical) → email must reference B only.
        emails.clear()
        assert api.put(f"{BASE}/{a2}/approve").status_code == 200
        html = self._mail(emails, "patient_a@test.com", "Appointment Confirmed — APX PRO")
        assert a2 in html and a1 not in html
        assert "04:00 PM" in html and "10:30 AM" not in html

        # Reschedule A → request email must reference A's old + new times.
        emails.clear()
        s1b, e1b = self._ist_slot(38, 11, 30)                 # A': 11:30 AM IST
        api.as_user(PATIENT_A_ID)
        assert api.put(f"{BASE}/{a1}/reschedule",
                       json={"start_time": s1b, "end_time": e1b}).status_code == 200
        html = self._mail(emails, "patient_a@test.com", "Reschedule Requested — APX PRO")
        assert a1 in html and a2 not in html
        assert "10:30 AM" in html and "11:30 AM" in html and "04:00 PM" not in html

        # Re-approve A → reschedule-approval email shows A's NEW time.
        emails.clear()
        api.as_user(ADMIN_ID)
        assert api.put(f"{BASE}/{a1}/approve", json=MEET).status_code == 200
        html = self._mail(emails, "patient_a@test.com",
                          "Rescheduled Appointment Approved — APX PRO")
        assert a1 in html and "11:30 AM" in html and "04:00 PM" not in html

        # Cancel B → cancellation email references B only.
        emails.clear()
        api.as_user(PATIENT_A_ID)
        assert api.put(f"{BASE}/{a2}/cancel").status_code == 200
        html = self._mail(emails, "patient_a@test.com", "Appointment Cancelled — APX PRO")
        assert a2 in html and a1 not in html
        assert "04:00 PM" in html and "11:30 AM" not in html
