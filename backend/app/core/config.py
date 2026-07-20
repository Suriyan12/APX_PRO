import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    PROJECT_NAME: str = "APX PRO API"
    API_V1_STR: str = "/api/v1"

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

    # AWS Storage (S3 + CloudFront)
    AWS_ACCESS_KEY_ID: str = ""
    AWS_SECRET_ACCESS_KEY: str = ""
    AWS_REGION: str = "ap-south-1"
    AWS_S3_BUCKET: str = "apx-pro-storage"
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

    class Config:
        case_sensitive = True
        env_file = ".env"
        env_file_encoding = "utf-8"


settings = Settings()
