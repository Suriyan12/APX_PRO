-- Migration 005: Move Study Materials (Notes) to Google Drive storage.
-- Files now live in Google Drive (StudyMaterials/<Category>/); this table
-- keeps metadata only. Adds Drive ids + mime_type + premium display fields,
-- and relaxes the legacy file_path to nullable.

IF COL_LENGTH('dbo.notes', 'google_drive_file_id') IS NULL
    ALTER TABLE dbo.notes ADD google_drive_file_id NVARCHAR(255) NULL;
GO

IF COL_LENGTH('dbo.notes', 'google_drive_folder_id') IS NULL
    ALTER TABLE dbo.notes ADD google_drive_folder_id NVARCHAR(255) NULL;
GO

IF COL_LENGTH('dbo.notes', 'mime_type') IS NULL
    ALTER TABLE dbo.notes ADD mime_type NVARCHAR(100) NULL;
GO

IF COL_LENGTH('dbo.notes', 'is_free') IS NULL
    ALTER TABLE dbo.notes ADD is_free BIT NOT NULL CONSTRAINT DF_notes_is_free DEFAULT 0;
GO

IF COL_LENGTH('dbo.notes', 'price') IS NULL
    ALTER TABLE dbo.notes ADD price DECIMAL(10, 2) NOT NULL CONSTRAINT DF_notes_price DEFAULT 0;
GO

-- Legacy S3/local key is no longer required.
ALTER TABLE dbo.notes ALTER COLUMN file_path NVARCHAR(512) NULL;
GO

-- Purge dead soft-deleted test rows whose files never lived on Drive.
DELETE FROM dbo.notes WHERE is_active = 0 AND google_drive_file_id IS NULL;
GO
