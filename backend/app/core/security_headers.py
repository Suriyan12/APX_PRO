"""
Security response headers.

Adds baseline hardening headers to every response. These are cheap defence-in-
depth measures appropriate for an API that serves a mobile app and (in dev) a
web client:

  * X-Content-Type-Options: nosniff  — stop MIME sniffing of responses.
  * X-Frame-Options: DENY            — the API is never meant to be framed.
  * Referrer-Policy: no-referrer     — never leak URLs to third parties.
  * Strict-Transport-Security        — force HTTPS (production only; harmless
                                        over http where browsers ignore it, but
                                        we still gate it to avoid confusing
                                        local/LAN cleartext development).
"""
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.core.config import settings


class MaxBodySizeMiddleware(BaseHTTPMiddleware):
    """Reject requests whose declared Content-Length exceeds a hard cap, before
    the body is read — a backstop against oversized-upload memory/disk abuse so
    the app is safe even without a reverse proxy enforcing limits."""

    def __init__(self, app, max_bytes: int):
        super().__init__(app)
        self._max_bytes = max_bytes

    async def dispatch(self, request: Request, call_next):
        cl = request.headers.get("content-length")
        if cl and cl.isdigit() and int(cl) > self._max_bytes:
            return JSONResponse(
                status_code=413, content={"detail": "Request body too large."}
            )
        return await call_next(request)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        if settings.is_production:
            response.headers.setdefault(
                "Strict-Transport-Security",
                "max-age=31536000; includeSubDomains",
            )
        return response
