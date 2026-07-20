import uuid
from typing import List, Optional
from uuid import UUID as PyUUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import boto3
from botocore.exceptions import ClientError

from app.core.database import get_db
from app.core.config import settings
from app.api.deps import get_current_user
from app.models.models import User, MedicalReport, UserRole
from app.schemas.schemas import ReportUploadConfirmRequest, MedicalReportResponse

router = APIRouter()


@router.get("/", response_model=List[MedicalReportResponse])
def list_my_reports(
    patient_id: Optional[PyUUID] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all uploaded medical reports for patient. Admins can view any user's reports.
    """
    if current_user.role == UserRole.ADMIN:
        if not patient_id:
            raise HTTPException(status_code=400, detail="patient_id is required for admin views")
        target_id = patient_id
    else:
        target_id = current_user.id

    reports = db.query(MedicalReport).filter(MedicalReport.patient_id == target_id).all()
    return reports


@router.post("/upload-url")
def get_upload_url(
    file_name: str,
    file_type: str,
    current_user: User = Depends(get_current_user)
):
    """
    Generate pre-signed S3 upload URL for medical document.
    """
    s3_client = boto3.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION
    )
    
    unique_key = f"reports/{current_user.id}/{uuid.uuid4()}-{file_name}"
    
    try:
        # Generate presigned PUT URL
        presigned_url = s3_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": settings.AWS_S3_BUCKET,
                "Key": unique_key,
                "ContentType": file_type
            },
            ExpiresIn=3600 # Valid for 1 hour
        )
    except ClientError as e:
        # Fallback Mock URL if AWS setup fails / keys are default
        presigned_url = f"https://mock-s3-upload-path.local/{settings.AWS_S3_BUCKET}/{unique_key}"

    return {
        "upload_url": presigned_url,
        "file_path": unique_key
    }


@router.post("/confirm", response_model=MedicalReportResponse, status_code=status.HTTP_201_CREATED)
def confirm_upload(
    confirm_in: ReportUploadConfirmRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Confirm report has been uploaded to S3 successfully and log metadata.
    """
    db_report = MedicalReport(
        patient_id=current_user.id,
        title=confirm_in.title,
        file_path=confirm_in.file_path,
        file_type=confirm_in.file_type
    )
    db.add(db_report)
    db.commit()
    db.refresh(db_report)
    return db_report


@router.get("/{id}/view-url")
def get_report_view_url(
    id: PyUUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generate a short-lived presigned GET URL. Patients can only view their own reports; admins can view any."""
    report = db.query(MedicalReport).filter(MedicalReport.id == id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found.")
    if report.patient_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Not authorized.")

    s3_client = boto3.client(
        "s3",
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        region_name=settings.AWS_REGION,
    )
    try:
        url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.AWS_S3_BUCKET, "Key": report.file_path},
            ExpiresIn=3600,
        )
    except ClientError:
        raise HTTPException(status_code=503, detail="Could not generate view URL. Check AWS configuration.")

    return {"view_url": url, "file_type": report.file_type, "expires_in": 3600}


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_report(
    id: PyUUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    report = db.query(MedicalReport).filter(MedicalReport.id == id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
        
    if report.patient_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Not authorized")
        
    db.delete(report)
    db.commit()
    return
