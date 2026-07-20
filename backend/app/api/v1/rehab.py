import logging
import uuid
from typing import List

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Depends,
    File,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.orm import Session

from app.core.ranges import parse_range

from app.api.deps import get_current_admin_user, get_current_user
from app.core.database import get_db
from app.models.models import User
from app.schemas.schemas import (
    RehabDuplicateRequest,
    RehabExerciseCreate,
    RehabExerciseResponse,
    RehabExerciseUpdate,
    RehabMyProgramResponse,
    RehabProgramCreate,
    RehabProgramListItem,
    RehabProgramResponse,
    RehabProgramUpdate,
    RehabProgressResponse,
    RehabReorderItem,
    RehabSessionCompleteRequest,
    RehabSessionResponse,
    RehabSessionStartRequest,
)
from app.services import rehab_service as svc

router = APIRouter()
logger = logging.getLogger(__name__)


# ── Admin: Programs ───────────────────────────────────────────────────────────

@router.post("/programs", response_model=RehabProgramResponse, status_code=201)
def create_program(
    body: RehabProgramCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    return svc.create_program(
        db, admin,
        patient_id=body.patient_id,
        title=body.title,
        description=body.description,
        estimated_duration_days=body.estimated_duration_days,
    )


@router.get("/programs/patient/{patient_id}", response_model=List[RehabProgramListItem])
def list_patient_programs(
    patient_id: uuid.UUID,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    return svc.get_patient_programs(db, admin, patient_id)


@router.get("/programs/{program_id}", response_model=RehabProgramResponse)
def get_program(
    program_id: uuid.UUID,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return svc.get_program_detail(db, user, program_id)


@router.put("/programs/{program_id}", response_model=RehabProgramResponse)
def update_program(
    program_id: uuid.UUID,
    body: RehabProgramUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    return svc.update_program(
        db, admin, program_id,
        title=body.title,
        description=body.description,
        estimated_duration_days=body.estimated_duration_days,
    )


@router.delete("/programs/{program_id}", status_code=204)
def delete_program(
    program_id: uuid.UUID,
    bg: BackgroundTasks,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    orphaned = svc.delete_program(db, admin, program_id)
    bg.add_task(svc.cleanup_drive_videos, orphaned)


@router.post("/programs/{program_id}/duplicate", response_model=RehabProgramResponse, status_code=201)
def duplicate_program(
    program_id: uuid.UUID,
    body: RehabDuplicateRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    return svc.duplicate_program(db, admin, program_id, body.target_patient_id, body.new_title)


@router.put("/programs/{program_id}/toggle", response_model=RehabProgramResponse)
def toggle_program(
    program_id: uuid.UUID,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    return svc.toggle_program(db, admin, program_id)


# ── Admin: Exercises ──────────────────────────────────────────────────────────

@router.post("/programs/{program_id}/exercises", response_model=RehabExerciseResponse, status_code=201)
def add_exercise(
    program_id: uuid.UUID,
    body: RehabExerciseCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    return svc.add_exercise(
        db, admin, program_id,
        name=body.name,
        description=body.description,
        instructions=body.instructions,
        exercise_type=body.exercise_type,
        sets=body.sets,
        reps=body.reps,
        duration_seconds=body.duration_seconds,
        rest_seconds=body.rest_seconds,
        difficulty=body.difficulty,
        target_area=body.target_area,
        notes=body.notes,
        video_type=body.video_type,
        video_url=body.video_url,
    )


@router.put("/programs/{program_id}/exercises/{exercise_id}", response_model=RehabExerciseResponse)
def update_exercise(
    program_id: uuid.UUID,
    exercise_id: uuid.UUID,
    body: RehabExerciseUpdate,
    bg: BackgroundTasks,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    updates = body.model_dump(exclude_unset=True)
    exercise, orphaned = svc.update_exercise(db, admin, program_id, exercise_id, updates)
    bg.add_task(svc.cleanup_drive_videos, orphaned)
    return exercise


@router.delete("/programs/{program_id}/exercises/{exercise_id}", status_code=204)
def delete_exercise(
    program_id: uuid.UUID,
    exercise_id: uuid.UUID,
    bg: BackgroundTasks,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    orphaned = svc.delete_exercise(db, admin, program_id, exercise_id)
    bg.add_task(svc.cleanup_drive_videos, orphaned)


@router.put("/programs/{program_id}/reorder", status_code=200)
def reorder_exercises(
    program_id: uuid.UUID,
    items: List[RehabReorderItem],
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    svc.reorder_exercises(db, admin, program_id, [{"id": i.id, "order_index": i.order_index} for i in items])
    return {"message": "Reordered."}


@router.post("/programs/{program_id}/exercises/{exercise_id}/video")
async def upload_video(
    program_id: uuid.UUID,
    exercise_id: uuid.UUID,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin_user),
):
    """Store the workout video in Google Drive (RehabilitationVideos/…) and
    persist its metadata. The response's video_path is the API streaming path
    the app should play from — never a Drive URL or filesystem path."""
    if not file.content_type or "video" not in file.content_type:
        raise HTTPException(status_code=400, detail="File must be a video (MP4).")
    exercise = await svc.upload_exercise_video(db, admin, program_id, exercise_id, file)
    return {
        "video_path": f"/rehab/videos/{exercise.id}",
        "video_type": "upload",
        "file_size": exercise.video_file_size,
        "mime_type": exercise.video_mime_type,
    }


# ── Uploaded-video streaming (patient + admin) ────────────────────────────────

@router.get("/videos/{exercise_id}")
def stream_exercise_video(
    exercise_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Stream an uploaded workout video from Google Drive through the API.

    Supports HTTP Range (206) so the player can start instantly and seek
    without downloading the whole file. Access limited to the program's
    patient and admins; Drive URLs are never exposed."""
    from app.services.rehab_video_service import RehabVideoService
    from app.services.google_drive_service import GoogleDriveError

    exercise = svc.get_exercise_for_playback(db, user, exercise_id)
    video = RehabVideoService()
    file_id = exercise.video_drive_file_id
    mime = exercise.video_mime_type or "video/mp4"

    try:
        total = exercise.video_file_size or video.file_size(file_id)

        range_header = request.headers.get("range")
        if range_header:
            rng = parse_range(range_header, total)
            if rng is None:
                raise HTTPException(status_code=416, detail="Invalid Range header.")
            start, end = rng
            chunk = video.read_range(file_id, start, end)
            return Response(
                content=chunk,
                status_code=206,
                media_type=mime,
                headers={
                    "Content-Range": f"bytes {start}-{end}/{total}",
                    "Accept-Ranges": "bytes",
                    "Content-Length": str(len(chunk)),
                },
            )

        return StreamingResponse(
            video.stream(file_id),
            media_type=mime,
            headers={"Content-Length": str(total), "Accept-Ranges": "bytes"},
        )
    except HTTPException:
        raise
    except GoogleDriveError as e:
        if e.status_code == 404:
            logger.warning("Rehab video %s missing from Drive (exercise %s)", file_id, exercise_id)
            raise HTTPException(
                status_code=404,
                detail="This video file is no longer available. "
                       "Please ask your therapist to re-upload it.",
            )
        logger.exception("Drive error streaming rehab video %s", file_id)
        raise HTTPException(status_code=502, detail="Video storage is temporarily unavailable.")


# ── Patient ───────────────────────────────────────────────────────────────────

@router.get("/my", response_model=RehabMyProgramResponse)
def my_program(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return svc.get_my_program(db, user)


@router.get("/my/progress", response_model=RehabProgressResponse)
def my_progress(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return svc.get_my_progress(db, user)


@router.get("/sessions/today", response_model=RehabSessionResponse)
def today_session(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    session = svc.get_today_session(db, user)
    if not session:
        raise HTTPException(status_code=404, detail="No session today.")
    return session


@router.post("/sessions/start", response_model=RehabSessionResponse, status_code=201)
def start_session(
    body: RehabSessionStartRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return svc.start_session(db, user, body.program_id)


@router.post("/sessions/{session_id}/complete", response_model=RehabSessionResponse)
def complete_session(
    session_id: uuid.UUID,
    body: RehabSessionCompleteRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return svc.complete_session(
        db, user, session_id,
        duration_seconds=body.duration_seconds,
        exercises=body.exercises,
    )
