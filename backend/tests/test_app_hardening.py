"""
Tests for M1 app-hardening: security headers on every response, and the
global exception handler returning a sanitized 500 (no traceback leakage).
"""
from fastapi.testclient import TestClient
from starlette.applications import Starlette
from starlette.responses import PlainTextResponse
from starlette.routing import Route

from app.core.security_headers import MaxBodySizeMiddleware
from app.main import app


def test_security_headers_present_on_public_response():
    with TestClient(app) as client:
        r = client.get("/")
    assert r.status_code == 200
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert r.headers.get("X-Frame-Options") == "DENY"
    assert r.headers.get("Referrer-Policy") == "no-referrer"


def test_unhandled_exception_is_sanitized():
    # Register a throwaway route that raises an unexpected error, then confirm
    # the global handler turns it into a generic 500 with no internals.
    @app.get("/_boom_test")
    def _boom():
        raise RuntimeError("secret internal detail")

    try:
        with TestClient(app, raise_server_exceptions=False) as client:
            r = client.get("/_boom_test")
        assert r.status_code == 500
        assert r.json() == {"detail": "Internal server error."}
        assert "secret internal detail" not in r.text
    finally:
        # Keep the app's route table clean for other tests.
        app.router.routes = [
            route for route in app.router.routes
            if getattr(route, "path", None) != "/_boom_test"
        ]


def test_oversized_request_body_rejected():
    async def _ok(request):
        return PlainTextResponse("ok")

    mini = Starlette(routes=[Route("/", _ok, methods=["POST"])])
    mini.add_middleware(MaxBodySizeMiddleware, max_bytes=10)
    with TestClient(mini) as client:
        too_big = client.post("/", content=b"x" * 50)
        assert too_big.status_code == 413
        ok = client.post("/", content=b"xx")
        assert ok.status_code == 200
