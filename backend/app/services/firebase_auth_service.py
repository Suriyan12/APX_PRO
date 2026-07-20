"""
Firebase Authentication token verification.

The Flutter app performs phone-number sign-in entirely through the Firebase
Auth SDK (send OTP, verify OTP, resend, auto-verification). The backend never
generates, stores, or checks SMS codes — it only validates the *result*: a
Firebase ID token, whose signature is checked against Google's public certs
and whose audience must equal our Firebase project id.

No service-account credentials are needed for verification; `google-auth`
fetches Google's public keys over HTTPS and caches them.
"""
import logging

from fastapi import HTTPException, status
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app.core.config import settings

logger = logging.getLogger(__name__)

# Reused across calls so google-auth can cache Google's public certificates.
_transport = google_requests.Request()


def verify_firebase_token(token: str) -> dict:
    """Validate a Firebase ID token and return its claims.

    Raises:
        HTTPException 503 — Firebase is not configured on the server.
        HTTPException 401 — token is invalid, expired, or for another project.
        HTTPException 400 — token is valid but carries no verified phone number.
    """
    if not settings.FIREBASE_PROJECT_ID:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Phone sign-in is not configured on the server. "
                   "Set FIREBASE_PROJECT_ID in the backend .env.",
        )
    try:
        claims = google_id_token.verify_firebase_token(
            token, _transport, audience=settings.FIREBASE_PROJECT_ID
        )
    except ValueError:
        logger.warning("Firebase ID token failed verification")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired verification token. Please try again.",
        )
    if not claims:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired verification token. Please try again.",
        )
    if not claims.get("phone_number"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="This sign-in token does not contain a verified phone number.",
        )
    return claims
