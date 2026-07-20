import uuid
from typing import List, Optional
from uuid import UUID as PyUUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import boto3
from botocore.exceptions import ClientError

from app.core.database import get_db
from app.core.config import settings
from app.api.deps import get_current_user, get_current_admin_user
from app.models.models import User, PostureScan, ScanStatus, UserRole
from app.schemas.schemas import PostureConfirmRequest, PostureReviewRequest, PostureScanResponse

router = APIRouter()


@router.get("/my", response_model=List[PostureScanResponse])
def get_my_scans(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    List history of posture scans and their review status for current patient.
    """
    scans = db.query(PostureScan).filter(PostureScan.patient_id == current_user.id).all()
    return scans


@router.post("/upload-url")
def get_video_upload_url(
    file_name: str,
    file_type: str,
    current_user: User = Depends(get_current_user)
):
    """
    Generate pre-signed S3 URL for user video scans (mp4, mov).
    """
    s3_client = boto3.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION
    )
    
    unique_key = f"scans/{current_user.id}/{uuid.uuid4()}-{file_name}"
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": settings.AWS_S3_BUCKET,
                "Key": unique_key,
                "ContentType": file_type
            },
            ExpiresIn=3600
        )
    except ClientError:
        presigned_url = f"https://mock-s3-upload-path.local/{settings.AWS_S3_BUCKET}/{unique_key}"

    return {
        "upload_url": presigned_url,
        "file_path": unique_key
    }


@router.post("/confirm", response_model=PostureScanResponse, status_code=status.HTTP_201_CREATED)
def confirm_scan_upload(
    confirm_in: PostureConfirmRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Confirm scan video has finished uploading to S3, marked as pending review.
    """
    db_scan = PostureScan(
        patient_id=current_user.id,
        video_path=confirm_in.video_path,
        status=ScanStatus.PENDING_REVIEW
    )
    db.add(db_scan)
    db.commit()
    db.refresh(db_scan)
    return db_scan


@router.get("/pending", response_model=List[PostureScanResponse])
def get_pending_scans(
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    (Admin only) List all posture scans awaiting assessment feedback.
    """
    scans = db.query(PostureScan).filter(PostureScan.status == ScanStatus.PENDING_REVIEW).all()
    return scans


@router.get("/{id}/view-url")
def get_scan_view_url(
    id: PyUUID,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    """Admin only — generate a short-lived presigned GET URL for a posture scan video."""
    scan = db.query(PostureScan).filter(PostureScan.id == id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found.")

    s3_client = boto3.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION,
    )
    try:
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.AWS_S3_BUCKET, "Key": scan.video_path},
            ExpiresIn=3600,
        )
    except ClientError:
        raise HTTPException(status_code=503, detail="Could not generate video URL. Check AWS configuration.")

    return {"view_url": url, "expires_in": 3600}


@router.put("/{id}/review", response_model=PostureScanResponse)
def review_posture_scan(
    id: PyUUID,
    review_in: PostureReviewRequest,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    (Admin only) Review a posture video scan and write corrective feedback.
    """
    scan = db.query(PostureScan).filter(PostureScan.id == id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")
        
    scan.feedback = review_in.feedback
    scan.status = ScanStatus.REVIEWED
    scan.reviewed_by = current_admin.id
    db.commit()
    db.refresh(scan)
    return scan
