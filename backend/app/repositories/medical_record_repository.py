import uuid
from typing import List, Optional

from sqlalchemy.orm import Session

from app.models.models import MedicalRecord, MedicalRecordStatus


class MedicalRecordRepository:
    """All medical_records database access is isolated here."""

    def __init__(self, db: Session):
        self.db = db

    def create(
        self,
        patient_id: uuid.UUID,
        uploaded_by: uuid.UUID,
        google_drive_file_id: str,
        google_drive_folder_id: str,
        file_name: str,
        file_extension: str,
        mime_type: str,
        file_size: int,
        category: Optional[str] = None,
    ) -> MedicalRecord:
        record = MedicalRecord(
            patient_id=patient_id,
            uploaded_by=uploaded_by,
            google_drive_file_id=google_drive_file_id,
            google_drive_folder_id=google_drive_folder_id,
            file_name=file_name,
            file_extension=file_extension,
            mime_type=mime_type,
            file_size=file_size,
            category=category,
            status=MedicalRecordStatus.ACTIVE.value,
        )
        self.db.add(record)
        self.db.commit()
        self.db.refresh(record)
        return record

    def get_by_id(self, record_id: uuid.UUID) -> Optional[MedicalRecord]:
        return (
            self.db.query(MedicalRecord)
            .filter(
                MedicalRecord.id == record_id,
                MedicalRecord.status == MedicalRecordStatus.ACTIVE.value,
            )
            .first()
        )

    def list_for_patient(self, patient_id: uuid.UUID) -> List[MedicalRecord]:
        return (
            self.db.query(MedicalRecord)
            .filter(
                MedicalRecord.patient_id == patient_id,
                MedicalRecord.status == MedicalRecordStatus.ACTIVE.value,
            )
            .order_by(MedicalRecord.uploaded_at.desc())
            .all()
        )

    def latest_folder_id_for_patient(self, patient_id: uuid.UUID) -> Optional[str]:
        record = (
            self.db.query(MedicalRecord)
            .filter(MedicalRecord.patient_id == patient_id)
            .order_by(MedicalRecord.uploaded_at.desc())
            .first()
        )
        return record.google_drive_folder_id if record else None

    def soft_delete(self, record: MedicalRecord) -> None:
        record.status = MedicalRecordStatus.DELETED.value
        self.db.commit()
