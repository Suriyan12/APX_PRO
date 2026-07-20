-- Migration 009: authentication redesign.
--  * OTPs are stored HASHED (sha256 hex) — plain-text otp column is dropped.
--  * Retry cap + resend cooldown columns added.
--  * email_otp_expires renamed to otp_expires (channel-neutral).
-- Phone verification moves to Firebase Authentication — no server-side SMS OTP
-- state exists anymore, so nothing else is needed for the phone channel.

IF COL_LENGTH('dbo.users', 'otp_hash') IS NULL
    ALTER TABLE dbo.users ADD otp_hash NVARCHAR(64) NULL;
GO

IF COL_LENGTH('dbo.users', 'otp_attempts') IS NULL
    ALTER TABLE dbo.users ADD otp_attempts INT NOT NULL CONSTRAINT DF_users_otp_attempts DEFAULT 0;
GO

IF COL_LENGTH('dbo.users', 'otp_last_sent') IS NULL
    ALTER TABLE dbo.users ADD otp_last_sent DATETIMEOFFSET NULL;
GO

IF COL_LENGTH('dbo.users', 'otp_expires') IS NULL AND COL_LENGTH('dbo.users', 'email_otp_expires') IS NOT NULL
    EXEC sp_rename 'dbo.users.email_otp_expires', 'otp_expires', 'COLUMN';
GO

IF COL_LENGTH('dbo.users', 'otp_expires') IS NULL
    ALTER TABLE dbo.users ADD otp_expires DATETIMEOFFSET NULL;
GO

-- Plain-text OTP storage is removed. Any in-flight pending registrations will
-- simply request a fresh code (resend), which is stored hashed.
IF COL_LENGTH('dbo.users', 'email_otp') IS NOT NULL
    ALTER TABLE dbo.users DROP COLUMN email_otp;
GO
