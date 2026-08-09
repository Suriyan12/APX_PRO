"""
Help Center business logic.

Owns the rules for the admin-managed instructional video library: CRUD,
activate/deactivate, reorder, the single-featured invariant, YouTube URL
validation/id-extraction, and user-vs-admin visibility. Route handlers delegate
here and handle only HTTP concerns; notification dispatch is wired in the router
(mirroring the appointment module) so this service never touches Firebase.
"""
import logging
import uuid
from typing import Optional

from fastapi import HTTPException

from app.core.youtube import extract_youtube_id
from app.models.models import HelpVideo
from app.repositories.help_center_repository import HelpVideoRepository
from app.schemas.schemas import (
    HelpVideoCreate,
    HelpVideoUpdate,
    HelpVideoResponse,
)

logger = logging.getLogger(__name__)

# How many same-category videos to surface under "Related videos".
RELATED_LIMIT = 10


class HelpCenterService:
    def __init__(self, repo: HelpVideoRepository) -> None:
        self.repo = repo

    # ── Helpers ────────────────────────────────────────────────────────────────

    def _require(self, video_id: uuid.UUID) -> HelpVideo:
        video = self.repo.get_by_id(video_id)
        if not video:
            raise HTTPException(status_code=404, detail="Help video not found.")
        return video

    @staticmethod
    def _extract_id_or_400(url: str) -> str:
        video_id = extract_youtube_id(url)
        if video_id is None:
            # Schema validation already guards this on the API path; this is a
            # defensive backstop for any non-HTTP caller.
            raise HTTPException(
                status_code=422, detail="A valid YouTube URL is required."
            )
        return video_id

    # ── User (read-only, active videos) ─────────────────────────────────────────

    def list_active(
        self,
        *,
        category: Optional[str],
        search: Optional[str],
        limit: int,
        offset: int,
    ) -> dict:
        rows, total = self.repo.list(
            active_only=True,
            category=category,
            search=search,
            limit=limit,
            offset=offset,
        )
        return {
            "items": [HelpVideoResponse.from_model(v) for v in rows],
            "total": total,
            "limit": limit,
            "offset": offset,
        }

    def get_detail(self, video_id: uuid.UUID, *, is_admin: bool) -> dict:
        video = self._require(video_id)
        if not is_admin and not video.is_active:
            # Do not expose unpublished videos to regular users.
            raise HTTPException(status_code=404, detail="Help video not found.")
        related = self.repo.list_related(
            category=video.category, exclude_id=video.id, limit=RELATED_LIMIT
        )
        return {
            "video": HelpVideoResponse.from_model(video),
            "related": [HelpVideoResponse.from_model(v) for v in related],
        }

    # ── Admin (management) ───────────────────────────────────────────────────────

    def list_admin(
        self,
        *,
        category: Optional[str],
        search: Optional[str],
        limit: int,
        offset: int,
    ) -> dict:
        rows, total = self.repo.list(
            active_only=False,
            category=category,
            search=search,
            limit=limit,
            offset=offset,
        )
        return {
            "items": [HelpVideoResponse.from_model(v) for v in rows],
            "total": total,
            "limit": limit,
            "offset": offset,
        }

    def create_video(self, payload: HelpVideoCreate) -> HelpVideo:
        video_id = self._extract_id_or_400(payload.youtube_url)
        display_order = (
            payload.display_order
            if payload.display_order is not None
            else self.repo.next_display_order()
        )
        # A featured video must be active; ignore a nonsensical featured+inactive
        # combination rather than creating a featured video nobody can see.
        make_featured = payload.is_featured and payload.is_active
        if make_featured:
            # Clear any existing featured row; committed together with the create
            # below so at most one video is ever featured.
            self.repo.clear_featured()
        video = self.repo.create(
            title=payload.title.strip(),
            description=(payload.description or None),
            category=payload.category,
            youtube_url=payload.youtube_url.strip(),
            youtube_video_id=video_id,
            display_order=display_order,
            is_active=payload.is_active,
            is_featured=make_featured,
        )
        logger.info(
            "Help video created id=%s category=%s active=%s featured=%s",
            video.id, video.category, video.is_active, video.is_featured,
        )
        return video

    def update_video(self, video_id: uuid.UUID, payload: HelpVideoUpdate) -> HelpVideo:
        video = self._require(video_id)
        data = payload.model_dump(exclude_unset=True)

        if "youtube_url" in data and data["youtube_url"]:
            video.youtube_url = data["youtube_url"].strip()
            video.youtube_video_id = self._extract_id_or_400(video.youtube_url)
        if "title" in data and data["title"] is not None:
            video.title = data["title"].strip()
        if "description" in data:
            video.description = data["description"] or None
        if "category" in data and data["category"] is not None:
            video.category = data["category"]
        if "display_order" in data and data["display_order"] is not None:
            video.display_order = data["display_order"]
        if "is_active" in data and data["is_active"] is not None:
            video.is_active = data["is_active"]

        # Resolve the featured flag last so it can react to is_active changes.
        want_featured = data.get("is_featured")
        if want_featured is True:
            if not video.is_active:
                raise HTTPException(
                    status_code=422,
                    detail="A featured video must be active. Activate it first.",
                )
            self.repo.clear_featured(except_id=video.id)
            video.is_featured = True
        elif want_featured is False:
            video.is_featured = False
        elif video.is_featured and not video.is_active:
            # Deactivating the currently-featured video: it can no longer be the
            # featured tutorial (users only see active videos).
            video.is_featured = False

        self.repo.save(video)
        logger.info(
            "Help video updated id=%s active=%s featured=%s",
            video.id, video.is_active, video.is_featured,
        )
        return video

    def set_active(self, video_id: uuid.UUID, is_active: bool) -> HelpVideo:
        video = self._require(video_id)
        video.is_active = is_active
        if not is_active and video.is_featured:
            video.is_featured = False
        self.repo.save(video)
        logger.info("Help video id=%s active=%s", video.id, video.is_active)
        return video

    def delete_video(self, video_id: uuid.UUID) -> None:
        video = self._require(video_id)
        self.repo.delete(video)
        logger.info("Help video deleted id=%s", video_id)

    def reorder(self, items: list) -> int:
        """Apply a batch of {id, display_order} updates. Every id must exist."""
        order_by_id = {item.id: item.display_order for item in items}
        # Detect unknown ids before writing so the whole request fails cleanly.
        found = 0
        for vid in order_by_id:
            if self.repo.get_by_id(vid) is not None:
                found += 1
        if found != len(order_by_id):
            raise HTTPException(
                status_code=404, detail="One or more videos were not found."
            )
        updated = self.repo.apply_reorder(order_by_id)
        logger.info("Reordered %d help video(s)", updated)
        return updated
