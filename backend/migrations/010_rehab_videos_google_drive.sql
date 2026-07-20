-- Migration 010: uploaded rehab exercise videos move to Google Drive
-- (RehabilitationVideos/Program_<id>/), matching Medical Records and Study
-- Materials. Metadata columns added; legacy video_path stays for old rows but
-- is no longer written.

IF COL_LENGTH('dbo.rehab_exercises', 'video_drive_file_id') IS NULL
    ALTER TABLE dbo.rehab_exercises ADD video_drive_file_id NVARCHAR(255) NULL;
GO

IF COL_LENGTH('dbo.rehab_exercises', 'video_mime_type') IS NULL
    ALTER TABLE dbo.rehab_exercises ADD video_mime_type NVARCHAR(100) NULL;
GO

IF COL_LENGTH('dbo.rehab_exercises', 'video_file_size') IS NULL
    ALTER TABLE dbo.rehab_exercises ADD video_file_size BIGINT NULL;
GO

IF COL_LENGTH('dbo.rehab_exercises', 'video_uploaded_at') IS NULL
    ALTER TABLE dbo.rehab_exercises ADD video_uploaded_at DATETIMEOFFSET NULL;
GO
