-- 018_help_center.sql
-- Help Center: admin-managed library of instructional YouTube videos.
-- One new table only (help_videos) — no existing table is altered, so this is
-- risk-free for every other workflow (appointments, rehab, notifications,
-- auth, payments, medical records, notes). Idempotent.
--
-- Fresh databases get this table from Base.metadata.create_all() in
-- app/init_db.py; this migration creates it on EXISTING databases.
--
-- Storage note: only the YouTube URL and its extracted video id are stored.
-- No video files, thumbnails, or blobs live in this table or anywhere on our
-- infrastructure — playback is via an embedded YouTube player.

SET XACT_ABORT ON;
GO

-- ── help_videos ──────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.help_videos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.help_videos (
        id                UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        title             NVARCHAR(200)    NOT NULL,
        description       NVARCHAR(MAX)    NULL,
        category          NVARCHAR(50)     NOT NULL,
        youtube_url       NVARCHAR(500)    NOT NULL,
        youtube_video_id  NVARCHAR(20)     NOT NULL,
        display_order     INT              NOT NULL CONSTRAINT DF_help_videos_display_order DEFAULT 0,
        is_active         BIT              NOT NULL CONSTRAINT DF_help_videos_is_active DEFAULT 1,
        is_featured       BIT              NOT NULL CONSTRAINT DF_help_videos_is_featured DEFAULT 0,
        created_at        DATETIME2        NULL,
        updated_at        DATETIME2        NULL
    );
END
GO

-- Serves the user-facing list: filter on is_active, order by (category, display_order).
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'ix_help_videos_active_order'
      AND object_id = OBJECT_ID('dbo.help_videos')
)
    CREATE INDEX ix_help_videos_active_order
        ON dbo.help_videos (is_active, category, display_order);
GO

-- Fast lookup of the featured video.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'ix_help_videos_featured'
      AND object_id = OBJECT_ID('dbo.help_videos')
)
    CREATE INDEX ix_help_videos_featured
        ON dbo.help_videos (is_featured);
GO

-- Enforce the single-featured invariant at the database level: a filtered
-- unique index allows at most one row where is_featured = 1. The service layer
-- also clears-then-sets, but this is the hard guarantee. (Filtered indexes are
-- MSSQL-only; the SQLite test DB relies on the service-layer invariant.)
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'ux_help_videos_single_featured'
      AND object_id = OBJECT_ID('dbo.help_videos')
)
    CREATE UNIQUE INDEX ux_help_videos_single_featured
        ON dbo.help_videos (is_featured)
        WHERE is_featured = 1;
GO
