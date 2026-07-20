-- Migration 008: store an optional cancellation reason on appointments so it
-- can be recorded for audit and surfaced in the cancellation email. Nullable
-- and additive — existing rows are unaffected.

IF COL_LENGTH('dbo.appointments', 'cancellation_reason') IS NULL
    ALTER TABLE dbo.appointments ADD cancellation_reason NVARCHAR(500) NULL;
GO
