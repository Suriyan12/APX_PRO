import enum
import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column,
    String,
    Boolean,
    BigInteger,
    DateTime,
    ForeignKey,
    Enum as SQLEnum,
    Text,
    Integer,
    Numeric,
    Date
)
from sqlalchemy import Uuid as UUID
from sqlalchemy.orm import relationship
from app.core.database import Base


def _utcnow():
    return datetime.now(timezone.utc)


class UserRole(str, enum.Enum):
    PATIENT = "patient"
    ADMIN = "admin"


class AppointmentStatus(str, enum.Enum):
    PENDING = "pending"          # booked by patient, awaiting admin approval
    APPROVED = "approved"        # admin approved/confirmed (online: meeting link set)
    REJECTED = "rejected"        # admin rejected the request (frees the slot)
    SCHEDULED = "scheduled"      # legacy "confirmed" status (still slot-occupying)
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    RESCHEDULED = "rescheduled"


class ConsultationType(str, enum.Enum):
    PHYSICAL = "physical"        # in-person visit
    ONLINE = "online"           # video consultation (meeting link required once approved)


class ScanStatus(str, enum.Enum):
    UPLOADING = "uploading"
    PENDING_REVIEW = "pending_review"
    REVIEWED = "reviewed"


class DiscountType(str, enum.Enum):
    PERCENTAGE = "percentage"
    FLAT = "flat"


# 1. User Model
class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    phone = Column(String(20), unique=True, nullable=True, index=True)
    full_name = Column(String(100), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(SQLEnum(UserRole), nullable=False, default=UserRole.PATIENT)
    is_active = Column(Boolean, nullable=False, default=True)
    # Account verification (required for new signups; existing users grandfathered).
    # Email channel: a hashed OTP is stored here. Phone channel: verification is
    # delegated to Firebase Authentication — no OTP is ever stored server-side.
    is_verified = Column(Boolean, nullable=False, default=False)
    otp_hash = Column(String(64), nullable=True)          # sha256 hex — never plain text
    otp_expires = Column(DateTime(timezone=True), nullable=True)
    otp_attempts = Column(Integer, nullable=False, default=0)   # wrong tries on current OTP
    otp_last_sent = Column(DateTime(timezone=True), nullable=True)  # resend rate limiting
    otp_channel = Column(String(10), nullable=True)  # 'email' | 'phone' — chosen at registration
    has_notes_access = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    refresh_tokens = relationship("RefreshToken", back_populates="user", cascade="all, delete-orphan")
    appointments_as_patient = relationship("Appointment", foreign_keys="[Appointment.patient_id]", back_populates="patient")
    appointments_as_admin = relationship("Appointment", foreign_keys="[Appointment.admin_id]", back_populates="admin")
    medical_reports = relationship("MedicalReport", back_populates="patient", cascade="all, delete-orphan")
    posture_scans = relationship("PostureScan", foreign_keys="[PostureScan.patient_id]", back_populates="patient", cascade="all, delete-orphan")
    assigned_programs = relationship("UserAssignedProgram", back_populates="user", cascade="all, delete-orphan")
    progress_logs = relationship("ProgressLog", back_populates="user", cascade="all, delete-orphan")
    password_reset_tokens = relationship("PasswordResetToken", back_populates="user", cascade="all, delete-orphan")
    notes_purchases = relationship("NotesPurchase", back_populates="user", cascade="all, delete-orphan")


# 2. Refresh Token Model
class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token = Column(String(512), unique=True, nullable=False, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    user = relationship("User", back_populates="refresh_tokens")


# 3. Password Reset Token Model
class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token = Column(String(512), unique=True, nullable=False, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    user = relationship("User", back_populates="password_reset_tokens")


# 4. Discount Code Model
class DiscountCode(Base):
    __tablename__ = "discount_codes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    code = Column(String(50), unique=True, nullable=False, index=True)
    discount_type = Column(SQLEnum(DiscountType), nullable=False)
    discount_value = Column(Numeric(10, 2), nullable=False)
    max_uses = Column(Integer, nullable=True)          # None = unlimited
    used_count = Column(Integer, nullable=False, default=0)
    valid_from = Column(DateTime(timezone=True), nullable=True)
    valid_until = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)


# 5. Appointment Model
class Appointment(Base):
    __tablename__ = "appointments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    admin_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    start_time = Column(DateTime(timezone=True), nullable=False)
    end_time = Column(DateTime(timezone=True), nullable=False)
    # SCHEDULED is the initial status for all API-created appointments.
    # PENDING is reserved for a future payment-confirmation flow.
    status = Column(SQLEnum(AppointmentStatus), nullable=False, default=AppointmentStatus.PENDING)
    # Physical (in-person) vs Online (video). Chosen by the patient at booking.
    # `values_callable` persists/reads the lowercase VALUE ('physical'/'online')
    # — matching the migration default and the CHECK constraint. Without it,
    # SQLAlchemy would store/expect the enum NAME ('PHYSICAL') and fail to load
    # the rows the migration back-filled with the lowercase default.
    consultation_type = Column(
        SQLEnum(
            ConsultationType,
            values_callable=lambda enum_cls: [m.value for m in enum_cls],
        ),
        nullable=False,
        default=ConsultationType.PHYSICAL,
    )
    # Video-consult meeting details. `meeting_provider` is an opaque provider id
    # (e.g. "google_meet") so the video platform can be swapped without schema
    # changes; `meeting_link` is only ever returned to the assigned patient/admin.
    meeting_provider = Column(String(30), nullable=True)
    meeting_link = Column(String(1000), nullable=True)
    # TRUE while an appointment sits in PENDING because the PATIENT rescheduled
    # it (vs an initial pending booking). Drives the reschedule-specific approval
    # / rejection emails. Set on reschedule; cleared on approve/reject.
    reschedule_pending = Column(Boolean, nullable=False, default=False)
    notes = Column(Text, nullable=True)
    consultation_fee = Column(Numeric(10, 2), nullable=False, default=0.00)
    discount_code_id = Column(UUID(as_uuid=True), ForeignKey("discount_codes.id", ondelete="SET NULL"), nullable=True)
    discount_code_used = Column(String(50), nullable=True)
    discount_amount = Column(Numeric(10, 2), nullable=False, default=0.00)
    final_amount = Column(Numeric(10, 2), nullable=False, default=0.00)
    cancellation_reason = Column(String(500), nullable=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    patient = relationship("User", foreign_keys=[patient_id], back_populates="appointments_as_patient")
    admin = relationship("User", foreign_keys=[admin_id], back_populates="appointments_as_admin")

    @property
    def patient_name(self):
        return self.patient.full_name if self.patient else None


# 6. Medical Report Model
class MedicalReport(Base):
    __tablename__ = "medical_reports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title = Column(String(150), nullable=False)
    file_path = Column(String(512), nullable=False)
    file_type = Column(String(50), nullable=False)
    uploaded_at = Column(DateTime(timezone=True), default=_utcnow)

    patient = relationship("User", back_populates="medical_reports")


# 6. Posture Scan Model
class PostureScan(Base):
    __tablename__ = "posture_scans"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    video_path = Column(String(512), nullable=False)
    status = Column(SQLEnum(ScanStatus), nullable=False, default=ScanStatus.UPLOADING)
    feedback = Column(Text, nullable=True)
    reviewed_by = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    patient = relationship("User", foreign_keys=[patient_id], back_populates="posture_scans")
    reviewer = relationship("User", foreign_keys=[reviewed_by])


# 7. Exercise Program Model
class ExerciseProgram(Base):
    __tablename__ = "exercise_programs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title = Column(String(150), nullable=False)
    description = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    exercises = relationship("Exercise", back_populates="program", cascade="all, delete-orphan")
    assignments = relationship("UserAssignedProgram", back_populates="program", cascade="all, delete-orphan")


# 8. User Assigned Programs
class UserAssignedProgram(Base):
    __tablename__ = "user_assigned_programs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    program_id = Column(UUID(as_uuid=True), ForeignKey("exercise_programs.id", ondelete="CASCADE"), nullable=False)
    assigned_at = Column(DateTime(timezone=True), default=_utcnow)
    is_active = Column(Boolean, nullable=False, default=True)

    user = relationship("User", back_populates="assigned_programs")
    program = relationship("ExerciseProgram", back_populates="assignments")


# 9. Exercise Model
class Exercise(Base):
    __tablename__ = "exercises"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    program_id = Column(UUID(as_uuid=True), ForeignKey("exercise_programs.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(150), nullable=False)
    description = Column(Text, nullable=True)
    video_url = Column(String(512), nullable=False)
    day_number = Column(Integer, nullable=False)
    sets = Column(Integer, nullable=False, default=3)
    reps = Column(Integer, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    order_index = Column(Integer, nullable=False)

    program = relationship("ExerciseProgram", back_populates="exercises")


# 10. Workout Log Model
class WorkoutLog(Base):
    __tablename__ = "workout_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    exercise_id = Column(UUID(as_uuid=True), ForeignKey("exercises.id", ondelete="CASCADE"), nullable=False)
    completed_at = Column(DateTime(timezone=True), default=_utcnow)

    exercise = relationship("Exercise")


# 11. Progress Log Model
class ProgressLog(Base):
    __tablename__ = "progress_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    log_date = Column(Date, nullable=False)
    weight = Column(Numeric(5, 2), nullable=True)
    chest = Column(Numeric(5, 2), nullable=True)
    waist = Column(Numeric(5, 2), nullable=True)
    hips = Column(Numeric(5, 2), nullable=True)
    systolic_bp = Column(Integer, nullable=True)
    diastolic_bp = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)

    user = relationship("User", back_populates="progress_logs")


# 12. Note File Type Enum
class NoteFileType(str, enum.Enum):
    PDF = "pdf"
    DOC = "doc"
    DOCX = "docx"
    PPT = "ppt"
    PPTX = "pptx"
    JPG = "jpg"
    JPEG = "jpeg"
    PNG = "png"
    TXT = "txt"


# 13. Note Model
class Note(Base):
    __tablename__ = "notes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    category = Column(String(100), nullable=False)
    tags = Column(String(500), nullable=True)
    file_name = Column(String(255), nullable=False)
    # Legacy S3/local key — kept nullable for backward compat; Drive is canonical now.
    file_path = Column(String(512), nullable=True)
    file_type = Column(SQLEnum(NoteFileType), nullable=False)
    file_size = Column(Integer, nullable=False)
    # Google Drive storage (StudyMaterials/<Category>/) — files live in Drive,
    # only these ids + metadata are stored here.
    google_drive_file_id = Column(String(255), nullable=True)
    google_drive_folder_id = Column(String(255), nullable=True)
    mime_type = Column(String(100), nullable=True)
    is_free = Column(Boolean, nullable=False, default=False)
    price = Column(Numeric(10, 2), nullable=False, default=0)
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    uploaded_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)
    is_active = Column(Boolean, nullable=False, default=True)

    uploader = relationship("User", foreign_keys=[uploaded_by])


# 15. Notes Purchase Model
class NotesPurchase(Base):
    __tablename__ = "notes_purchases"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    razorpay_order_id = Column(String(100), nullable=True)
    razorpay_payment_id = Column(String(100), nullable=True)
    amount = Column(Numeric(10, 2), nullable=False)
    purchased_at = Column(DateTime(timezone=True), default=_utcnow)
    is_active = Column(Boolean, nullable=False, default=True)

    user = relationship("User", back_populates="notes_purchases")


# 16. Medical Record Model (Google Drive backed)
class MedicalRecordStatus(str, enum.Enum):
    ACTIVE = "active"
    DELETED = "deleted"


class MedicalRecord(Base):
    __tablename__ = "medical_records"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    google_drive_file_id = Column(String(255), nullable=False)
    google_drive_folder_id = Column(String(255), nullable=False)
    file_name = Column(String(255), nullable=False)
    file_extension = Column(String(10), nullable=False)
    mime_type = Column(String(100), nullable=False)
    file_size = Column(Integer, nullable=False)
    category = Column(String(50), nullable=True)
    uploaded_at = Column(DateTime(timezone=True), default=_utcnow)
    uploaded_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    status = Column(String(20), nullable=False, default=MedicalRecordStatus.ACTIVE.value)

    patient = relationship("User", foreign_keys=[patient_id])
    uploader = relationship("User", foreign_keys=[uploaded_by])


# ─────────────────────────────────────────────────────────────────────────────
# Rehabilitation Program Models
# ─────────────────────────────────────────────────────────────────────────────

class ExerciseType(str, enum.Enum):
    REPS = "reps"
    TIMED = "timed"


class VideoType(str, enum.Enum):
    NONE = "none"
    YOUTUBE = "youtube"
    UPLOAD = "upload"


class RehabDifficulty(str, enum.Enum):
    EASY = "easy"
    MODERATE = "moderate"
    HARD = "hard"


class RehabProgram(Base):
    __tablename__ = "rehab_programs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_by = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    estimated_duration_days = Column(Integer, nullable=False, default=30)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    patient = relationship("User", foreign_keys=[patient_id])
    creator = relationship("User", foreign_keys=[created_by])
    exercises = relationship(
        "RehabExercise",
        back_populates="program",
        cascade="all, delete-orphan",
        order_by="RehabExercise.order_index",
    )
    sessions = relationship(
        "RehabWorkoutSession",
        back_populates="program",
        cascade="all, delete-orphan",
    )


class RehabExercise(Base):
    __tablename__ = "rehab_exercises"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    program_id = Column(UUID(as_uuid=True), ForeignKey("rehab_programs.id", ondelete="CASCADE"), nullable=False, index=True)
    name = Column(String(200), nullable=False)
    description = Column(String(500), nullable=True)
    instructions = Column(Text, nullable=True)
    exercise_type = Column(SQLEnum(ExerciseType), nullable=False, default=ExerciseType.REPS)
    sets = Column(Integer, nullable=False, default=3)
    reps = Column(Integer, nullable=True)
    duration_seconds = Column(Integer, nullable=True)
    rest_seconds = Column(Integer, nullable=False, default=30)
    difficulty = Column(SQLEnum(RehabDifficulty), nullable=False, default=RehabDifficulty.MODERATE)
    target_area = Column(String(100), nullable=True)
    notes = Column(Text, nullable=True)
    video_type = Column(SQLEnum(VideoType), nullable=False, default=VideoType.NONE)
    video_url = Column(String(1000), nullable=True)      # YouTube link (video_type=youtube)
    video_path = Column(String(500), nullable=True)      # legacy local/S3 path (no longer written)
    # Uploaded videos live in Google Drive (RehabilitationVideos/Program_<id>/),
    # exactly like Medical Records and Study Materials — never on local disk.
    video_drive_file_id = Column(String(255), nullable=True)
    video_mime_type = Column(String(100), nullable=True)
    video_file_size = Column(BigInteger, nullable=True)
    video_uploaded_at = Column(DateTime(timezone=True), nullable=True)
    order_index = Column(Integer, nullable=False)
    created_at = Column(DateTime(timezone=True), default=_utcnow)
    updated_at = Column(DateTime(timezone=True), default=_utcnow, onupdate=_utcnow)

    program = relationship("RehabProgram", back_populates="exercises")
    completions = relationship("RehabExerciseCompletion", back_populates="exercise")


class RehabWorkoutSession(Base):
    __tablename__ = "rehab_workout_sessions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    patient_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False, index=True)
    program_id = Column(UUID(as_uuid=True), ForeignKey("rehab_programs.id", ondelete="CASCADE"), nullable=False)
    started_at = Column(DateTime(timezone=True), nullable=False, default=_utcnow)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    is_completed = Column(Boolean, nullable=False, default=False)
    exercises_total = Column(Integer, nullable=False)
    exercises_completed = Column(Integer, nullable=False, default=0)
    duration_seconds = Column(Integer, nullable=True)

    program = relationship("RehabProgram", back_populates="sessions")
    exercise_completions = relationship(
        "RehabExerciseCompletion",
        back_populates="session",
        cascade="all, delete-orphan",
    )


class RehabExerciseCompletion(Base):
    __tablename__ = "rehab_exercise_completions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id = Column(UUID(as_uuid=True), ForeignKey("rehab_workout_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    exercise_id = Column(UUID(as_uuid=True), ForeignKey("rehab_exercises.id"), nullable=False)
    sets_completed = Column(Integer, nullable=False)
    is_skipped = Column(Boolean, nullable=False, default=False)
    completed_at = Column(DateTime(timezone=True), nullable=False, default=_utcnow)
    actual_duration_seconds = Column(Integer, nullable=True)

    session = relationship("RehabWorkoutSession", back_populates="exercise_completions")
    exercise = relationship("RehabExercise", back_populates="completions")
