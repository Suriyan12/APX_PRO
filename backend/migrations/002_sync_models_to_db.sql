-- =============================================================================
-- Migration 002: Sync database to match current SQLAlchemy models
-- Safe to run multiple times -- every block checks before altering.
-- Does NOT drop or modify existing data.
-- Run against: apx_pro (SQL Server)
-- =============================================================================

-- =============================================================================
-- 1. password_reset_tokens  (entire table missing from original schema)
-- =============================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.tables WHERE name = 'password_reset_tokens'
)
BEGIN
    CREATE TABLE password_reset_tokens (
        id           UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        user_id      UNIQUEIDENTIFIER NOT NULL
                         REFERENCES users(id) ON DELETE CASCADE,
        token        VARCHAR(512)     UNIQUE NOT NULL,
        expires_at   DATETIME2        NOT NULL,
        used         BIT              NOT NULL DEFAULT 0,
        created_at   DATETIME2        NOT NULL DEFAULT GETUTCDATE()
    );
    CREATE INDEX idx_prt_token   ON password_reset_tokens(token);
    CREATE INDEX idx_prt_user_id ON password_reset_tokens(user_id);
    PRINT 'Created table: password_reset_tokens';
END
ELSE
    PRINT 'Skipped: password_reset_tokens already exists';
GO

-- =============================================================================
-- 2. discount_codes  (entire table missing from actual DB)
-- =============================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.tables WHERE name = 'discount_codes'
)
BEGIN
    CREATE TABLE discount_codes (
        id             UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
        code           VARCHAR(50)      UNIQUE NOT NULL,
        discount_type  VARCHAR(20)      NOT NULL
                           CHECK (discount_type IN ('percentage', 'flat')),
        discount_value DECIMAL(10, 2)   NOT NULL,
        max_uses       INT              NULL,
        used_count     INT              NOT NULL DEFAULT 0,
        valid_from     DATETIME2        NULL,
        valid_until    DATETIME2        NULL,
        is_active      BIT              NOT NULL DEFAULT 1,
        created_at     DATETIME2        NOT NULL DEFAULT GETUTCDATE()
    );
    CREATE INDEX idx_discount_codes_code ON discount_codes(code);
    PRINT 'Created table: discount_codes';

    -- Seed starter codes
    INSERT INTO discount_codes (id, code, discount_type, discount_value, max_uses, is_active)
    VALUES
        (NEWID(), 'APX10',   'percentage', 10.00, NULL, 1),
        (NEWID(), 'APX20',   'percentage', 20.00, NULL, 1),
        (NEWID(), 'FLAT100', 'flat',       100.00,  50, 1),
        (NEWID(), 'FLAT200', 'flat',       200.00,  20, 1);
    PRINT 'Seeded: 4 discount codes';
END
ELSE
    PRINT 'Skipped: discount_codes already exists';
GO

-- =============================================================================
-- 3. appointments — add 5 missing columns
--    discount_code_id FK added last so discount_codes exists first.
-- =============================================================================

-- 3a. consultation_fee
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('appointments') AND name = 'consultation_fee'
)
BEGIN
    ALTER TABLE appointments
        ADD consultation_fee DECIMAL(10, 2) NOT NULL DEFAULT 0.00;
    PRINT 'Added column: appointments.consultation_fee';
END
ELSE
    PRINT 'Skipped: appointments.consultation_fee already exists';
GO

-- 3b. discount_code_id  (FK to discount_codes)
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('appointments') AND name = 'discount_code_id'
)
BEGIN
    ALTER TABLE appointments
        ADD discount_code_id UNIQUEIDENTIFIER NULL;

    ALTER TABLE appointments
        ADD CONSTRAINT FK_appointments_discount_code
        FOREIGN KEY (discount_code_id)
        REFERENCES discount_codes(id)
        ON DELETE SET NULL;

    PRINT 'Added column + FK: appointments.discount_code_id';
END
ELSE
    PRINT 'Skipped: appointments.discount_code_id already exists';
GO

-- 3c. discount_code_used
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('appointments') AND name = 'discount_code_used'
)
BEGIN
    ALTER TABLE appointments
        ADD discount_code_used VARCHAR(50) NULL;
    PRINT 'Added column: appointments.discount_code_used';
END
ELSE
    PRINT 'Skipped: appointments.discount_code_used already exists';
GO

-- 3d. discount_amount
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('appointments') AND name = 'discount_amount'
)
BEGIN
    ALTER TABLE appointments
        ADD discount_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00;
    PRINT 'Added column: appointments.discount_amount';
END
ELSE
    PRINT 'Skipped: appointments.discount_amount already exists';
GO

-- 3e. final_amount
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('appointments') AND name = 'final_amount'
)
BEGIN
    ALTER TABLE appointments
        ADD final_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00;
    PRINT 'Added column: appointments.final_amount';
END
ELSE
    PRINT 'Skipped: appointments.final_amount already exists';
GO

-- =============================================================================
-- 4. Verification — print final column list for affected tables
-- =============================================================================
PRINT '--- appointments columns ---';
SELECT name, TYPE_NAME(user_type_id) AS type, is_nullable, object_definition(default_object_id) AS [default]
FROM sys.columns
WHERE object_id = OBJECT_ID('appointments')
ORDER BY column_id;

PRINT '--- password_reset_tokens columns ---';
SELECT name, TYPE_NAME(user_type_id) AS type, is_nullable
FROM sys.columns
WHERE object_id = OBJECT_ID('password_reset_tokens')
ORDER BY column_id;

PRINT '--- discount_codes columns ---';
SELECT name, TYPE_NAME(user_type_id) AS type, is_nullable
FROM sys.columns
WHERE object_id = OBJECT_ID('discount_codes')
ORDER BY column_id;
GO
