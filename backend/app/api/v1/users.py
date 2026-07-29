from typing import List, Optional
from uuid import UUID as PyUUID
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_password_hash
from app.core.audit import audit_admin
from app.api.deps import get_current_admin_user
from app.models.models import User, UserRole
from app.schemas.schemas import UserResponse, UserAdminListResponse, AdminCreateUserRequest
from app.services.user_service import UserDeletionService, cleanup_drive_files

router = APIRouter()


@router.get("/", response_model=List[UserAdminListResponse])
def list_users(
    search: Optional[str] = Query(None, description="Search by name, email or phone"),
    role: Optional[UserRole] = Query(None),
    is_active: Optional[bool] = Query(None),
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Admin: paginated, filtered list of all users."""
    q = db.query(User)

    if search:
        term = f"%{search}%"
        q = q.filter(
            User.full_name.ilike(term)
            | User.email.ilike(term)
            | User.phone.ilike(term)
        )
    if role is not None:
        q = q.filter(User.role == role)
    if is_active is not None:
        q = q.filter(User.is_active == is_active)

    return q.order_by(User.created_at.desc()).offset(skip).limit(limit).all()


@router.get("/{id}", response_model=UserAdminListResponse)
def get_user(
    id: PyUUID,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Admin: fetch a single user's full profile."""
    user = db.query(User).filter(User.id == id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    return user


@router.post("/", response_model=UserAdminListResponse, status_code=status.HTTP_201_CREATED)
def create_user(
    user_in: AdminCreateUserRequest,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Admin: create a new user with any role."""
    if db.query(User).filter(User.email == user_in.email).first():
        raise HTTPException(status_code=400, detail="An account with this email already exists.")
    user = User(
        email=user_in.email,
        full_name=user_in.full_name,
        phone=user_in.phone or None,
        password_hash=get_password_hash(user_in.password),
        role=user_in.role,
        is_active=True,
        # Admin-provisioned accounts are trusted and skip self-verification;
        # without this they default to is_verified=False and login is blocked
        # forever (403 ACCOUNT_NOT_VERIFIED) with no OTP path to recover.
        is_verified=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    audit_admin("user.create", actor=current_admin, target_id=user.id,
                detail=f"role={user.role.value}")
    return user


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    id: PyUUID,
    bg: BackgroundTasks,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Admin: permanently delete a user and all their data.

    Deletes appointments, medical records/reports, posture scans, rehab
    programs/sessions, logs, purchases and tokens in one transaction; records
    the user authored for OTHERS are detached, not destroyed. Their medical-
    record files are removed from Google Drive in the background afterwards.
    """
    user = db.query(User).filter(User.id == id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if user.id == current_admin.id:
        raise HTTPException(status_code=400, detail="You cannot delete your own account.")

    drive_file_ids = UserDeletionService(db).delete_user_and_data(user, current_admin)
    audit_admin("user.delete", actor=current_admin, target_id=id,
                detail=f"drive_files={len(drive_file_ids)}")
    bg.add_task(cleanup_drive_files, drive_file_ids)


@router.patch("/{id}/status", response_model=UserAdminListResponse)
def toggle_user_status(
    id: PyUUID,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Admin: toggle a user's active/inactive status."""
    user = db.query(User).filter(User.id == id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if user.id == current_admin.id:
        raise HTTPException(status_code=400, detail="You cannot deactivate your own account.")

    user.is_active = not user.is_active
    db.commit()
    db.refresh(user)
    audit_admin("user.status_toggle", actor=current_admin, target_id=user.id,
                detail=f"is_active={user.is_active}")
    return user
