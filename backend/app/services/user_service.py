"""
User deletion business logic.

The MSSQL schema does NOT cascade user deletes (most FKs are NO_ACTION), so an
admin delete must remove the user's data explicitly, child tables first. All
deletes run in one transaction — either the user and all their data go, or
nothing does.

Records authored BY the user for other people (reviews, uploads, created
programs) are not destroyed — they are detached (NULLed) or reassigned, so
deleting an admin never wipes out patients' data.

Google Drive files owned by deleted medical records are returned to the caller
for best-effort background cleanup (Drive failures must never block or undo
the DB deletion).
"""
import logging
from typing import List

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.models import (
    Appointment,
    MedicalRecord,
    MedicalReport,
    NotesPurchase,
    PasswordResetToken,
    PostureScan,
    ProgressLog,
    RefreshToken,
    RehabExercise,
    RehabExerciseCompletion,
    RehabProgram,
    RehabWorkoutSession,
    User,
    UserAssignedProgram,
    WorkoutLog,
)

logger = logging.getLogger(__name__)


class UserDeletionService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def delete_user_and_data(self, user: User, acting_admin: User) -> List[str]:
        """Delete `user` and every row they own. Returns the Google Drive file
        ids of their medical records so the route can clean Drive up in the
        background after the transaction commits."""
        db = self.db
        uid = user.id
        # Capture identifying info NOW — after the delete commits, this ORM
        # instance maps to a nonexistent row and attribute access would raise.
        user_email = user.email
        admin_email = acting_admin.email

        # Collect Drive file ids BEFORE deleting the rows.
        drive_file_ids = [
            fid
            for (fid,) in db.query(MedicalRecord.google_drive_file_id)
            .filter(MedicalRecord.patient_id == uid)
            .all()
            if fid
        ]
        # Uploaded rehab videos (Drive-hosted) belonging to this patient's programs.
        rehab_video_candidates = [
            fid
            for (fid,) in db.query(RehabExercise.video_drive_file_id)
            .filter(
                RehabExercise.program_id.in_(
                    db.query(RehabProgram.id).filter(RehabProgram.patient_id == uid).scalar_subquery()
                ),
                RehabExercise.video_drive_file_id.isnot(None),
            )
            .all()
        ]

        # --- 1. Detach records the user AUTHORED for others (never delete) ---
        db.query(Appointment).filter(Appointment.admin_id == uid).update(
            {Appointment.admin_id: None}, synchronize_session=False
        )
        db.query(PostureScan).filter(PostureScan.reviewed_by == uid).update(
            {PostureScan.reviewed_by: None}, synchronize_session=False
        )
        db.query(MedicalRecord).filter(MedicalRecord.uploaded_by == uid).update(
            {MedicalRecord.uploaded_by: None}, synchronize_session=False
        )
        # rehab_programs.created_by is NOT NULL — reassign other patients'
        # programs to the acting admin so they keep working.
        db.query(RehabProgram).filter(
            RehabProgram.created_by == uid, RehabProgram.patient_id != uid
        ).update({RehabProgram.created_by: acting_admin.id}, synchronize_session=False)
        # notes.uploaded_by has ON DELETE SET NULL in the DB — handled there.

        # --- 2. Rehab module (grandchildren → children → parents) ---
        session_ids = db.query(RehabWorkoutSession.id).filter(
            RehabWorkoutSession.patient_id == uid
        ).scalar_subquery()
        program_ids = db.query(RehabProgram.id).filter(
            RehabProgram.patient_id == uid
        ).scalar_subquery()
        exercise_ids = db.query(RehabExercise.id).filter(
            RehabExercise.program_id.in_(program_ids)
        ).scalar_subquery()

        db.query(RehabExerciseCompletion).filter(
            RehabExerciseCompletion.session_id.in_(session_ids)
            | RehabExerciseCompletion.exercise_id.in_(exercise_ids)
        ).delete(synchronize_session=False)
        db.query(RehabWorkoutSession).filter(
            RehabWorkoutSession.patient_id == uid
        ).delete(synchronize_session=False)
        db.query(RehabExercise).filter(
            RehabExercise.program_id.in_(program_ids)
        ).delete(synchronize_session=False)
        db.query(RehabProgram).filter(
            RehabProgram.patient_id == uid
        ).delete(synchronize_session=False)

        # --- 3. Everything the user owns directly ---
        db.query(Appointment).filter(Appointment.patient_id == uid).delete(
            synchronize_session=False
        )
        db.query(MedicalRecord).filter(MedicalRecord.patient_id == uid).delete(
            synchronize_session=False
        )
        db.query(MedicalReport).filter(MedicalReport.patient_id == uid).delete(
            synchronize_session=False
        )
        db.query(PostureScan).filter(PostureScan.patient_id == uid).delete(
            synchronize_session=False
        )
        db.query(ProgressLog).filter(ProgressLog.user_id == uid).delete(
            synchronize_session=False
        )
        db.query(WorkoutLog).filter(WorkoutLog.user_id == uid).delete(
            synchronize_session=False
        )
        db.query(UserAssignedProgram).filter(
            UserAssignedProgram.user_id == uid
        ).delete(synchronize_session=False)
        db.query(NotesPurchase).filter(NotesPurchase.user_id == uid).delete(
            synchronize_session=False
        )
        db.query(RefreshToken).filter(RefreshToken.user_id == uid).delete(
            synchronize_session=False
        )
        db.query(PasswordResetToken).filter(
            PasswordResetToken.user_id == uid
        ).delete(synchronize_session=False)
        # Orphan table from the removed subscriptions module — no ORM model.
        # Guard on existence: if the table was never created (e.g. this DB, or
        # after the module was dropped) skip it rather than aborting the whole
        # deletion transaction on a "no such table" error.
        from sqlalchemy import inspect as sa_inspect
        if "subscriptions" in sa_inspect(db.bind).get_table_names():
            db.execute(text("DELETE FROM subscriptions WHERE user_id = :uid"), {"uid": str(uid)})

        # --- 4. The user row itself ---
        # Use a bulk delete so the ORM doesn't walk relationships and try to
        # NULL non-nullable FKs (everything is already gone above).
        db.query(User).filter(User.id == uid).delete(synchronize_session=False)
        db.commit()

        # Rehab videos may be shared with other patients' programs (duplication)
        # — only clean up the ones nothing references anymore.
        if rehab_video_candidates:
            from app.services.rehab_service import orphan_video_ids
            drive_file_ids.extend(orphan_video_ids(db, rehab_video_candidates))

        logger.info(
            "User %s (%s) deleted by admin %s — %d Drive file(s) queued for cleanup",
            uid, user_email, admin_email, len(drive_file_ids),
        )
        return drive_file_ids


def cleanup_drive_files(file_ids: List[str]) -> None:
    """Best-effort Google Drive cleanup, run as a background task after the DB
    transaction commits. Failures are logged, never raised."""
    if not file_ids:
        return
    try:
        from app.services.google_drive_service import GoogleDriveService
        drive = GoogleDriveService()
        for fid in file_ids:
            try:
                drive.delete_file(fid)
            except Exception:
                logger.exception("Drive cleanup: could not delete file %s", fid)
        logger.info("Drive cleanup finished for %d file(s)", len(file_ids))
    except Exception:
        logger.exception("Drive cleanup unavailable — files left in Drive: %s", file_ids)
