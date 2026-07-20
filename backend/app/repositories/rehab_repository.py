import logging
import uuid
from datetime import datetime, timezone, timedelta
from typing import List, Optional
from sqlalchemy.orm import Session

from app.models.models import (
    RehabProgram, RehabExercise, RehabWorkoutSession, RehabExerciseCompletion
)

logger = logging.getLogger(__name__)


class RehabRepository:
    def __init__(self, db: Session):
        self.db = db

    # ── Programs ──────────────────────────────────────────────────────────────

    def create_program(
        self,
        patient_id: uuid.UUID,
        created_by: uuid.UUID,
        title: str,
        description: Optional[str],
        estimated_duration_days: int,
    ) -> RehabProgram:
        program = RehabProgram(
            patient_id=patient_id,
            created_by=created_by,
            title=title,
            description=description,
            estimated_duration_days=estimated_duration_days,
            is_active=True,
        )
        self.db.add(program)
        self.db.commit()
        self.db.refresh(program)
        return program

    def get_programs_for_patient(self, patient_id: uuid.UUID) -> List[RehabProgram]:
        return (
            self.db.query(RehabProgram)
            .filter(RehabProgram.patient_id == patient_id)
            .order_by(RehabProgram.is_active.desc(), RehabProgram.created_at.desc())
            .all()
        )

    def get_by_id(self, program_id: uuid.UUID) -> Optional[RehabProgram]:
        return self.db.query(RehabProgram).filter(RehabProgram.id == program_id).first()

    def update_program(
        self,
        program: RehabProgram,
        title: Optional[str] = None,
        description: Optional[str] = None,
        estimated_duration_days: Optional[int] = None,
    ) -> RehabProgram:
        if title is not None:
            program.title = title
        if description is not None:
            program.description = description
        if estimated_duration_days is not None:
            program.estimated_duration_days = estimated_duration_days
        self.db.commit()
        self.db.refresh(program)
        return program

    def delete_program(self, program: RehabProgram) -> None:
        self.db.delete(program)
        self.db.commit()

    def deactivate_all_for_patient(self, patient_id: uuid.UUID) -> None:
        self.db.query(RehabProgram).filter(
            RehabProgram.patient_id == patient_id,
            RehabProgram.is_active == True,
        ).update({"is_active": False})
        self.db.commit()

    def set_active(self, program: RehabProgram, is_active: bool) -> RehabProgram:
        program.is_active = is_active
        self.db.commit()
        self.db.refresh(program)
        return program

    def get_active_for_patient(self, patient_id: uuid.UUID) -> Optional[RehabProgram]:
        return (
            self.db.query(RehabProgram)
            .filter(
                RehabProgram.patient_id == patient_id,
                RehabProgram.is_active == True,
            )
            .first()
        )

    # ── Exercises ─────────────────────────────────────────────────────────────

    def add_exercise(self, program_id: uuid.UUID, **kwargs) -> RehabExercise:
        max_idx = (
            self.db.query(RehabExercise)
            .filter(RehabExercise.program_id == program_id)
            .count()
        )
        exercise = RehabExercise(program_id=program_id, order_index=max_idx, **kwargs)
        self.db.add(exercise)
        self.db.commit()
        self.db.refresh(exercise)
        return exercise

    def get_exercise(self, exercise_id: uuid.UUID) -> Optional[RehabExercise]:
        return self.db.query(RehabExercise).filter(RehabExercise.id == exercise_id).first()

    # Keys that may legitimately be set to NULL (cleared) via an update.
    _NULLABLE_UPDATE_KEYS = (
        "video_url", "video_path", "notes", "description", "instructions",
        "target_area", "video_drive_file_id", "video_mime_type",
        "video_file_size", "video_uploaded_at",
    )

    def update_exercise(self, exercise: RehabExercise, updates: dict) -> RehabExercise:
        for key, value in updates.items():
            if value is not None or key in self._NULLABLE_UPDATE_KEYS:
                setattr(exercise, key, value)
        self.db.commit()
        self.db.refresh(exercise)
        return exercise

    def delete_exercise(self, exercise: RehabExercise) -> None:
        program_id = exercise.program_id
        # Remove completion history referencing this exercise first. Its FK
        # (rehab_exercise_completions.exercise_id) has no ON DELETE CASCADE, so
        # deleting an exercise a patient has completed would otherwise raise an
        # IntegrityError (500). The session-level counts are stored on the
        # session row, so dropping per-exercise completion rows is safe for
        # progress reporting.
        self.db.query(RehabExerciseCompletion).filter(
            RehabExerciseCompletion.exercise_id == exercise.id
        ).delete(synchronize_session=False)
        self.db.delete(exercise)
        self.db.commit()
        remaining = (
            self.db.query(RehabExercise)
            .filter(RehabExercise.program_id == program_id)
            .order_by(RehabExercise.order_index)
            .all()
        )
        for i, ex in enumerate(remaining):
            ex.order_index = i
        self.db.commit()

    def reorder_exercises(self, items: list) -> None:
        for item in items:
            self.db.query(RehabExercise).filter(
                RehabExercise.id == item["id"]
            ).update({"order_index": item["order_index"]})
        self.db.commit()

    def set_exercise_video_drive(
        self,
        exercise: RehabExercise,
        drive_file_id: str,
        mime_type: str,
        file_size: int,
    ) -> RehabExercise:
        """Record a Google Drive-hosted upload. Clears the YouTube URL and any
        legacy local path — local filesystem paths are never stored."""
        exercise.video_type = "upload"
        exercise.video_drive_file_id = drive_file_id
        exercise.video_mime_type = mime_type
        exercise.video_file_size = file_size
        exercise.video_uploaded_at = datetime.now(timezone.utc)
        exercise.video_url = None
        exercise.video_path = None
        self.db.commit()
        self.db.refresh(exercise)
        return exercise

    # ── Sessions ──────────────────────────────────────────────────────────────

    def get_today_session(self, patient_id: uuid.UUID) -> Optional[RehabWorkoutSession]:
        today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        return (
            self.db.query(RehabWorkoutSession)
            .filter(
                RehabWorkoutSession.patient_id == patient_id,
                RehabWorkoutSession.started_at >= today_start,
            )
            .order_by(RehabWorkoutSession.started_at.desc())
            .first()
        )

    def create_session(
        self,
        patient_id: uuid.UUID,
        program_id: uuid.UUID,
        exercises_total: int,
    ) -> RehabWorkoutSession:
        session = RehabWorkoutSession(
            patient_id=patient_id,
            program_id=program_id,
            exercises_total=exercises_total,
        )
        self.db.add(session)
        self.db.commit()
        self.db.refresh(session)
        return session

    def complete_session(
        self,
        session: RehabWorkoutSession,
        duration_seconds: int,
        exercises_completed: int,
        completions: list,
    ) -> RehabWorkoutSession:
        session.is_completed = True
        session.completed_at = datetime.now(timezone.utc)
        session.duration_seconds = duration_seconds
        session.exercises_completed = exercises_completed
        for c in completions:
            self.db.add(
                RehabExerciseCompletion(
                    session_id=session.id,
                    exercise_id=c["exercise_id"],
                    sets_completed=c["sets_completed"],
                    is_skipped=c["is_skipped"],
                    actual_duration_seconds=c.get("actual_duration_seconds"),
                )
            )
        self.db.commit()
        self.db.refresh(session)
        return session

    def get_session_by_id(self, session_id: uuid.UUID) -> Optional[RehabWorkoutSession]:
        return self.db.query(RehabWorkoutSession).filter(RehabWorkoutSession.id == session_id).first()

    # ── Progress ──────────────────────────────────────────────────────────────

    def get_completed_sessions(self, patient_id: uuid.UUID, program_id: uuid.UUID) -> List[RehabWorkoutSession]:
        return (
            self.db.query(RehabWorkoutSession)
            .filter(
                RehabWorkoutSession.patient_id == patient_id,
                RehabWorkoutSession.program_id == program_id,
                RehabWorkoutSession.is_completed == True,
            )
            .order_by(RehabWorkoutSession.completed_at.desc())
            .all()
        )
