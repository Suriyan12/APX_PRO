import logging
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.core.config import settings
from app.core.rate_limit import limiter
from app.core.security_headers import MaxBodySizeMiddleware, SecurityHeadersMiddleware

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)
from app.api.v1 import (
    auth,
    appointments,
    programs,
    progress,
    notes,
    users,
    rehab,
    medical_records,
    notifications,
)

# Interactive docs + OpenAPI schema are disabled in production so the full
# medical API surface is not publicly enumerable. Enabled in development.
_docs_enabled = not settings.is_production
app = FastAPI(
    title=settings.PROJECT_NAME,
    description="APX PRO API - Backend engine for Fitness, Physiotherapy, and Rehabilitation",
    version="1.0.0",
    openapi_url=f"{settings.API_V1_STR}/openapi.json" if _docs_enabled else None,
    docs_url="/docs" if _docs_enabled else None,
    redoc_url="/redoc" if _docs_enabled else None,
)

# Rate limiting (slowapi). The limiter is attached to app.state so the
# decorators in the route modules resolve it; the middleware enforces limits
# and the handler turns a breach into a clean 429.
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

# Baseline security headers on every response.
app.add_middleware(SecurityHeadersMiddleware)

# Hard cap on request body size (backstop against oversized uploads).
app.add_middleware(
    MaxBodySizeMiddleware,
    max_bytes=settings.MAX_REQUEST_BODY_MB * 1024 * 1024,
)


# Global safety net: any unhandled exception is logged in full server-side but
# returned to the client as a generic 500 — never leaks tracebacks/internals.
# (FastAPI still handles HTTPException and validation errors with their own
# structured responses; this only catches the unexpected.)
@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error."})

# CORS — set ALLOWED_ORIGINS in .env for production (comma-separated). In
# development the localhost regex additionally allows any localhost port so the
# Flutter web dev server (whichever port it picks) works without config.
allowed_origins = [o.strip() for o in settings.ALLOWED_ORIGINS.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include all feature modular routers
app.include_router(auth.router, prefix=f"{settings.API_V1_STR}/auth", tags=["Authentication"])
app.include_router(appointments.router, prefix=f"{settings.API_V1_STR}/appointments", tags=["Consultation & Booking"])
app.include_router(programs.router, prefix=f"{settings.API_V1_STR}/programs", tags=["Rehabilitation Programs"])
app.include_router(progress.router, prefix=f"{settings.API_V1_STR}/progress", tags=["Progress Logs"])
app.include_router(notes.router, prefix=f"{settings.API_V1_STR}/notes", tags=["Premium Notes"])
app.include_router(users.router, prefix=f"{settings.API_V1_STR}/users", tags=["User Management (Admin)"])
app.include_router(rehab.router, prefix=f"{settings.API_V1_STR}/rehab", tags=["Rehabilitation Programs"])
app.include_router(medical_records.router, prefix=f"{settings.API_V1_STR}/medical-records", tags=["Medical Records (Google Drive)"])
app.include_router(notifications.router, prefix=f"{settings.API_V1_STR}/notifications", tags=["Notifications"])


# NOTE: the legacy S3-backed /reports and /scans (posture) modules were removed.
# All file storage now goes through Google Drive behind authenticated endpoints
# (rehab videos → /api/v1/rehab/videos/{id}, medical records → /api/v1/medical-records).
# Serving patient files via S3 presigned URLs was a security & consistency hole.


@app.get("/")
def read_root():
    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "version": "1.0.0"
    }
