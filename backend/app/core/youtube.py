"""
YouTube URL parsing for the Help Center.

The Help Center stores only a YouTube URL and its extracted 11-character video
id — never video files. This module is the single place that validates a URL
and pulls out the id, so the rule lives in exactly one spot and is unit-tested
independently of the web layer.

Supported forms (with or without scheme, http/https, optional query params):
    https://www.youtube.com/watch?v=VIDEOID
    https://youtube.com/watch?v=VIDEOID&t=30s
    https://youtu.be/VIDEOID
    https://www.youtube.com/embed/VIDEOID
    https://www.youtube.com/shorts/VIDEOID
    https://m.youtube.com/watch?v=VIDEOID

Anything else (other hosts, missing id, malformed id) returns None so the
caller can reject it with a clear validation error.
"""
import re
from typing import Optional
from urllib.parse import parse_qs, urlparse

# A YouTube video id is exactly 11 chars from [A-Za-z0-9_-].
_VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")

# Hosts we accept (normalised to lowercase, leading "www."/"m." stripped).
_YOUTUBE_HOSTS = {"youtube.com", "youtu.be"}

# Path prefixes on youtube.com that carry the id as the first path segment.
_PATH_ID_PREFIXES = ("embed", "shorts", "v", "live")


def _normalise_host(host: str) -> str:
    host = (host or "").lower()
    for prefix in ("www.", "m."):
        if host.startswith(prefix):
            host = host[len(prefix):]
    return host


def extract_youtube_id(url: str) -> Optional[str]:
    """Return the 11-char video id from a YouTube URL, or None if the URL is not
    a recognisable/valid YouTube video link."""
    if not url or not isinstance(url, str):
        return None

    raw = url.strip()
    if not raw:
        return None

    # Allow scheme-less input like "youtu.be/VIDEOID" by defaulting to https.
    if "://" not in raw:
        raw = "https://" + raw

    try:
        parsed = urlparse(raw)
    except ValueError:
        return None

    host = _normalise_host(parsed.hostname or "")
    if host not in _YOUTUBE_HOSTS:
        return None

    candidate: Optional[str] = None

    if host == "youtu.be":
        # https://youtu.be/VIDEOID
        candidate = parsed.path.lstrip("/").split("/", 1)[0]
    else:
        # youtube.com
        if parsed.path in ("", "/", "/watch"):
            # https://youtube.com/watch?v=VIDEOID
            qs = parse_qs(parsed.query)
            values = qs.get("v")
            if values:
                candidate = values[0]
        else:
            segments = [s for s in parsed.path.split("/") if s]
            if segments and segments[0] in _PATH_ID_PREFIXES and len(segments) >= 2:
                # /embed/VIDEOID, /shorts/VIDEOID, /v/VIDEOID, /live/VIDEOID
                candidate = segments[1]

    if candidate and _VIDEO_ID_RE.match(candidate):
        return candidate
    return None


def is_valid_youtube_url(url: str) -> bool:
    """True if `url` is a recognisable YouTube video link we can extract an id from."""
    return extract_youtube_id(url) is not None
