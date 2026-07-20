from datetime import date
from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.models import User, ProgressLog
from app.schemas.schemas import ProgressLogCreate, ProgressLogResponse

router = APIRouter()


@router.get("/logs", response_model=List[ProgressLogResponse])
def get_progress_logs(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get user progress logs (weight, measurements) sorted chronologically for visual charts.
    """
    logs = db.query(ProgressLog).filter(
        ProgressLog.user_id == current_user.id
    ).order_by(ProgressLog.log_date.asc()).all()
    return logs


@router.post("/logs", response_model=ProgressLogResponse, status_code=status.HTTP_201_CREATED)
def log_progress(
    log_in: ProgressLogCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Log weight and body measurements. If a log exists for today, update it; otherwise create a new one.
    """
    log_date = log_in.log_date or date.today()
    
    # Check if entry already exists for this date
    db_log = db.query(ProgressLog).filter(
        ProgressLog.user_id == current_user.id,
        ProgressLog.log_date == log_date
    ).first()
    
    if db_log:
        # Update existing
        if log_in.weight is not None:
            db_log.weight = log_in.weight
        if log_in.chest is not None:
            db_log.chest = log_in.chest
        if log_in.waist is not None:
            db_log.waist = log_in.waist
        if log_in.hips is not None:
            db_log.hips = log_in.hips
        if log_in.systolic_bp is not None:
            db_log.systolic_bp = log_in.systolic_bp
        if log_in.diastolic_bp is not None:
            db_log.diastolic_bp = log_in.diastolic_bp
    else:
        # Create new
        db_log = ProgressLog(
            user_id=current_user.id,
            log_date=log_date,
            weight=log_in.weight,
            chest=log_in.chest,
            waist=log_in.waist,
            hips=log_in.hips,
            systolic_bp=log_in.systolic_bp,
            diastolic_bp=log_in.diastolic_bp
        )
        db.add(db_log)
        
    db.commit()
    db.refresh(db_log)
    return db_log
