"""
Admin user-deletion must remove the user and everything they own in one
transaction, while leaving other users' data intact. Uses a throwaway patient
so the shared seeded users are never touched.
"""
import uuid
from datetime import datetime, timedelta, timezone

from app.models.models import Appointment, ProgressLog, User, UserRole
from app.services.user_service import UserDeletionService
from tests.conftest import ADMIN_ID, PATIENT_A_ID


def test_delete_user_removes_their_data_only(db):
    victim_id = uuid.uuid4()
    victim = User(
        id=victim_id,
        email=f"victim_{victim_id.hex[:8]}@test.com",
        full_name="Victim",
        password_hash="x",
        role=UserRole.PATIENT,
        is_active=True,
    )
    db.add(victim)
    start = datetime.now(timezone.utc) + timedelta(days=3)
    db.add(Appointment(patient_id=victim_id, start_time=start, end_time=start + timedelta(minutes=30)))
    db.add(ProgressLog(user_id=victim_id, log_date=start.date(), weight=70))
    # A row belonging to another patient that must SURVIVE the deletion.
    db.add(ProgressLog(user_id=PATIENT_A_ID, log_date=start.date(), weight=80))
    db.commit()

    admin = db.get(User, ADMIN_ID)
    try:
        UserDeletionService(db).delete_user_and_data(victim, admin)

        assert db.get(User, victim_id) is None
        assert db.query(Appointment).filter(Appointment.patient_id == victim_id).count() == 0
        assert db.query(ProgressLog).filter(ProgressLog.user_id == victim_id).count() == 0
        # Other patient's data untouched.
        assert db.query(ProgressLog).filter(ProgressLog.user_id == PATIENT_A_ID).count() == 1
    finally:
        db.query(ProgressLog).filter(ProgressLog.user_id == PATIENT_A_ID).delete()
        if db.get(User, victim_id):
            db.query(Appointment).filter(Appointment.patient_id == victim_id).delete()
            db.query(ProgressLog).filter(ProgressLog.user_id == victim_id).delete()
            db.query(User).filter(User.id == victim_id).delete()
        db.commit()
