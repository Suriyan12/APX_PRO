-- Migration 013: brute-force protection for password-reset OTPs.
--
-- Adds an attempts counter to password_reset_tokens so a wrong OTP can be
-- counted and the token locked after a small number of tries (mirrors the
-- email-verification OTP hardening in migration 009). Without this the 6-digit
-- reset OTP (1,000,000 combinations, 10-minute TTL) was brute-forceable into a
-- full account takeover.
--
-- Idempotent: safe to re-run.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.password_reset_tokens')
      AND name = 'attempts'
)
BEGIN
    ALTER TABLE dbo.password_reset_tokens
        ADD attempts INT NOT NULL CONSTRAINT DF_password_reset_tokens_attempts DEFAULT 0;
END;
GO
