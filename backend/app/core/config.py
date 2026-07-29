import os
from pydantic_settings import BaseSettings
from pydantic import model_validator


class Settings(BaseSettings):
    PROJECT_NAME: str = "APX PRO API"
    API_V1_STR: str = "/api/v1"

    # Deployment environment: "development" | "production". In production the
    # interactive API docs (/docs, /redoc, /openapi.json) are disabled and HSTS
    # is emitted. Set ENVIRONMENT=production in the server .env.
    ENVIRONMENT: str = "development"

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.strip().lower() == "production"

    # JWT — SECRET_KEY MUST be set in .env; no hardcoded fallback
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Database
    DATABASE_URL: str = (
        "mssql+pyodbc://localhost/apx_pro"
        "?driver=ODBC+Driver+17+for+SQL+Server&trusted_connection=yes"
    )

    # CORS — comma-separated list of allowed origins
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://localhost:8080"

    # CloudFront CDN — prefix prepended to legacy Exercise.video_url values in
    # the /programs module. (The S3 upload/storage code was removed; storage is
    # Google Drive now. This CDN prefix is retained only for existing program
    # video URLs.)
    CLOUDFRONT_DOMAIN: str = ""

    # Razorpay
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""

    # Google Drive (Medical Records storage) — OAuth 2.0 user credentials.
    # Files are stored in the configured Google account's own Drive.
    # Generate the three values with: python get_gdrive_token.py
    GDRIVE_OAUTH_CLIENT_ID: str = ""
    GDRIVE_OAUTH_CLIENT_SECRET: str = ""
    GDRIVE_OAUTH_REFRESH_TOKEN: str = ""
    GDRIVE_ROOT_FOLDER_ID: str = ""            # optional: pin root to an existing Drive folder
    GDRIVE_ROOT_FOLDER_NAME: str = "MedicalRecords"
    MEDICAL_RECORD_MAX_FILE_SIZE_MB: int = 20

    # Firebase Authentication (phone sign-in) — ID tokens from the Flutter app
    # are verified against this project's public certs. No service account
    # credentials are required for token verification.
    FIREBASE_PROJECT_ID: str = ""

    # Firebase Cloud Messaging
    FIREBASE_CREDENTIALS_PATH: str = ""

    # SMTP Email — use Gmail App Password (not your regular password)
    # Generate at: myaccount.google.com → Security → App Passwords
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""

    # Appointments — clinic address shown in confirmation emails for PHYSICAL
    # visits (override in .env with the real address).
    CLINIC_ADDRESS: str = "APX PRO Clinic — please contact us for the visit address."

    # Notes Module
    DEVELOPMENT_MODE: bool = False
    NOTES_PRICE: int = 100  # Amount in paise (Rs. 100)
    STUDY_MATERIAL_MAX_FILE_SIZE_MB: int = 250

    # Rehabilitation Module — uploaded exercise videos (stored in Google Drive)
    REHAB_VIDEO_MAX_FILE_SIZE_MB: int = 500

    # Hard cap on request body size (backstop against memory/disk abuse from
    # oversized uploads). Must exceed the largest legitimate upload (rehab video
    # + multipart overhead). Per-endpoint limits are still enforced separately.
    MAX_REQUEST_BODY_MB: int = 600

    @model_validator(mode="after")
    def _guard_dev_mode_in_production(self):
        # DEVELOPMENT_MODE auto-grants paid Notes access with no payment. It must
        # never be on in production, so fail fast at startup rather than silently
        # giving every user free premium access.
        if self.is_production and self.DEVELOPMENT_MODE:
            raise ValueError(
                "DEVELOPMENT_MODE=True is not allowed when ENVIRONMENT=production "
                "(it bypasses payment for Notes). Set DEVELOPMENT_MODE=False."
            )
        return self

    class Config:
        case_sensitive = True
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
