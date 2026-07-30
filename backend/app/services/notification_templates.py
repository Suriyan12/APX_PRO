"""
Centralized notification copy.

Every user-facing notification title/body — and its deep-link payload — is
defined here, so wording stays consistent and reusable across producers and is
changed in exactly one place. Producers (e.g. the appointment adapter) call
these builders; they never inline notification text.

The `data` payload is the deep-link contract the Flutter client will route on.
Keys are stable strings; values are stringified by the FCM transport.
"""
from dataclasses import dataclass


# Notification `type` values (also used as the top-level category client-side).
TYPE_APPOINTMENT = "appointment"


@dataclass(frozen=True)
class NotificationContent:
    title: str
    body: str
    type: str
    data: dict


def _appointment_data(appointment_id, event: str) -> dict:
    """Deep-link payload for an appointment notification.

    `route` is a client-navigable path the app can push directly; `event`
    distinguishes what happened so the UI can tailor its handling.
    """
    aid = str(appointment_id)
    return {
        "type": TYPE_APPOINTMENT,
        "event": event,
        "appointment_id": aid,
        "route": f"/appointments/{aid}",
    }


# ── Appointment events ────────────────────────────────────────────────────────

def appointment_requested(patient_name: str, appointment_id, when_str: str) -> NotificationContent:
    """Sent to admins when a patient submits an appointment request."""
    return NotificationContent(
        title="New appointment request",
        body=f"{patient_name} requested an appointment for {when_str}.",
        type=TYPE_APPOINTMENT,
        data=_appointment_data(appointment_id, "requested"),
    )


def appointment_approved(appointment_id, when_str: str, is_online: bool) -> NotificationContent:
    """Sent to the patient when an admin approves their appointment."""
    where = "online (video)" if is_online else "in-person"
    return NotificationContent(
        title="Appointment approved",
        body=f"Your {where} appointment for {when_str} has been approved.",
        type=TYPE_APPOINTMENT,
        data=_appointment_data(appointment_id, "approved"),
    )


def appointment_rejected(appointment_id, when_str: str, reason: str | None = None) -> NotificationContent:
    """Sent to the patient when an admin rejects their appointment request."""
    body = f"Your appointment request for {when_str} was declined."
    if reason:
        body += f" Reason: {reason}"
    return NotificationContent(
        title="Appointment declined",
        body=body,
        type=TYPE_APPOINTMENT,
        data=_appointment_data(appointment_id, "rejected"),
    )
