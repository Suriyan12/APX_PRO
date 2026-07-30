"""
Notification HTTP adapter.

Thin route handlers: parse params, inject dependencies (DB session, current
user), delegate to NotificationService, return the right status code. All
domain logic lives in the service.
"""
import logging
import uuid

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.models import User
from app.repositories.notification_repository import (
    DeviceTokenRepository,
    NotificationRepository,
)
from app.services.notification_service import NotificationService
from app.schemas.schemas import (
    DeviceTokenRegisterRequest,
    DeviceTokenResponse,
    DeviceTokenUnregisterRequest,
    MarkAllReadResponse,
    NotificationListResponse,
    NotificationResponse,
    UnreadCountResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter()


def _svc(db: Session) -> NotificationService:
    return NotificationService(NotificationRepository(db), DeviceTokenRepository(db))


# ── Device registration ───────────────────────────────────────────────────────

@router.post(
    "/devices",
    response_model=DeviceTokenResponse,
    status_code=status.HTTP_201_CREATED,
)
def register_device(
    body: DeviceTokenRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Register (or refresh) this device's push token for the current user."""
    return _svc(db).register_device(current_user, body.token, body.platform)


@router.post("/devices/unregister", status_code=status.HTTP_204_NO_CONTENT)
def unregister_device(
    body: DeviceTokenUnregisterRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Unregister this device's push token (e.g. on logout). Idempotent — a
    POST (not DELETE) so the long token travels in the body across every client
    and is not exposed in URLs/logs."""
    _svc(db).unregister_device(current_user, body.token)


# ── Notifications ──────────────────────────────────────────────────────────────

@router.get("", response_model=NotificationListResponse)
def list_notifications(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    unread_only: bool = Query(False),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The current user's notifications, newest first (paginated)."""
    return _svc(db).list_notifications(
        current_user, limit=limit, offset=offset, unread_only=unread_only
    )


@router.get("/unread-count", response_model=UnreadCountResponse)
def unread_count(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Count of the current user's unread notifications (for the badge)."""
    return {"count": _svc(db).unread_count(current_user)}


@router.put("/read-all", response_model=MarkAllReadResponse)
def mark_all_read(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Mark all of the current user's notifications as read."""
    return {"updated": _svc(db).mark_all_read(current_user)}


@router.put("/{notification_id}/read", response_model=NotificationResponse)
def mark_read(
    notification_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Mark a single notification as read (must belong to the current user)."""
    return _svc(db).mark_read(current_user, notification_id)
