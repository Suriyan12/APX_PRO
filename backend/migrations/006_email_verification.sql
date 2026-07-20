-- Migration 006: Email-OTP verification for new signups.
-- Adds is_verified + email OTP columns. Existing accounts are grandfathered
-- (marked verified) so no current user — including admin — is locked out.

IF COL_LENGTH('dbo.users', 'is_verified') IS NULL
    ALTER TABLE dbo.users ADD is_verified BIT NOT NULL CONSTRAINT DF_users_is_verified DEFAULT 0;
GO

IF COL_LENGTH('dbo.users', 'email_otp') IS NULL
    ALTER TABLE dbo.users ADD email_otp NVARCHAR(10) NULL;
GO

IF COL_LENGTH('dbo.users', 'email_otp_expires') IS NULL
    ALTER TABLE dbo.users ADD email_otp_expires DATETIMEOFFSET NULL;
GO

-- Grandfather every account that existed before this feature.
UPDATE dbo.users SET is_verified = 1 WHERE is_verified = 0;
GO
