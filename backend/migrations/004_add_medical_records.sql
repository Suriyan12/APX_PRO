-- Migration 004: Medical Records Module (Google Drive backed)
-- Files live in Google Drive; this table stores metadata only.

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[medical_records]') AND type = N'U')
BEGIN
    CREATE TABLE [dbo].[medical_records] (
        id                      UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID() PRIMARY KEY,
        patient_id              UNIQUEIDENTIFIER NOT NULL,
        google_drive_file_id    NVARCHAR(255)    NOT NULL,
        google_drive_folder_id  NVARCHAR(255)    NOT NULL,
        file_name               NVARCHAR(255)    NOT NULL,
        file_extension          NVARCHAR(10)     NOT NULL,
        mime_type               NVARCHAR(100)    NOT NULL,
        file_size               BIGINT           NOT NULL,
        category                NVARCHAR(50)     NULL,
        uploaded_at             DATETIMEOFFSET   NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        uploaded_by             UNIQUEIDENTIFIER NULL,
        status                  NVARCHAR(20)     NOT NULL DEFAULT 'active',

        CONSTRAINT FK_medical_records_patient
            FOREIGN KEY (patient_id) REFERENCES [dbo].[users](id) ON DELETE CASCADE,
        -- NO ACTION to avoid multiple cascade paths on users
        CONSTRAINT FK_medical_records_uploader
            FOREIGN KEY (uploaded_by) REFERENCES [dbo].[users](id)
    );

    CREATE INDEX IX_medical_records_patient ON [dbo].[medical_records](patient_id, status);
END
GO
