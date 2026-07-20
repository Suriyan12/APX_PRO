from datetime import datetime, date, timezone
from typing import Optional, List
from uuid import UUID
from pydantic import BaseModel, EmailStr, Field, field_serializer, field_validator
from app.models.models import UserRole, AppointmentStatus, ConsultationType, ScanStatus, DiscountType, NoteFileType, ExerciseType, VideoType, RehabDifficulty


# --- USER & AUTH SCHEMAS ---

class UserBase(BaseModel):
    email: EmailStr
    full_name: str
    phone: Optional[str] = None


class UserCreate(UserBase):
    password: str = Field(..., min_length=8)
    role: UserRole = UserRole.PATIENT
    # Which channel to verify with at signup: "email" or "phone".
    verification_method: str = "email"


class UserResponse(UserBase):
    id: UUID
    role: UserRole
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True


class UserAdminListResponse(UserResponse):
    """Extended user details returned only to admin endpoints."""
    pass


class AdminCreateUserRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=100)
    email: EmailStr
    phone: Optional[str] = None
    password: str = Field(..., min_length=8)
    role: UserRole = UserRole.PATIENT


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: UserResponse


class TokenRefreshRequest(BaseModel):
    refresh_token: str


class FirebaseLoginRequest(BaseModel):
    """Phone-OTP login: the app verified the SMS code with Firebase and sends
    the resulting ID token. The backend never sees or stores the OTP."""
    id_token: str


class VerifyPhoneRequest(BaseModel):
    """Activate a pending phone-channel registration with a Firebase ID token."""
    email: EmailStr
    id_token: str


class RegistrationResponse(BaseModel):
    message: str
    email: EmailStr
    channel: str = "email"          # where verification happens
    phone_e164: Optional[str] = None  # E.164 number the app should verify via Firebase
    verification_required: bool = True


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6)


class ResendVerificationRequest(BaseModel):
    email: EmailStr


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ForgotPasswordVerifyRequest(BaseModel):
    email: EmailStr
    otp: str = Field(..., min_length=6, max_length=6)


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str = Field(..., min_length=8)


# --- APPOINTMENT SCHEMAS ---

class AppointmentBase(BaseModel):
    start_time: datetime
    end_time: datetime
    notes: Optional[str] = Field(None, max_length=500)


class AppointmentCreate(AppointmentBase):
    admin_id: Optional[UUID] = None
    discount_code: Optional[str] = None
    # Physical (in-person) vs online (video). Defaults to physical so older
    # clients that don't send it keep working.
    consultation_type: ConsultationType = ConsultationType.PHYSICAL


class AppointmentRescheduleRequest(AppointmentBase):
    # Reschedule changes date/time (and optionally notes). The consultation type
    # must be PRESERVED unless the patient explicitly changes it, so this field
    # is Optional with NO default: omitted => keep the appointment's current
    # type; sent => switch to the given type. (Contrast AppointmentCreate, whose
    # consultation_type defaults to PHYSICAL for booking.)
    consultation_type: Optional[ConsultationType] = None


class AppointmentCancelRequest(BaseModel):
    # Optional so the existing no-body cancel call keeps working unchanged.
    reason: Optional[str] = Field(None, max_length=500)


class AppointmentApproveRequest(BaseModel):
    """Admin approval. For an ONLINE consultation a meeting provider + link are
    required and validated server-side; ignored for a physical visit."""
    meeting_provider: Optional[str] = Field(None, max_length=30)
    meeting_link: Optional[str] = Field(None, max_length=1000)


class AppointmentRejectRequest(BaseModel):
    reason: Optional[str] = Field(None, max_length=500)


class AppointmentResponse(AppointmentBase):
    id: UUID
    patient_id: UUID
    patient_name: Optional[str] = None
    admin_id: Optional[UUID] = None
    status: AppointmentStatus
    consultation_type: ConsultationType = ConsultationType.PHYSICAL
    meeting_provider: Optional[str] = None
    # Only ever populated on appointments the caller is authorized to see
    # (their own, or any as an admin) — /my is the only endpoint returning it.
    meeting_link: Optional[str] = None
    consultation_fee: float = 0.0
    discount_amount: float = 0.0
    final_amount: float = 0.0
    discount_code_used: Optional[str] = None
    cancellation_reason: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}

    @field_serializer('start_time', 'end_time', 'created_at')
    def _serialize_utc(self, dt: datetime, _info):
        """DB columns are naive DATETIME2 holding UTC. Emit an explicit UTC
        offset so clients (Dart parses offset-less strings as DEVICE-LOCAL
        time) can never misinterpret the instant."""
        if dt is None:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc).isoformat()

    @field_validator('consultation_fee', 'discount_amount', 'final_amount', mode='before')
    @classmethod
    def coerce_decimal(cls, v):
        from decimal import Decimal
        if v is None:
            return 0.0
        if isinstance(v, Decimal):
            return float(v)
        return v


class SlotResponse(BaseModel):
    start_time: datetime
    end_time: datetime


class DiscountValidateRequest(BaseModel):
    code: str = Field(..., min_length=2, max_length=50)


class DiscountValidateResponse(BaseModel):
    code: str
    discount_type: DiscountType
    discount_value: float
    discount_amount: float
    original_fee: float
    final_amount: float
    message: str


# --- MEDICAL REPORT SCHEMAS ---

class ReportUploadConfirmRequest(BaseModel):
    title: str
    file_path: str
    file_type: str


class MedicalReportResponse(BaseModel):
    id: UUID
    patient_id: UUID
    title: str
    file_path: str
    file_type: str
    uploaded_at: datetime

    class Config:
        from_attributes = True


# --- MEDICAL RECORDS (GOOGLE DRIVE) SCHEMAS ---

class MedicalRecordResponse(BaseModel):
    id: UUID
    patient_id: UUID
    file_name: str
    file_extension: str
    mime_type: str
    file_size: int
    category: Optional[str] = None
    uploaded_at: datetime
    uploaded_by: Optional[UUID] = None
    status: str

    class Config:
        from_attributes = True


# --- POSTURE SCAN SCHEMAS ---

class PostureConfirmRequest(BaseModel):
    video_path: str


class PostureReviewRequest(BaseModel):
    feedback: str


class PatientSummary(BaseModel):
    id: UUID
    full_name: str
    email: str
    phone: Optional[str] = None

    class Config:
        from_attributes = True


class PostureScanResponse(BaseModel):
    id: UUID
    patient_id: UUID
    patient: Optional[PatientSummary] = None
    video_path: str
    status: ScanStatus
    feedback: Optional[str] = None
    reviewed_by: Optional[UUID] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# --- EXERCISE & PROGRAM SCHEMAS ---

class ExerciseResponse(BaseModel):
    id: UUID
    program_id: UUID
    name: str
    description: Optional[str] = None
    video_url: str
    day_number: int
    sets: int
    reps: Optional[int] = None
    duration_seconds: Optional[int] = None
    order_index: int

    class Config:
        from_attributes = True


class ExerciseProgramResponse(BaseModel):
    id: UUID
    title: str
    description: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class WorkoutLogCreate(BaseModel):
    exercise_id: UUID


class WorkoutLogResponse(BaseModel):
    id: UUID
    user_id: UUID
    exercise_id: UUID
    completed_at: datetime

    class Config:
        from_attributes = True


# --- PROGRESS LOG SCHEMAS ---

class ProgressLogCreate(BaseModel):
    log_date: Optional[date] = None
    weight: Optional[float] = None
    chest: Optional[float] = None
    waist: Optional[float] = None
    hips: Optional[float] = None
    systolic_bp: Optional[int] = None
    diastolic_bp: Optional[int] = None


class ProgressLogResponse(BaseModel):
    id: UUID
    user_id: UUID
    log_date: date
    weight: Optional[float] = None
    chest: Optional[float] = None
    waist: Optional[float] = None
    hips: Optional[float] = None
    systolic_bp: Optional[int] = None
    diastolic_bp: Optional[int] = None
    created_at: datetime

    class Config:
        from_attributes = True


# --- NOTES SCHEMAS ---

class NoteResponse(BaseModel):
    id: UUID
    title: str
    description: Optional[str]
    category: str
    tags: Optional[str]
    file_name: str
    file_type: str
    file_size: int
    is_free: bool = False
    price: float = 0
    uploaded_at: datetime
    updated_at: datetime
    is_active: Optional[bool] = None

    class Config:
        from_attributes = True


class NoteAdminResponse(NoteResponse):
    uploaded_by: Optional[UUID]
    is_active: bool


class NotesAccessStatus(BaseModel):
    has_access: bool
    is_admin: bool
    purchased_at: Optional[datetime]


class NotesPurchaseOrderResponse(BaseModel):
    order_id: str
    amount: int
    currency: str
    key_id: str
    dev_mode: bool = False


class NotesPurchaseGrantResponse(BaseModel):
    status: str
    dev_mode: bool = False
    purchased_at: Optional[datetime] = None


class NotesPurchaseVerifyRequest(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


class AdminGrantAccessRequest(BaseModel):
    user_id: UUID
    grant: bool


# --- REHAB PROGRAM SCHEMAS ---

class RehabExerciseCreate(BaseModel):
    name: str = Field(..., max_length=200)
    description: Optional[str] = Field(None, max_length=500)
    instructions: Optional[str] = None
    exercise_type: str = Field("reps", pattern="^(reps|timed)$")
    sets: int = Field(3, ge=1, le=20)
    reps: Optional[int] = Field(None, ge=1, le=200)
    duration_seconds: Optional[int] = Field(None, ge=1, le=3600)
    rest_seconds: int = Field(30, ge=0, le=600)
    difficulty: str = Field("moderate", pattern="^(easy|moderate|hard)$")
    target_area: Optional[str] = Field(None, max_length=100)
    notes: Optional[str] = None
    video_type: str = Field("none", pattern="^(none|youtube|upload)$")
    video_url: Optional[str] = Field(None, max_length=1000)


class RehabExerciseUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    instructions: Optional[str] = None
    exercise_type: Optional[str] = Field(None, pattern="^(reps|timed)$")
    sets: Optional[int] = Field(None, ge=1, le=20)
    reps: Optional[int] = Field(None, ge=1, le=200)
    duration_seconds: Optional[int] = Field(None, ge=1, le=3600)
    rest_seconds: Optional[int] = Field(None, ge=0, le=600)
    difficulty: Optional[str] = Field(None, pattern="^(easy|moderate|hard)$")
    target_area: Optional[str] = None
    notes: Optional[str] = None
    video_type: Optional[str] = Field(None, pattern="^(none|youtube|upload)$")
    video_url: Optional[str] = None


class RehabExerciseResponse(BaseModel):
    id: UUID
    program_id: UUID
    name: str
    description: Optional[str] = None
    instructions: Optional[str] = None
    exercise_type: str
    sets: int
    reps: Optional[int] = None
    duration_seconds: Optional[int] = None
    rest_seconds: int
    difficulty: str
    target_area: Optional[str] = None
    notes: Optional[str] = None
    video_type: str
    video_url: Optional[str] = None
    video_path: Optional[str] = None
    video_file_size: Optional[int] = None
    video_mime_type: Optional[str] = None
    order_index: int
    created_at: datetime
    model_config = {"from_attributes": True}


class RehabProgramCreate(BaseModel):
    patient_id: UUID
    title: str = Field(..., max_length=200)
    description: Optional[str] = None
    estimated_duration_days: int = Field(30, ge=1, le=365)


class RehabProgramUpdate(BaseModel):
    title: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    estimated_duration_days: Optional[int] = Field(None, ge=1, le=365)


class RehabProgramResponse(BaseModel):
    id: UUID
    patient_id: UUID
    created_by: UUID
    title: str
    description: Optional[str] = None
    estimated_duration_days: int
    is_active: bool
    created_at: datetime
    exercises: List[RehabExerciseResponse] = []
    model_config = {"from_attributes": True}


class RehabProgramListItem(BaseModel):
    id: UUID
    patient_id: UUID
    created_by: UUID
    title: str
    description: Optional[str] = None
    estimated_duration_days: int
    is_active: bool
    created_at: datetime
    exercise_count: int = 0
    model_config = {"from_attributes": True}


class RehabReorderItem(BaseModel):
    id: UUID
    order_index: int


class RehabDuplicateRequest(BaseModel):
    target_patient_id: UUID
    new_title: Optional[str] = None


class RehabSessionStartRequest(BaseModel):
    program_id: UUID


class RehabExerciseCompletionInput(BaseModel):
    exercise_id: UUID
    sets_completed: int = Field(..., ge=0)
    is_skipped: bool = False
    actual_duration_seconds: Optional[int] = None


class RehabSessionCompleteRequest(BaseModel):
    duration_seconds: int = Field(..., ge=0)
    exercises: List[RehabExerciseCompletionInput]


class RehabSessionResponse(BaseModel):
    id: UUID
    patient_id: UUID
    program_id: UUID
    started_at: datetime
    completed_at: Optional[datetime] = None
    is_completed: bool
    exercises_total: int
    exercises_completed: int
    duration_seconds: Optional[int] = None
    model_config = {"from_attributes": True}


class RehabProgressResponse(BaseModel):
    streak_days: int
    total_sessions: int
    total_minutes: int
    completion_percent: float
    last_completed_at: Optional[datetime] = None


class RehabMyProgramResponse(BaseModel):
    program: RehabProgramResponse
    progress: RehabProgressResponse
    today_session: Optional[RehabSessionResponse] = None
