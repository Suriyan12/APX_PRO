-- Migration 015: indexes for the appointments hot paths.
--
-- Availability + overlap checks filter on start_time (+ status), and the
-- patient "my appointments" view filters on patient_id. Without indexes these
-- are table scans that degrade as the appointments table grows.
--
-- Idempotent: safe to re-run.

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_appointments_start_time'
      AND object_id = OBJECT_ID('dbo.appointments')
)
BEGIN
    CREATE INDEX IX_appointments_start_time
        ON dbo.appointments (start_time) INCLUDE (end_time, status);
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_appointments_patient_id'
      AND object_id = OBJECT_ID('dbo.appointments')
)
BEGIN
    CREATE INDEX IX_appointments_patient_id
        ON dbo.appointments (patient_id);
END;
GO
