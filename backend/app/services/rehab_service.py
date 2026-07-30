import logging
import uuid
from datetime import datetime, timezone, timedelta
from typing import List, Optional

from fastapi import HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.models.models import User, UserRole, RehabExercise, RehabProgram
from app.repositories.rehab_repository import RehabRepository

logger = logging.getLogger(__name__)


def _repo(db: Session) -> RehabRepository:
    return RehabRepository(db)


def _require_program(db: Session, program_id: uuid.UUID) -> RehabProgram:
    program = _repo(db).get_by_id(program_id)
    if not program:
        raise HTTPException(status_code=404, detail="Program not found.")
    return program


def _require_admin(user: User) -> None:
    if user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin access required.")


def _require_patient_access(user: User, program: RehabProgram) -> None:
    if user.role == UserRole.ADMIN:
        return
    if program.patient_id != user.id:
        raise HTTPException(status_code=403, detail="Access denied.")


def compute_progress(sessions):
    if not sessions:
        return {"streak_days": 0, "total_sessions": 0, "total_minutes": 0,
                "completion_percent": 0.0, "last_completed_at": None}

    total_sessions = len(sessions)
    total_seconds = sum(s.duration_seconds or 0 for s in sessions)
    total_minutes = total_seconds // 60

    completed_ex = sum(s.exercises_completed for s in sessions)
    total_ex = sum(s.exercises_total for s in sessions)
    completion_percent = round((completed_ex / total_ex * 100) if total_ex > 0 else 0.0, 1)

    last_completed_at = sessions[0].completed_at

    now_utc = datetime.now(timezone.utc)
    today = now_utc.date()
    session_dates = sorted(
        {s.completed_at.date() for s in sessions if s.completed_at},
        reverse=True,
    )

    streak = 0
    expected = today
    if session_dates and session_dates[0] < today - timedelta(days=1):
        streak = 0
    else:
        for d in session_dates:
            if d == expected or d == expected - timedelta(days=1):
                if d == expected - timedelta(days=1) and streak == 0:
                    expected = d
                streak += 1
                expected = d - timedelta(days=1)
            elif d < expected:
                break

    return {
        "streak_days": streak,
        "total_sessions": total_sessions,
        "total_minutes": total_minutes,
        "completion_percent": completion_percent,
        "last_completed_at": last_completed_at,
    }


# ── Admin: Programs ───────────────────────────────────────────────────────────

def create_program(db: Session, admin: User, patient_id: uuid.UUID, title: str,
                   description: Optional[str], estimated_duration_days: int) -> RehabProgram:
    _require_admin(admin)
    repo = _repo(db)
    repo.deactivate_all_for_patient(patient_id)
    return repo.create_program(
        patient_id=patient_id,
        created_by=admin.id,
        title=title,
        description=description,
        estimated_duration_days=estimated_duration_days,
    )


def get_patient_programs(db: Session, admin: User, patient_id: uuid.UUID):
    _require_admin(admin)
    programs = _repo(db).get_programs_for_patient(patient_id)
    result = []
    for p in programs:
        result.append({
            "id": p.id,
            "patient_id": p.patient_id,
            "created_by": p.created_by,
            "title": p.title,
            "description": p.description,
            "estimated_duration_days": p.estimated_duration_days,
            "is_active": p.is_active,
            "created_at": p.created_at,
            "exercise_count": len(p.exercises),
        })
    return result


def get_program_detail(db: Session, user: User, program_id: uuid.UUID) -> RehabProgram:
    program = _require_program(db, program_id)
    _require_patient_access(user, program)
    return program


def update_program(db: Session, admin: User, program_id: uuid.UUID,
                   title: Optional[str], description: Optional[str],
                   estimated_duration_days: Optional[int]) -> RehabProgram:
    _require_admin(admin)
    program = _require_program(db, program_id)
    return _repo(db).update_program(program, title, description, estimated_duration_days)


def delete_program(db: Session, admin: User, program_id: uuid.UUID) -> list:
    """Deletes the program (exercises cascade). Returns the Drive file ids of
    its uploaded videos that are now orphaned, for background cleanup."""
    _require_admin(admin)
    program = _require_program(db, program_id)
    candidate_ids = [ex.video_drive_file_id for ex in program.exercises if ex.video_drive_file_id]
    _repo(db).delete_program(program)
    return orphan_video_ids(db, candidate_ids)


def duplicate_program(db: Session, admin: User, program_id: uuid.UUID,
                      target_patient_id: uuid.UUID,
                      new_title: Optional[str]) -> RehabProgram:
    _require_admin(admin)
    source = _require_program(db, program_id)
    repo = _repo(db)
    repo.deactivate_all_for_patient(target_patient_id)
    new_program = repo.create_program(
        patient_id=target_patient_id,
        created_by=admin.id,
        title=new_title or f"{source.title} (Copy)",
        description=source.description,
        estimated_duration_days=source.estimated_duration_days,
    )
    for ex in source.exercises:
        repo.add_exercise(
            program_id=new_program.id,
            name=ex.name,
            description=ex.description,
            instructions=ex.instructions,
            exercise_type=ex.exercise_type,
            sets=ex.sets,
            reps=ex.reps,
            duration_seconds=ex.duration_seconds,
            rest_seconds=ex.rest_seconds,
            difficulty=ex.difficulty,
            target_area=ex.target_area,
            notes=ex.notes,
            video_type=ex.video_type,
            video_url=ex.video_url,
            video_path=ex.video_path,
            # Duplicates share the source's Drive file; deletion is safe because
            # cleanup only removes files no exercise references anymore.
            video_drive_file_id=ex.video_drive_file_id,
            video_mime_type=ex.video_mime_type,
            video_file_size=ex.video_file_size,
            video_uploaded_at=ex.video_uploaded_at,
        )
    return _repo(db).get_by_id(new_program.id)


def toggle_program(db: Session, admin: User, program_id: uuid.UUID) -> RehabProgram:
    _require_admin(admin)
    program = _require_program(db, program_id)
    repo = _repo(db)
    if not program.is_active:
        repo.deactivate_all_for_patient(program.patient_id)
        return repo.set_active(program, True)
    return repo.set_active(program, False)


# ── Admin: Patient workout dashboard ──────────────────────────────────────────

def _empty_dashboard() -> dict:
    return {
        "has_active_program": False,
        "program_id": None,
        "program_title": None,
        "estimated_duration_days": None,
        "overall_progress_percent": 0.0,
        "today_status": "not_started",
        "last_completed_at": None,
        "assigned_sessions": 0,
        "completed_sessions": 0,
        "remaining_sessions": 0,
        "compliance_percent": 0.0,
    }


def get_patient_dashboard(db: Session, admin: User, patient_id: uuid.UUID) -> dict:
    """Workout-progress summary for a patient's ACTIVE program only.

    Model: a program prescribes one session per day across its
    ``estimated_duration_days`` (= assigned sessions). Overall progress is
    completed/assigned; compliance is completed vs the sessions expected by
    today (min of days-elapsed and assigned), so a patient early in a long
    program isn't penalised for sessions not yet due. All counts are scoped to
    the active program, keeping each program's progress independent.
    """
    _require_admin(admin)
    repo = _repo(db)
    program = repo.get_active_for_patient(patient_id)
    if not program:
        return _empty_dashboard()

    assigned = program.estimated_duration_days or 0
    completed = repo.count_completed_sessions(patient_id, program.id)
    remaining = max(0, assigned - completed)
    overall = round(min(completed / assigned * 100, 100.0), 1) if assigned > 0 else 0.0

    today = datetime.now(timezone.utc).date()
    start = program.created_at.date() if program.created_at else today
    days_elapsed = (today - start).days + 1  # inclusive of the start day
    expected_to_date = max(1, min(days_elapsed, assigned)) if assigned > 0 else 1
    compliance = round(min(completed / expected_to_date * 100, 100.0), 1)

    today_session = repo.get_today_session_for_program(patient_id, program.id)
    if today_session is None:
        today_status = "not_started"
    elif today_session.is_completed:
        today_status = "completed"
    else:
        today_status = "in_progress"

    last = repo.get_last_completed_session(patient_id, program.id)

    return {
        "has_active_program": True,
        "program_id": program.id,
        "program_title": program.title,
        "estimated_duration_days": assigned,
        "overall_progress_percent": overall,
        "today_status": today_status,
        "last_completed_at": last.completed_at if last else None,
        "assigned_sessions": assigned,
        "completed_sessions": completed,
        "remaining_sessions": remaining,
        "compliance_percent": compliance,
    }


def get_patient_sessions(db: Session, admin: User, patient_id: uuid.UUID,
                         limit: int, offset: int) -> dict:
    """Paginated workout history for a patient, newest first (admin view)."""
    _require_admin(admin)
    rows, total = _repo(db).list_sessions_for_patient(patient_id, limit, offset)
    items = [
        {
            "id": s.id,
            "program_id": s.program_id,
            "program_title": s.program.title if s.program else "—",
            "session_date": s.session_date,
            "started_at": s.started_at,
            "completed_at": s.completed_at,
            # Coalesce for any legacy row written before the status column existed.
            "status": s.status or ("completed" if s.is_completed else "in_progress"),
            "duration_seconds": s.duration_seconds,
            "exercises_total": s.exercises_total,
            "exercises_completed": s.exercises_completed,
        }
        for s in rows
    ]
    return {"items": items, "total": total, "limit": limit, "offset": offset}


# ── Admin: Exercises ──────────────────────────────────────────────────────────

def add_exercise(db: Session, admin: User, program_id: uuid.UUID, **kwargs):
    _require_admin(admin)
    _require_program(db, program_id)
    return _repo(db).add_exercise(program_id=program_id, **kwargs)


def update_exercise(db: Session, admin: User, program_id: uuid.UUID,
                    exercise_id: uuid.UUID, updates: dict):
    """Returns (exercise, orphaned_drive_ids). Switching the video type away
    from 'upload' releases the Drive file (cleaned up in the background)."""
    _require_admin(admin)
    repo = _repo(db)
    exercise = repo.get_exercise(exercise_id)
    if not exercise or exercise.program_id != program_id:
        raise HTTPException(status_code=404, detail="Exercise not found.")

    released_drive_id = None
    new_type = updates.get("video_type")
    if new_type and new_type != "upload" and exercise.video_drive_file_id:
        released_drive_id = exercise.video_drive_file_id
        updates = {
            **updates,
            "video_drive_file_id": None,
            "video_mime_type": None,
            "video_file_size": None,
            "video_uploaded_at": None,
        }

    exercise = repo.update_exercise(exercise, updates)
    orphaned = orphan_video_ids(db, [released_drive_id]) if released_drive_id else []
    return exercise, orphaned


def delete_exercise(db: Session, admin: User, program_id: uuid.UUID,
                    exercise_id: uuid.UUID) -> list:
    """Deletes the exercise. Returns orphaned Drive video ids for cleanup."""
    _require_admin(admin)
    repo = _repo(db)
    exercise = repo.get_exercise(exercise_id)
    if not exercise or exercise.program_id != program_id:
        raise HTTPException(status_code=404, detail="Exercise not found.")
    candidate = exercise.video_drive_file_id
    repo.delete_exercise(exercise)
    return orphan_video_ids(db, [candidate]) if candidate else []


def reorder_exercises(db: Session, admin: User, program_id: uuid.UUID,
                      items: list) -> None:
    _require_admin(admin)
    _require_program(db, program_id)
    _repo(db).reorder_exercises(items)


async def upload_exercise_video(db: Session, admin: User, program_id: uuid.UUID,
                                exercise_id: uuid.UUID, file: UploadFile) -> RehabExercise:
    """Store an uploaded workout video in Google Drive
    (RehabilitationVideos/Program_<id>/) and persist its metadata. Local
    filesystem paths are never written."""
    from app.core.config import settings
    from app.services.rehab_video_service import RehabVideoService

    _require_admin(admin)
    repo = _repo(db)
    exercise = repo.get_exercise(exercise_id)
    if not exercise or exercise.program_id != program_id:
        raise HTTPException(status_code=404, detail="Exercise not found.")

    # Size guard — configurable, never hardcoded.
    max_bytes = settings.REHAB_VIDEO_MAX_FILE_SIZE_MB * 1024 * 1024
    file.file.seek(0, 2)
    size = file.file.tell()
    file.file.seek(0)
    if size == 0:
        raise HTTPException(status_code=400, detail="The uploaded file is empty.")
    if size > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"Video is too large. Maximum size is "
                   f"{settings.REHAB_VIDEO_MAX_FILE_SIZE_MB} MB.",
        )

    mime = file.content_type or "video/mp4"
    old_drive_id = exercise.video_drive_file_id

    try:
        drive_id, _folder_id = RehabVideoService().store(
            program_id, file.filename or f"{exercise_id}.mp4", mime, file.file
        )
    except HTTPException:
        raise
    except Exception:
        logger.exception("Drive upload failed for rehab exercise %s", exercise_id)
        raise HTTPException(
            status_code=502,
            detail="Video upload to storage failed. Please try again.",
        )

    exercise = repo.set_exercise_video_drive(exercise, drive_id, mime, size)

    # Replaced a previous upload → remove the orphaned Drive file (best-effort,
    # only if no other exercise still references it, e.g. via duplication).
    if old_drive_id and old_drive_id != drive_id:
        cleanup_drive_videos(orphan_video_ids(db, [old_drive_id]))

    return exercise


# ── Uploaded-video playback + Drive cleanup ──────────────────────────────────

def get_exercise_for_playback(db: Session, user: User, exercise_id: uuid.UUID) -> RehabExercise:
    """Authorize video access: the program's patient or any admin."""
    exercise = _repo(db).get_exercise(exercise_id)
    if not exercise:
        raise HTTPException(status_code=404, detail="Exercise not found.")
    program = _repo(db).get_by_id(exercise.program_id)
    if user.role != UserRole.ADMIN and (program is None or program.patient_id != user.id):
        raise HTTPException(status_code=403, detail="Access denied.")
    if exercise.video_type != "upload" or not exercise.video_drive_file_id:
        raise HTTPException(
            status_code=404,
            detail="This exercise has no playable uploaded video. "
                   "Please ask your therapist to re-upload it.",
        )
    return exercise


def orphan_video_ids(db: Session, candidate_ids: list) -> list:
    """Of the candidate Drive file ids, return those no longer referenced by
    ANY exercise (duplicated programs share the same Drive file)."""
    candidates = [c for c in candidate_ids if c]
    if not candidates:
        return []
    still_used = {
        row[0]
        for row in db.query(RehabExercise.video_drive_file_id)
        .filter(RehabExercise.video_drive_file_id.in_(candidates))
        .all()
    }
    return [c for c in candidates if c not in still_used]


def cleanup_drive_videos(file_ids: list) -> None:
    """Best-effort Drive deletion (run in a BackgroundTask). Never raises."""
    if not file_ids:
        return
    try:
        from app.services.rehab_video_service import RehabVideoService
        service = RehabVideoService()
        for fid in file_ids:
            try:
                service.remove(fid)
            except Exception:
                logger.exception("Could not delete rehab video %s from Drive", fid)
    except Exception:
        logger.exception("Rehab video Drive cleanup unavailable; ids left: %s", file_ids)


# ── Patient: Program + Progress ───────────────────────────────────────────────

def get_my_program(db: Session, patient: User):
    repo = _repo(db)
    program = repo.get_active_for_patient(patient.id)
    if not program:
        raise HTTPException(status_code=404, detail="No active rehabilitation program assigned.")
    sessions = repo.get_completed_sessions(patient.id, program.id)
    progress = compute_progress(sessions)
    today_session = repo.get_today_session(patient.id)
    return {
        "program": program,
        "progress": progress,
        "today_session": today_session,
    }


def get_my_progress(db: Session, patient: User):
    repo = _repo(db)
    program = repo.get_active_for_patient(patient.id)
    if not program:
        return {"streak_days": 0, "total_sessions": 0, "total_minutes": 0,
                "completion_percent": 0.0, "last_completed_at": None}
    sessions = repo.get_completed_sessions(patient.id, program.id)
    return compute_progress(sessions)


def get_today_session(db: Session, patient: User):
    return _repo(db).get_today_session(patient.id)


def start_session(db: Session, patient: User, program_id: uuid.UUID):
    repo = _repo(db)
    program = _require_program(db, program_id)
    if program.patient_id != patient.id:
        raise HTTPException(status_code=403, detail="Access denied.")
    exercises_total = len(program.exercises)
    if exercises_total == 0:
        raise HTTPException(status_code=400, detail="Program has no exercises.")
    return repo.create_session(patient.id, program_id, exercises_total)


def complete_session(db: Session, patient: User, session_id: uuid.UUID,
                     duration_seconds: int, exercises: list):
    repo = _repo(db)
    session = repo.get_session_by_id(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found.")
    if session.patient_id != patient.id:
        raise HTTPException(status_code=403, detail="Access denied.")
    if session.is_completed:
        raise HTTPException(status_code=400, detail="Session already completed.")

    # Only accept completions for exercises that actually belong to this
    # program. This prevents (a) a 500 from a foreign-key violation on a bogus
    # exercise_id, and (b) a client inflating progress by submitting extra or
    # other-program exercise ids. Duplicates are collapsed.
    program = _require_program(db, session.program_id)
    valid_ids = {ex.id for ex in program.exercises}
    seen: set = set()
    completions = []
    for e in exercises:
        if e.exercise_id not in valid_ids or e.exercise_id in seen:
            continue
        seen.add(e.exercise_id)
        completions.append({
            "exercise_id": e.exercise_id,
            "sets_completed": e.sets_completed,
            "is_skipped": e.is_skipped,
            "actual_duration_seconds": e.actual_duration_seconds,
        })

    completed = sum(1 for c in completions if not c["is_skipped"])
    # Never let completed exceed the total recorded at start — keeps
    # completion_percent within 0..100 even under a crafted payload.
    exercises_completed = min(completed, session.exercises_total)
    return repo.complete_session(session, duration_seconds, exercises_completed, completions)
