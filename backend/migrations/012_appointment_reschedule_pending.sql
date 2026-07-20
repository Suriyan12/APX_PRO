-- 012_appointment_reschedule_pending.sql
-- Tracks whether an appointment is awaiting admin re-approval because the
-- PATIENT rescheduled it (as opposed to an initial pending booking). This lets
-- the approve/reject flows send the correct "Rescheduled Appointment Approved"
-- / "Reschedule Request Rejected" emails instead of the initial-booking ones.
-- Set TRUE on reschedule; cleared (FALSE) on approve or reject.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('appointments') AND name = 'reschedule_pending'
)
BEGIN
    ALTER TABLE appointments
        ADD reschedule_pending BIT NOT NULL CONSTRAINT DF_appointments_reschedule_pending DEFAULT 0;
END;
