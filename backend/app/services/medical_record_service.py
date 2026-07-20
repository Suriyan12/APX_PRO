"""
MedicalRecordService — business logic for the Medical Records module.

Responsibilities:
  • Validate uploads (type / MIME / size)
  • Upload files to Google Drive (creating patient folders on demand)
  • Persist metadata via MedicalRecordRepository
  • Retrieve, download and delete records with strict per-patient authorization
"""
import logging
import re
import uuid
from typing import List, Optional, Tuple

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.models import MedicalRecord, User, UserRole
from app.repositories.medical_record_repository import MedicalRecordRepository
from app.services.google_drive_service import GoogleDriveService

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {"pdf", "jpg", "jpeg", "png"}
ALLOWED_MIME_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/jpg",
    "image/png",
}


class MedicalRecordValidationError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


class MedicalRecordAccessDenied(Exception):
    pass


class MedicalRecordNotFound(Exception):
    pass


def _sanitize_file_name(name: str) -> str:
    """Keep only safe characters; prevent path tricks in Drive file names."""
    base = name.strip().replace("\\", "/").split("/")[-1]
    base = re.sub(r"[^A-Za-z0-9._ \-()]", "_", base)
    return base[:200] or "document"


class MedicalRecordService:
    def __init__(self, db: Session):
        self.repo = MedicalRecordRepository(db)
        self.drive = GoogleDriveService()

    # ── Authorization ────────────────────────────────────────────────────────

    @staticmethod
    def _assert_can_access(record: MedicalRecord, user: User) -> None:
        if record.patient_id != user.id and user.role != UserRole.ADMIN:
            raise MedicalRecordAccessDenied()

    def _get_authorized(self, record_id: uuid.UUID, user: User) -> MedicalRecord:
        record = self.repo.get_by_id(record_id)
        if not record:
            raise MedicalRecordNotFound()
        self._assert_can_access(record, user)
        return record

    # ── Upload ───────────────────────────────────────────────────────────────

    def upload(
        self,
        current_user: User,
        file_name: str,
        content_type: Optional[str],
        data: bytes,
        category: Optional[str] = None,
        patient_id: Optional[uuid.UUID] = None,
    ) -> MedicalRecord:
        # Patients can only ever upload into their own folder; only admins may
        # target another patient via patient_id.
        if patient_id and patient_id != current_user.id:
            if current_user.role != UserRole.ADMIN:
                raise MedicalRecordAccessDenied()
            target_patient_id = patient_id
        else:
            target_patient_id = current_user.id

        safe_name = _sanitize_file_name(file_name)
        extension = safe_name.rsplit(".", 1)[-1].lower() if "." in safe_name else ""
        if extension not in ALLOWED_EXTENSIONS:
            raise MedicalRecordValidationError(
                "Unsupported file type. Allowed: PDF, JPG, JPEG, PNG."
            )

        mime_type = (content_type or "").lower().split(";")[0].strip()
        if mime_type not in ALLOWED_MIME_TYPES:
            raise MedicalRecordValidationError(
                "Unsupported content type. Allowed: PDF, JPG, JPEG, PNG."
            )

        max_bytes = settings.MEDICAL_RECORD_MAX_FILE_SIZE_MB * 1024 * 1024
        if len(data) == 0:
            raise MedicalRecordValidationError("Uploaded file is empty.")
        if len(data) > max_bytes:
            raise MedicalRecordValidationError(
                f"File exceeds the {settings.MEDICAL_RECORD_MAX_FILE_SIZE_MB} MB limit.",
                status_code=413,
            )

        # Prefer the folder id already recorded for this patient (avoids a Drive
        # round-trip). upload_to_patient self-heals if that id is stale — e.g.
        # after a Google account change — by rediscovering/recreating the folder
        # and returning the id actually used, which we then persist.
        preferred_folder_id = self.repo.latest_folder_id_for_patient(target_patient_id)
        # uuid prefix prevents collisions between same-named uploads
        drive_name = f"{uuid.uuid4().hex[:8]}_{safe_name}"
        drive_file_id, folder_id = self.drive.upload_to_patient(
            patient_key=str(target_patient_id),
            file_name=drive_name,
            mime_type=mime_type,
            data=data,
            preferred_folder_id=preferred_folder_id,
        )

        try:
            return self.repo.create(
                patient_id=target_patient_id,
                uploaded_by=current_user.id,
                google_drive_file_id=drive_file_id,
                google_drive_folder_id=folder_id,
                file_name=safe_name,
                file_extension=extension,
                mime_type=mime_type,
                file_size=len(data),
                category=category.strip()[:50] if category else None,
            )
        except Exception:
            # Compensating action — never leave an orphan file in Drive.
            logger.exception("Metadata insert failed; removing Drive file %s", drive_file_id)
            try:
                self.drive.delete_file(drive_file_id)
            except Exception:
                logger.exception("Compensating Drive delete failed for %s", drive_file_id)
            raise

    # ── Retrieval ────────────────────────────────────────────────────────────

    def list_for_patient(self, patient_id: uuid.UUID, current_user: User) -> List[MedicalRecord]:
        if patient_id != current_user.id and current_user.role != UserRole.ADMIN:
            raise MedicalRecordAccessDenied()
        return self.repo.list_for_patient(patient_id)

    def get_record(self, record_id: uuid.UUID, current_user: User) -> MedicalRecord:
        return self._get_authorized(record_id, current_user)

    def download(self, record_id: uuid.UUID, current_user: User) -> Tuple[MedicalRecord, bytes]:
        record = self._get_authorized(record_id, current_user)
        data = self.drive.download_file(record.google_drive_file_id)
        return record, data

    # ── Delete ───────────────────────────────────────────────────────────────

    def delete(self, record_id: uuid.UUID, current_user: User) -> None:
        record = self._get_authorized(record_id, current_user)
        self.drive.delete_file(record.google_drive_file_id)
        self.repo.soft_delete(record)
