-- 016_rehab_session_status.sql
-- Adds explicit lifecycle + audit columns to rehab_workout_sessions so the
-- admin rehabilitation dashboard can report per-session status, per-day
-- compliance, and creation/update times. Idempotent (safe to run repeatedly).
--
-- Fresh databases get these columns from Base.metadata.create_all() in
-- app/init_db.py; this migration brings EXISTING databases up to the same shape
-- and backfills sensible values from the columns already present.

SET XACT_ABORT ON;
GO

-- session_date: the calendar day the session belongs to (UTC).
IF COL_LENGTH('dbo.rehab_workout_sessions', 'session_date') IS NULL
    ALTER TABLE dbo.rehab_workout_sessions ADD session_date DATE NULL;
GO

-- status: 'in_progress' | 'completed'. Added nullable, backfilled, then made NOT NULL.
IF COL_LENGTH('dbo.rehab_workout_sessions', 'status') IS NULL
    ALTER TABLE dbo.rehab_workout_sessions ADD status VARCHAR(20) NULL;
GO

-- created_at / updated_at: audit timestamps.
IF COL_LENGTH('dbo.rehab_workout_sessions', 'created_at') IS NULL
    ALTER TABLE dbo.rehab_workout_sessions ADD created_at DATETIME2 NULL;
GO

IF COL_LENGTH('dbo.rehab_workout_sessions', 'updated_at') IS NULL
    ALTER TABLE dbo.rehab_workout_sessions ADD updated_at DATETIME2 NULL;
GO

-- Backfill existing rows from the data already on the row.
UPDATE dbo.rehab_workout_sessions
SET session_date = CAST(started_at AS DATE)
WHERE session_date IS NULL;
GO

UPDATE dbo.rehab_workout_sessions
SET status = CASE WHEN is_completed = 1 THEN 'completed' ELSE 'in_progress' END
WHERE status IS NULL;
GO

UPDATE dbo.rehab_workout_sessions
SET created_at = started_at
WHERE created_at IS NULL;
GO

UPDATE dbo.rehab_workout_sessions
SET updated_at = COALESCE(completed_at, started_at)
WHERE updated_at IS NULL;
GO

-- Enforce NOT NULL + default on status now that every row has a value.
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.rehab_workout_sessions')
      AND name = 'status' AND is_nullable = 1
)
    ALTER TABLE dbo.rehab_workout_sessions ALTER COLUMN status VARCHAR(20) NOT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.default_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.rehab_workout_sessions')
      AND name = 'DF_rehab_workout_sessions_status'
)
    ALTER TABLE dbo.rehab_workout_sessions
        ADD CONSTRAINT DF_rehab_workout_sessions_status DEFAULT 'in_progress' FOR status;
GO

-- Index the per-day lookup used by "today's status" and compliance queries.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_rehab_workout_sessions_patient_program_date'
      AND object_id = OBJECT_ID('dbo.rehab_workout_sessions')
)
    CREATE INDEX IX_rehab_workout_sessions_patient_program_date
        ON dbo.rehab_workout_sessions (patient_id, program_id, session_date);
GO
