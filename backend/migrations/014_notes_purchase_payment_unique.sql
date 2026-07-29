-- Migration 014: prevent duplicate/replayed Notes payments at the DB level.
--
-- The verify endpoint already rejects a re-used razorpay_payment_id in code,
-- but a race between two concurrent verifies could still insert two rows before
-- either commits. A filtered UNIQUE index closes that window.
--
-- Filtered so it applies only to real payment ids: NULLs are ignored, and the
-- legacy bare 'DEV_MODE' literal (older dev-mode grants) is excluded so this
-- index can be created even if such rows exist. New dev grants use a per-user
-- 'DEV_<uuid>' sentinel, which is naturally unique.
--
-- Idempotent: safe to re-run.

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'UX_notes_purchases_payment_id'
      AND object_id = OBJECT_ID('dbo.notes_purchases')
)
BEGIN
    CREATE UNIQUE INDEX UX_notes_purchases_payment_id
        ON dbo.notes_purchases (razorpay_payment_id)
        WHERE razorpay_payment_id IS NOT NULL
          AND razorpay_payment_id <> 'DEV_MODE';
END;
GO
