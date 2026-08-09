"""
Help Center HTTP adapter.

Thin route handlers: parse params, inject dependencies (DB session, current
user), delegate to HelpCenterService, return the right status code. All domain
logic lives in the service.

Authorization:
  - Read endpoints (list active videos, video detail, categories) → any
    authenticated user (get_current_user). Users see only active videos.
  - Management endpoints (create/update/delete/activate/reorder, admin list) →
    admins only (get_current_admin_user).

Route ordering note: the static paths (/admin, /reorder, /categories) are
declared BEFORE the dynamic /{video_id} routes so FastAPI matches them first.

Notifications: publishing a new active video optionally notifies patients. The
producer is only invoked when settings.HELP_CENTER_NOTIFY_ON_PUBLISH is True
(off by default), so the deep-linked notification architecture is present but
dormant. A notification failure never affects the publish (producer swallows).
"""
import logging
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin_user, get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.models.models import HELP_VIDEO_CATEGORIES, HelpVideo, User, UserRole
from app.repositories.help_center_repository import HelpVideoRepository
from app.services import help_notifications as notify
from app.services.help_center_service import HelpCenterService
from app.schemas.schemas import (
    HelpCategoriesResponse,
    HelpVideoActiveRequest,
    HelpVideoCreate,
    HelpVideoDetailResponse,
    HelpVideoListResponse,
    HelpVideoReorderRequest,
    HelpVideoResponse,
    HelpVideoUpdate,
)

logger = logging.getLogger(__name__)

router = APIRouter()


def _svc(db: Session) -> HelpCenterService:
    return HelpCenterService(HelpVideoRepository(db))


def _maybe_notify_published(
    db: Session, background_tasks: BackgroundTasks, video: HelpVideo
) -> None:
    """Fire the optional 'new help video' notification, gated by the feature
    flag. Only for active videos (an inactive video is not visible)."""
    if settings.HELP_CENTER_NOTIFY_ON_PUBLISH and video.is_active:
        notify.notify_help_video_published(db, background_tasks, video=video)


# ── Static routes (declared before /{video_id}) ─────────────────────────────

@router.get("/categories", response_model=HelpCategoriesResponse)
def list_categories(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The supported Help Center categories (for filters and the admin form)."""
    return {"categories": list(HELP_VIDEO_CATEGORIES)}


@router.get("/admin", response_model=HelpVideoListResponse)
def list_videos_admin(
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    category: str | None = Query(None, max_length=50),
    search: str | None = Query(None, max_length=200),
    admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """All help videos (any status), for admin management."""
    return _svc(db).list_admin(
        category=category, search=search, limit=limit, offset=offset
    )


@router.put("/reorder", status_code=status.HTTP_200_OK)
def reorder_videos(
    body: HelpVideoReorderRequest,
    admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Apply a batch of display-order updates (drag-to-reorder)."""
    updated = _svc(db).reorder(body.items)
    return {"updated": updated}


# ── User read endpoints ──────────────────────────────────────────────────────

@router.get("", response_model=HelpVideoListResponse)
def list_videos(
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    category: str | None = Query(None, max_length=50),
    search: str | None = Query(None, max_length=200),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Active help videos, ordered by (category, display_order). Supports
    category filtering, free-text search, and pagination."""
    return _svc(db).list_active(
        category=category, search=search, limit=limit, offset=offset
    )


@router.get("/{video_id}", response_model=HelpVideoDetailResponse)
def get_video(
    video_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """A single help video plus related videos from the same category. Regular
    users can only open active videos; admins can open any."""
    is_admin = current_user.role == UserRole.ADMIN
    return _svc(db).get_detail(video_id, is_admin=is_admin)


# ── Admin management endpoints ───────────────────────────────────────────────

@router.post("", response_model=HelpVideoResponse, status_code=status.HTTP_201_CREATED)
def create_video(
    body: HelpVideoCreate,
    background_tasks: BackgroundTasks,
    admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Create a help video. Validates the YouTube URL and stores only the URL +
    extracted video id (never a file)."""
    video = _svc(db).create_video(body)
    _maybe_notify_published(db, background_tasks, video)
    return HelpVideoResponse.from_model(video)


@router.put("/{video_id}", response_model=HelpVideoResponse)
def update_video(
    video_id: uuid.UUID,
    body: HelpVideoUpdate,
    admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Edit a help video (partial update)."""
    video = _svc(db).update_video(video_id, body)
    return HelpVideoResponse.from_model(video)


@router.patch("/{video_id}/active", response_model=HelpVideoResponse)
def set_video_active(
    video_id: uuid.UUID,
    body: HelpVideoActiveRequest,
    background_tasks: BackgroundTasks,
    admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Activate or deactivate a help video."""
    video = _svc(db).set_active(video_id, body.is_active)
    if body.is_active:
        # Publishing a previously-hidden video: fire the optional notification.
        _maybe_notify_published(db, background_tasks, video)
    return HelpVideoResponse.from_model(video)


@router.delete("/{video_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_video(
    video_id: uuid.UUID,
    admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Permanently delete a help video."""
    _svc(db).delete_video(video_id)
