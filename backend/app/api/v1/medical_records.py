"""
Medical Records API — Google Drive backed.

Flutter never talks to Google Drive; every byte flows through these
authenticated endpoints. Drive file ids and links are never exposed.
"""
import logging
from typing import List, Optional
from urllib.parse import quote
from uuid import UUID as PyUUID

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.ranges import parse_range
from app.models.models import User, UserRole
from app.schemas.schemas import MedicalRecordResponse
from app.services.google_drive_service import GoogleDriveError
from app.services.medical_record_service import (
    MedicalRecordAccessDenied,
    MedicalRecordNotFound,
    MedicalRecordService,
    MedicalRecordValidationError,
)

router = APIRouter()

# Dedicated PHI-access audit trail. Records only opaque ids + the action — never
# file names or content — so the log itself carries no medical PII. Route this
# logger to a durable/append-only sink in production for compliance.
audit_logger = logging.getLogger("apx.medical_records.audit")


def _audit(action: str, *, actor: User, record) -> None:
    audit_logger.info(
        "MEDREC_ACCESS action=%s actor=%s actor_role=%s record=%s owner=%s by_admin=%s",
        action, actor.id, getattr(actor.role, "value", actor.role),
        record.id, record.patient_id, actor.role == UserRole.ADMIN,
    )


def _translate(e: Exception) -> HTTPException:
    if isinstance(e, MedicalRecordValidationError):
        return HTTPException(status_code=e.status_code, detail=e.message)
    if isinstance(e, MedicalRecordAccessDenied):
        return HTTPException(status_code=403, detail="Not authorized to access this record.")
    if isinstance(e, MedicalRecordNotFound):
        return HTTPException(status_code=404, detail="Medical record not found.")
    if isinstance(e, GoogleDriveError):
        return HTTPException(status_code=e.status_code, detail=e.message)
    raise e


@router.post("/upload", response_model=MedicalRecordResponse, status_code=status.HTTP_201_CREATED)
async def upload_medical_record(
    file: UploadFile = File(...),
    category: Optional[str] = Form(None),
    patient_id: Optional[PyUUID] = Form(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Upload a medical record (PDF/JPG/JPEG/PNG). Patients upload for
    themselves; admins may upload on behalf of a patient via patient_id."""
    # Measure the disk-backed upload without reading it into memory, then stream
    # it to Drive (bounded server memory — no full-file buffering).
    file.file.seek(0, 2)  # SEEK_END
    file_size = file.file.tell()
    file.file.seek(0)
    service = MedicalRecordService(db)
    try:
        record = service.upload(
            current_user=current_user,
            file_name=file.filename or "document",
            content_type=file.content_type,
            fileobj=file.file,
            file_size=file_size,
            category=category,
            patient_id=patient_id,
        )
    except Exception as e:
        raise _translate(e)
    return record


@router.get("/patient/{patient_id}", response_model=List[MedicalRecordResponse])
def list_patient_records(
    patient_id: PyUUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List a patient's records. Patients can only list their own; admins any."""
    service = MedicalRecordService(db)
    try:
        return service.list_for_patient(patient_id, current_user)
    except Exception as e:
        raise _translate(e)


@router.get("/{record_id}", response_model=MedicalRecordResponse)
def get_medical_record(
    record_id: PyUUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = MedicalRecordService(db)
    try:
        return service.get_record(record_id, current_user)
    except Exception as e:
        raise _translate(e)


@router.get("/{record_id}/download")
def download_medical_record(
    record_id: PyUUID,
    request: Request,
    inline: bool = False,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Stream the file bytes through the API. inline=true renders in-place
    (preview); inline=false forces a download attachment. Supports HTTP Range
    for progressive PDF loading and streams the full file in chunks otherwise
    (bounded server memory — no full-file buffering)."""
    service = MedicalRecordService(db)
    try:
        record = service.get_record(record_id, current_user)
    except Exception as e:
        raise _translate(e)

    # PHI access — audit before streaming bytes.
    _audit("download_inline" if inline else "download_attachment",
           actor=current_user, record=record)

    disposition = "inline" if inline else "attachment"
    file_name = quote(record.file_name)
    base_headers = {
        "Content-Disposition": f"{disposition}; filename*=UTF-8''{file_name}",
        "Accept-Ranges": "bytes",
        "Cache-Control": "private, no-store",
    }

    range_header = request.headers.get("range")
    try:
        if range_header:
            total = record.file_size or service.drive.get_file_size(record.google_drive_file_id)
            rng = parse_range(range_header, total)
            if rng is None:
                return Response(
                    status_code=416,
                    headers={"Content-Range": f"bytes */{total}", "Accept-Ranges": "bytes"},
                )
            start, end = rng
            chunk = service.drive.download_range(record.google_drive_file_id, start, end)
            headers = dict(base_headers)
            headers["Content-Range"] = f"bytes {start}-{end}/{total}"
            headers["Content-Length"] = str(len(chunk))
            return Response(
                content=chunk, status_code=206, media_type=record.mime_type, headers=headers
            )

        total = record.file_size or service.drive.get_file_size(record.google_drive_file_id)
    except Exception as e:
        raise _translate(e)

    headers = dict(base_headers)
    if total:
        headers["Content-Length"] = str(total)
    return StreamingResponse(
        service.drive.stream_file(record.google_drive_file_id),
        media_type=record.mime_type,
        headers=headers,
    )


@router.delete("/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_medical_record(
    record_id: PyUUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    service = MedicalRecordService(db)
    try:
        record = service.get_record(record_id, current_user)
        _audit("delete", actor=current_user, record=record)
        service.delete(record_id, current_user)
    except Exception as e:
        raise _translate(e)
    return
