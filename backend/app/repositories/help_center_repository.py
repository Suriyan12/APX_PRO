"""
Help Center data access layer.

All raw SQLAlchemy queries for help videos live here; the service layer calls
these methods and route handlers never touch the ORM directly. Each write
commits and refreshes, matching the other repositories in the project.
"""
import uuid
from typing import List, Optional, Tuple

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.models import HelpVideo


class HelpVideoRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    # ── Reads ──────────────────────────────────────────────────────────────────

    def get_by_id(self, video_id: uuid.UUID) -> Optional[HelpVideo]:
        return (
            self.db.query(HelpVideo)
            .filter(HelpVideo.id == video_id)
            .first()
        )

    def list(
        self,
        *,
        active_only: bool,
        category: Optional[str] = None,
        search: Optional[str] = None,
        limit: int,
        offset: int,
    ) -> Tuple[List[HelpVideo], int]:
        """One page of help videos ordered by (category, display_order, created_at),
        with the total for pagination.

        `active_only` scopes to published videos (the user-facing view); admins
        pass False to see everything. `search` matches title/description/category
        (case-insensitive substring)."""
        q = self.db.query(HelpVideo)
        if active_only:
            q = q.filter(HelpVideo.is_active == True)  # noqa: E712
        if category:
            q = q.filter(HelpVideo.category == category)
        if search:
            term = f"%{search.strip().lower()}%"
            q = q.filter(
                func.lower(HelpVideo.title).like(term)
                | func.lower(func.coalesce(HelpVideo.description, "")).like(term)
                | func.lower(HelpVideo.category).like(term)
            )
        total = q.count()
        rows = (
            q.order_by(
                HelpVideo.category.asc(),
                HelpVideo.display_order.asc(),
                HelpVideo.created_at.asc(),
            )
            .offset(offset)
            .limit(limit)
            .all()
        )
        return rows, total

    def list_related(
        self, *, category: str, exclude_id: uuid.UUID, limit: int
    ) -> List[HelpVideo]:
        """Active videos in the same category, excluding the given one."""
        return (
            self.db.query(HelpVideo)
            .filter(
                HelpVideo.is_active == True,  # noqa: E712
                HelpVideo.category == category,
                HelpVideo.id != exclude_id,
            )
            .order_by(HelpVideo.display_order.asc(), HelpVideo.created_at.asc())
            .limit(limit)
            .all()
        )

    def get_featured(self, *, active_only: bool = True) -> Optional[HelpVideo]:
        q = self.db.query(HelpVideo).filter(HelpVideo.is_featured == True)  # noqa: E712
        if active_only:
            q = q.filter(HelpVideo.is_active == True)  # noqa: E712
        return q.first()

    def next_display_order(self) -> int:
        """One past the current maximum display_order (0-based list → append)."""
        current_max = self.db.query(func.max(HelpVideo.display_order)).scalar()
        return 0 if current_max is None else int(current_max) + 1

    # ── Writes ─────────────────────────────────────────────────────────────────

    def create(
        self,
        *,
        title: str,
        description: Optional[str],
        category: str,
        youtube_url: str,
        youtube_video_id: str,
        display_order: int,
        is_active: bool,
        is_featured: bool,
    ) -> HelpVideo:
        row = HelpVideo(
            title=title,
            description=description,
            category=category,
            youtube_url=youtube_url,
            youtube_video_id=youtube_video_id,
            display_order=display_order,
            is_active=is_active,
            is_featured=is_featured,
        )
        self.db.add(row)
        self.db.commit()
        self.db.refresh(row)
        return row

    def save(self, video: HelpVideo) -> HelpVideo:
        """Persist in-place mutations made by the service."""
        self.db.commit()
        self.db.refresh(video)
        return video

    def delete(self, video: HelpVideo) -> None:
        self.db.delete(video)
        self.db.commit()

    def clear_featured(self, *, except_id: Optional[uuid.UUID] = None) -> None:
        """Unset is_featured on every featured row (optionally keeping one).

        Committed as part of the caller's set-featured operation so at most one
        video is ever featured. Does NOT commit on its own — the caller commits."""
        q = self.db.query(HelpVideo).filter(HelpVideo.is_featured == True)  # noqa: E712
        if except_id is not None:
            q = q.filter(HelpVideo.id != except_id)
        q.update({"is_featured": False}, synchronize_session=False)

    def apply_reorder(self, order_by_id: dict) -> int:
        """Set display_order for the given {video_id: display_order} mapping in a
        single transaction. Returns the number of rows updated."""
        updated = 0
        rows = (
            self.db.query(HelpVideo)
            .filter(HelpVideo.id.in_(list(order_by_id.keys())))
            .all()
        )
        for row in rows:
            row.display_order = order_by_id[row.id]
            updated += 1
        self.db.commit()
        return updated
