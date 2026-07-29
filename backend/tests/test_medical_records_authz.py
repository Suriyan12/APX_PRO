"""
M8 / PHI security: medical records must be strictly per-patient. A patient may
only ever read their own records; another patient must be denied (no IDOR),
while an admin may read any. Exercises the service authorization layer directly
(no Google Drive needed — authz happens before any Drive call).
"""
import pytest

from app.models.models import MedicalRecord, User
from app.services.medical_record_service import (
    MedicalRecordAccessDenied,
    MedicalRecordService,
)
from tests.conftest import ADMIN_ID, PATIENT_A_ID, PATIENT_B_ID


@pytest.fixture
def record(db):
    rec = MedicalRecord(
        patient_id=PATIENT_A_ID,
        google_drive_file_id="fake-file-id",
        google_drive_folder_id="fake-folder-id",
        file_name="report.pdf",
        file_extension="pdf",
        mime_type="application/pdf",
        file_size=1234,
        uploaded_by=PATIENT_A_ID,
    )
    db.add(rec)
    db.commit()
    db.refresh(rec)
    yield rec
    db.query(MedicalRecord).filter(MedicalRecord.id == rec.id).delete()
    db.commit()


def test_owner_can_read_own_record(db, record):
    svc = MedicalRecordService(db)
    got = svc.get_record(record.id, db.get(User, PATIENT_A_ID))
    assert got.id == record.id


def test_other_patient_cannot_read_record(db, record):
    svc = MedicalRecordService(db)
    with pytest.raises(MedicalRecordAccessDenied):
        svc.get_record(record.id, db.get(User, PATIENT_B_ID))


def test_admin_can_read_any_record(db, record):
    svc = MedicalRecordService(db)
    got = svc.get_record(record.id, db.get(User, ADMIN_ID))
    assert got.id == record.id


def test_other_patient_cannot_list_records(db, record):
    svc = MedicalRecordService(db)
    with pytest.raises(MedicalRecordAccessDenied):
        svc.list_for_patient(PATIENT_A_ID, db.get(User, PATIENT_B_ID))
