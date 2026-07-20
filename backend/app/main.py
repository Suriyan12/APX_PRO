import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
from app.api.v1 import (
    auth,
    appointments,
    reports,
    posture,
    programs,
    progress,
    notes,
    users,
    rehab,
    medical_records,
)

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="APX PRO API - Backend engine for Fitness, Physiotherapy, and Posture scans",
    version="1.0.0",
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

# CORS — set ALLOWED_ORIGINS in .env for production (comma-separated)
allowed_origins = [o.strip() for o in settings.ALLOWED_ORIGINS.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include all feature modular routers
app.include_router(auth.router, prefix=f"{settings.API_V1_STR}/auth", tags=["Authentication"])
app.include_router(appointments.router, prefix=f"{settings.API_V1_STR}/appointments", tags=["Consultation & Booking"])
app.include_router(reports.router, prefix=f"{settings.API_V1_STR}/reports", tags=["Medical Reports"])
app.include_router(posture.router, prefix=f"{settings.API_V1_STR}/scans", tags=["Posture Scan (APX Scan)"])
app.include_router(programs.router, prefix=f"{settings.API_V1_STR}/programs", tags=["Rehabilitation Programs"])
app.include_router(progress.router, prefix=f"{settings.API_V1_STR}/progress", tags=["Progress Logs"])
app.include_router(notes.router, prefix=f"{settings.API_V1_STR}/notes", tags=["Premium Notes"])
app.include_router(users.router, prefix=f"{settings.API_V1_STR}/users", tags=["User Management (Admin)"])
app.include_router(rehab.router, prefix=f"{settings.API_V1_STR}/rehab", tags=["Rehabilitation Programs"])
app.include_router(medical_records.router, prefix=f"{settings.API_V1_STR}/medical-records", tags=["Medical Records (Google Drive)"])


# NOTE: the public /media static mount was removed. Rehab videos now live in
# Google Drive and stream through the authenticated /api/v1/rehab/videos/{id}
# endpoint — serving patient videos from an unauthenticated static mount was a
# security hole.


@app.get("/")
def read_root():
    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "version": "1.0.0"
    }
