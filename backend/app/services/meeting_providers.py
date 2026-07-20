"""
Meeting-provider abstraction for online consultations.

The appointment workflow never hardcodes "Google Meet". It talks to a
`MeetingProvider` interface — validate a link, expose an id/label — so a new
platform (LiveKit, Agora, Zoom, Jitsi, …) can be added by registering one more
provider class here, with zero changes to the appointment service, schema,
routes, or the client contract.

Today only Google Meet is registered. To add another provider later:
    1. subclass MeetingProvider,
    2. implement `validate_link`,
    3. add an instance to _REGISTRY.
"""
from __future__ import annotations

import re
from abc import ABC, abstractmethod
from typing import Dict, List


class MeetingProviderError(ValueError):
    """Raised when a meeting link is invalid for the selected provider."""


class MeetingProvider(ABC):
    id: str            # opaque, stored in appointments.meeting_provider
    display_name: str

    @abstractmethod
    def validate_link(self, url: str) -> str:
        """Return a cleaned/normalized link, or raise MeetingProviderError."""
        raise NotImplementedError


class GoogleMeetProvider(MeetingProvider):
    id = "google_meet"
    display_name = "Google Meet"

    # A Google Meet meeting code is three-four-three lowercase letters,
    # e.g. abc-defg-hij.
    _BARE_CODE = re.compile(r"^[a-z]{3}-[a-z]{4}-[a-z]{3}$", re.I)
    # Full URL form (http/https, optional www, optional query/fragment).
    _URL = re.compile(
        r"^https?://(?:www\.)?meet\.google\.com/([a-z]{3}-[a-z]{4}-[a-z]{3})"
        r"(?:[/?#].*)?$",
        re.I,
    )
    # Enterprise "lookup" links.
    _LOOKUP = re.compile(
        r"^https?://(?:www\.)?meet\.google\.com/(lookup/[A-Za-z0-9_-]+)"
        r"(?:[/?#].*)?$",
        re.I,
    )

    def validate_link(self, url: str) -> str:
        """Accept either a full Meet URL or a bare meeting code, and normalize
        to a canonical `https://meet.google.com/<code>` — the ONLY form stored."""
        v = (url or "").strip()
        if self._BARE_CODE.match(v):
            return f"https://meet.google.com/{v.lower()}"
        m = self._URL.match(v)
        if m:
            return f"https://meet.google.com/{m.group(1).lower()}"
        m = self._LOOKUP.match(v)
        if m:
            return f"https://meet.google.com/{m.group(1)}"
        raise MeetingProviderError(
            "Enter a valid Google Meet link or code "
            "(e.g. https://meet.google.com/abc-defg-hij or abc-defg-hij)."
        )


# ── Registry ─────────────────────────────────────────────────────────────────
_REGISTRY: Dict[str, MeetingProvider] = {
    p.id: p for p in (GoogleMeetProvider(),)
}

DEFAULT_PROVIDER_ID = GoogleMeetProvider.id


def available_providers() -> List[dict]:
    return [{"id": p.id, "display_name": p.display_name} for p in _REGISTRY.values()]


def get_provider(provider_id: str) -> MeetingProvider:
    provider = _REGISTRY.get((provider_id or "").strip().lower())
    if not provider:
        raise MeetingProviderError(
            f"Unsupported meeting provider '{provider_id}'. "
            f"Supported: {', '.join(_REGISTRY)}."
        )
    return provider


def validate_meeting_link(provider_id: str, url: str) -> str:
    """Validate `url` for `provider_id`; returns the normalized link or raises
    MeetingProviderError."""
    return get_provider(provider_id).validate_link(url)
