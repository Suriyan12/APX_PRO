-- Migration 011: physical vs online consultations.
--  * consultation_type: 'physical' | 'online' (default physical)
--  * meeting_provider  : opaque provider id (e.g. 'google_meet') — swappable
--  * meeting_link      : video-consult URL (only served to the assigned patient/admin)
--  * status check constraint extended with 'approved' and 'rejected'
-- MSSQL default collation is case-insensitive, so stored enum NAMEs
-- ('APPROVED') match the lowercase constraint values ('approved').

IF COL_LENGTH('dbo.appointments', 'consultation_type') IS NULL
    ALTER TABLE dbo.appointments
        ADD consultation_type VARCHAR(20) NOT NULL
        CONSTRAINT DF_appointments_consultation_type DEFAULT 'physical';
GO

IF COL_LENGTH('dbo.appointments', 'meeting_provider') IS NULL
    ALTER TABLE dbo.appointments ADD meeting_provider VARCHAR(30) NULL;
GO

IF COL_LENGTH('dbo.appointments', 'meeting_link') IS NULL
    ALTER TABLE dbo.appointments ADD meeting_link VARCHAR(1000) NULL;
GO

-- Extend the status CHECK constraint to allow 'approved' and 'rejected'.
DECLARE @status_ck sysname;
SELECT @status_ck = cc.name
FROM sys.check_constraints cc
JOIN sys.tables t ON cc.parent_object_id = t.object_id
WHERE t.name = 'appointments' AND cc.definition LIKE '%status%';
IF @status_ck IS NOT NULL
    EXEC('ALTER TABLE dbo.appointments DROP CONSTRAINT ' + @status_ck);
ALTER TABLE dbo.appointments ADD CONSTRAINT CK_appointments_status
    CHECK ([status] IN ('pending','approved','rejected','scheduled','completed','cancelled','rescheduled'));
GO

-- Constrain consultation_type.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_appointments_consultation_type')
    ALTER TABLE dbo.appointments ADD CONSTRAINT CK_appointments_consultation_type
        CHECK ([consultation_type] IN ('physical','online'));
GO
