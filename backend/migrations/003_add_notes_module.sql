-- Migration 003: Premium Notes Module
-- Run this against the apx_pro SQL Server database

-- 1. Add has_notes_access column to users
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'users') AND name = 'has_notes_access'
)
BEGIN
    ALTER TABLE users ADD has_notes_access BIT NOT NULL DEFAULT 0;
    PRINT 'Added has_notes_access to users';
END

-- 2. Create notes table
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'notes') AND type = N'U')
BEGIN
    CREATE TABLE notes (
        id              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
        title           NVARCHAR(200)    NOT NULL,
        description     NVARCHAR(MAX)    NULL,
        category        NVARCHAR(100)    NOT NULL,
        tags            NVARCHAR(500)    NULL,
        file_name       NVARCHAR(255)    NOT NULL,
        file_path       NVARCHAR(512)    NOT NULL,
        file_type       NVARCHAR(10)     NOT NULL,
        file_size       INT              NOT NULL,
        uploaded_by     UNIQUEIDENTIFIER NULL REFERENCES users(id) ON DELETE SET NULL,
        uploaded_at     DATETIMEOFFSET   NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        updated_at      DATETIMEOFFSET   NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        is_active       BIT              NOT NULL DEFAULT 1
    );
    CREATE INDEX idx_notes_category ON notes(category);
    CREATE INDEX idx_notes_is_active ON notes(is_active);
    PRINT 'Created notes table';
END

-- 3. Create notes_purchases table
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'notes_purchases') AND type = N'U')
BEGIN
    CREATE TABLE notes_purchases (
        id                   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID() PRIMARY KEY,
        user_id              UNIQUEIDENTIFIER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        razorpay_order_id    NVARCHAR(100)    NULL,
        razorpay_payment_id  NVARCHAR(100)    NULL,
        amount               DECIMAL(10, 2)   NOT NULL,
        purchased_at         DATETIMEOFFSET   NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        is_active            BIT              NOT NULL DEFAULT 1
    );
    CREATE INDEX idx_notes_purchases_user_id ON notes_purchases(user_id);
    PRINT 'Created notes_purchases table';
END
