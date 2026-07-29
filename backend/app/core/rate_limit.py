"""
Shared rate limiter for the API.

Uses slowapi (a Starlette/FastAPI wrapper over the `limits` library). The
limiter is created once here and attached to the app in main.py so route
modules can import the same instance and decorate sensitive endpoints.

Key function: the client's remote address. IMPORTANT — behind a reverse proxy
(nginx / ALB / Cloudflare) the direct peer is the proxy, so every client would
share one bucket. Set the proxy to forward the real client IP and ensure the
ASGI server is run with `--proxy-headers` (uvicorn) so `get_remote_address`
resolves `X-Forwarded-For` correctly.
"""
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
