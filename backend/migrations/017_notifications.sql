-- 017_notifications.sql
-- Notification Center foundation: device_tokens (push registration) and
-- notifications (in-app messages). New tables only — no existing table is
-- altered, so this is risk-free for every other workflow. Idempotent.
--
-- Fresh databases get these tables from Base.metadata.create_all() in
-- app/init_db.py; this migration creates them on EXISTING databases.

SET XACT_ABORT ON;
GO

-- ── device_tokens ────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.device_tokens', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.device_tokens (
        id            UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        user_id       UNIQUEIDENTIFIER NOT NULL,
        token         NVARCHAR(512)    NOT NULL,
        platform      NVARCHAR(20)     NULL,
        is_active     BIT              NOT NULL CONSTRAINT DF_device_tokens_is_active DEFAULT 1,
        last_seen_at  DATETIME2        NULL,
        created_at    DATETIME2        NULL,
        updated_at    DATETIME2        NULL,
        CONSTRAINT FK_device_tokens_user FOREIGN KEY (user_id)
            REFERENCES dbo.users(id) ON DELETE CASCADE,
        CONSTRAINT UQ_device_tokens_token UNIQUE (token)
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'ix_device_tokens_user_id'
      AND object_id = OBJECT_ID('dbo.device_tokens')
)
    CREATE INDEX ix_device_tokens_user_id ON dbo.device_tokens (user_id);
GO

-- ── notifications ────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.notifications', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.notifications (
        id          UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        user_id     UNIQUEIDENTIFIER NOT NULL,
        title       NVARCHAR(200)    NOT NULL,
        body        NVARCHAR(MAX)    NOT NULL,
        type        NVARCHAR(50)     NULL,
        data        NVARCHAR(MAX)    NULL,
        is_read     BIT              NOT NULL CONSTRAINT DF_notifications_is_read DEFAULT 0,
        read_at     DATETIME2        NULL,
        created_at  DATETIME2        NULL,
        updated_at  DATETIME2        NULL,
        CONSTRAINT FK_notifications_user FOREIGN KEY (user_id)
            REFERENCES dbo.users(id) ON DELETE CASCADE
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'ix_notifications_user_read'
      AND object_id = OBJECT_ID('dbo.notifications')
)
    CREATE INDEX ix_notifications_user_read ON dbo.notifications (user_id, is_read);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'ix_notifications_user_created'
      AND object_id = OBJECT_ID('dbo.notifications')
)
    CREATE INDEX ix_notifications_user_created ON dbo.notifications (user_id, created_at);
GO
