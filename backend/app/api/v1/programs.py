from datetime import date, datetime, timedelta
from typing import List
from uuid import UUID as PyUUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.config import settings
from app.api.deps import get_current_user, get_current_admin_user
from app.models.models import User, ExerciseProgram, UserAssignedProgram, Exercise, WorkoutLog, UserRole
from app.schemas.schemas import ExerciseResponse, ExerciseProgramResponse, WorkoutLogCreate, WorkoutLogResponse

router = APIRouter()


@router.get("/my-active", response_model=List[ExerciseProgramResponse])
def get_my_active_programs(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all active exercise programs assigned to the patient.
    """
    assigned = db.query(UserAssignedProgram).filter(
        UserAssignedProgram.user_id == current_user.id,
        UserAssignedProgram.is_active == True
    ).all()
    
    program_ids = [a.program_id for a in assigned]
    programs = db.query(ExerciseProgram).filter(ExerciseProgram.id.in_(program_ids)).all()
    return programs


@router.get("/{id}/exercises", response_model=List[ExerciseResponse])
def get_exercises_for_program(
    id: PyUUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get exercise video list for a specific program, appending CloudFront CDN root URL.
    """
    # Authorization check: user must be assigned to the program or be an admin
    if current_user.role != UserRole.ADMIN:
        assigned = db.query(UserAssignedProgram).filter(
            UserAssignedProgram.user_id == current_user.id,
            UserAssignedProgram.program_id == id,
            UserAssignedProgram.is_active == True
        ).first()
        if not assigned:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have access to this program."
            )

    exercises = db.query(Exercise).filter(Exercise.program_id == id).order_by(Exercise.order_index.asc()).all()
    
    # Append CloudFront CDN prefix if not already an absolute URL
    for exercise in exercises:
        if exercise.video_url and not exercise.video_url.startswith("http"):
            exercise.video_url = f"{settings.CLOUDFRONT_DOMAIN}/{exercise.video_url.lstrip('/')}"
            
    return exercises


@router.get("/workout-logs/today", response_model=List[WorkoutLogResponse])
def get_todays_workout_logs(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all exercise completions logged by the current user today.
    Used by the home dashboard to display daily progress.
    """
    today = date.today()
    day_start = datetime.combine(today, datetime.min.time())
    day_end = day_start + timedelta(days=1)
    logs = db.query(WorkoutLog).filter(
        WorkoutLog.user_id == current_user.id,
        WorkoutLog.completed_at >= day_start,
        WorkoutLog.completed_at < day_end,
    ).all()
    return logs


@router.post("/workout-logs", status_code=status.HTTP_201_CREATED)
def log_workout_completion(
    log_in: WorkoutLogCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Log an exercise as completed by the user.
    """
    # Verify exercise exists
    exercise = db.query(Exercise).filter(Exercise.id == log_in.exercise_id).first()
    if not exercise:
        raise HTTPException(status_code=404, detail="Exercise not found")

    db_log = WorkoutLog(
        user_id=current_user.id,
        exercise_id=log_in.exercise_id
    )
    db.add(db_log)
    db.commit()
    return {"message": "Exercise completion logged successfully"}


@router.post("/", response_model=ExerciseProgramResponse, status_code=status.HTTP_201_CREATED)
def create_program(
    title: str,
    description: str = None,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    (Admin only) Create a new rehabilitation/workout program template.
    """
    db_program = ExerciseProgram(title=title, description=description)
    db.add(db_program)
    db.commit()
    db.refresh(db_program)
    return db_program


@router.post("/assign", status_code=status.HTTP_201_CREATED)
def assign_program_to_user(
    user_id: PyUUID,
    program_id: PyUUID,
    current_admin: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db)
):
    """
    (Admin only) Assign a workout/rehab program to a patient.
    """
    # Check if user exists
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Patient not found")

    # Check if program exists
    program = db.query(ExerciseProgram).filter(ExerciseProgram.id == program_id).first()
    if not program:
        raise HTTPException(status_code=404, detail="Program not found")

    # Check if assignment already exists
    existing = db.query(UserAssignedProgram).filter(
        UserAssignedProgram.user_id == user_id,
        UserAssignedProgram.program_id == program_id
    ).first()
    
    if existing:
        existing.is_active = True
        db.commit()
    else:
        db_assign = UserAssignedProgram(user_id=user_id, program_id=program_id)
        db.add(db_assign)
        db.commit()

    return {"message": "Program assigned successfully"}
