-- Migration 007: track which channel (email/phone) a pending OTP was sent to,
-- so resend/verify use the right channel. Existing (grandfathered) users leave
-- it NULL — they are already verified & active.

IF COL_LENGTH('dbo.users', 'otp_channel') IS NULL
    ALTER TABLE dbo.users ADD otp_channel NVARCHAR(10) NULL;
GO
