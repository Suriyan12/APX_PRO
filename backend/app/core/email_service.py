import logging
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from app.core.config import settings

logger = logging.getLogger(__name__)


def send_email(to_email: str, subject: str, html_body: str) -> None:
    if not settings.SMTP_USER or not settings.SMTP_PASSWORD:
        logger.warning(
            "SMTP credentials not configured — falling back to console output. "
            "Set SMTP_USER and SMTP_PASSWORD in .env to send real emails."
        )
        logger.debug("[DEV EMAIL] To: %s | Subject: %s\n%s", to_email, subject, html_body)
        return

    logger.info("Sending email to %s | Subject: %s", to_email, subject)
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"APX PRO <{settings.SMTP_USER}>"
    msg["To"] = to_email
    msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
        server.sendmail(settings.SMTP_USER, to_email, msg.as_string())

    logger.info("Email delivered to %s", to_email)


def send_otp_email(to_email: str, otp: str) -> None:
    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;
                background:#0A0B10;padding:32px;border-radius:12px;">
      <h2 style="color:#00F2FE;margin:0 0 8px;">APX PRO</h2>
      <p style="color:#9098B1;font-size:15px;margin:0 0 24px;">
        Your password reset OTP:
      </p>
      <div style="text-align:center;padding:24px;background:#131520;
                  border-radius:10px;margin-bottom:24px;">
        <span style="font-size:40px;font-weight:bold;letter-spacing:14px;
                     color:#ffffff;">{otp}</span>
      </div>
      <p style="color:#9098B1;font-size:13px;margin:0 0 8px;">
        This OTP expires in <strong style="color:#ffffff;">10 minutes</strong>.
        Do not share it with anyone.
      </p>
      <p style="color:#4A5060;font-size:12px;margin:0;">
        If you didn't request this, you can safely ignore this email.
      </p>
    </div>
    """
    send_email(to_email, "APX PRO — Password Reset OTP", html)


# ---------------------------------------------------------------------------
# Appointment notification templates
#
# These are pure template/builder functions. They construct branded HTML and
# delegate delivery to send_email() above — no SMTP logic is duplicated here.
# The outer branded shell is shared by all three appointment emails so booking,
# reschedule and cancellation stay visually consistent.
# ---------------------------------------------------------------------------

def _appointment_shell(
    *,
    heading: str,
    heading_color: str,
    intro_html: str,
    rows_html: str,
    footer_html: str = "",
) -> str:
    return f"""
    <div style="font-family:Arial,sans-serif;max-width:540px;margin:auto;
                background:#ffffff;border-radius:12px;overflow:hidden;
                border:1px solid #e0e0e0;">
      <div style="background:#1a73e8;padding:24px 28px;">
        <h1 style="margin:0;color:#fff;font-size:22px;">APX PRO</h1>
        <p style="margin:4px 0 0;color:#c8e0ff;font-size:13px;">
          Physiotherapy &amp; Wellness
        </p>
      </div>
      <div style="padding:28px;">
        <h2 style="margin:0 0 6px;color:{heading_color};font-size:18px;">
          {heading}
        </h2>
        <p style="color:#444;margin:0 0 20px;">{intro_html}</p>
        <table style="width:100%;border-collapse:collapse;font-size:14px;
                      border:1px solid #e8e8e8;border-radius:8px;overflow:hidden;">
          {rows_html}
        </table>
        {footer_html}
      </div>
    </div>
    """


def _row(label: str, value: str, *, alt: bool, value_color: str = "#111",
         value_weight: str = "600") -> str:
    bg = "background:#f5f9ff;" if alt else ""
    return (
        f'<tr style="{bg}">'
        f'<td style="padding:10px 14px;color:#555;width:42%;">{label}</td>'
        f'<td style="padding:10px 14px;color:{value_color};'
        f'font-weight:{value_weight};">{value}</td>'
        f'</tr>'
    )


def send_appointment_booked_email(
    *, to_email: str, patient_name: str, date_str: str, time_str: str,
    consultation_type: str | None = None,
) -> None:
    """Booking acknowledgement. Appointments are now confirmed by an admin, so
    this email tells the patient their request was received and is pending."""
    type_label = _meeting_type_label(consultation_type)
    type_row = (
        '<tr style="background:#f5f9ff;">'
        '<td style="padding:10px 14px;color:#555;width:40%;">Type</td>'
        f'<td style="padding:10px 14px;color:#111;font-weight:600;">{type_label}</td>'
        '</tr>' if type_label else ''
    )
    rows = (
        type_row +
        '<tr>'
        '<td style="padding:10px 14px;color:#555;width:40%;">📅 Date</td>'
        f'<td style="padding:10px 14px;color:#111;font-weight:600;">{date_str}</td>'
        '</tr>'
        '<tr style="background:#f5f9ff;">'
        '<td style="padding:10px 14px;color:#555;">⏰ Time</td>'
        f'<td style="padding:10px 14px;color:#111;font-weight:600;">{time_str}</td>'
        '</tr>'
        '<tr>'
        '<td style="padding:10px 14px;color:#555;">💰 Fee</td>'
        '<td style="padding:10px 14px;color:#2e7d32;font-weight:700;">FREE</td>'
        '</tr>'
    )
    footer = (
        '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
        "We'll email you again as soon as our team confirms this appointment. "
        'For an online consultation, your meeting link will be included then.'
        '</p>'
    )
    html = _appointment_shell(
        heading="🗓️ Appointment Requested",
        heading_color="#1a73e8",
        intro_html=(
            f"Hi {patient_name}, we've received your appointment request. "
            "It's pending confirmation from our team."
        ),
        rows_html=rows,
        footer_html=footer,
    )
    send_email(to_email=to_email, subject="Appointment Requested — APX PRO", html_body=html)


def _meeting_type_label(consultation_type: str | None) -> str | None:
    if consultation_type == "online":
        return "💻 Online Consultation"
    if consultation_type == "physical":
        return "🏥 Physical Visit"
    return None


def _join_button(meeting_link: str) -> str:
    """A prominent Join-Consultation button for online consults."""
    return (
        f'<div style="text-align:center;margin:24px 0 4px;">'
        f'<a href="{meeting_link}" '
        f'style="display:inline-block;background:#1a73e8;color:#fff;'
        f'text-decoration:none;padding:12px 28px;border-radius:8px;'
        f'font-weight:600;font-size:15px;">🎥 Join Consultation</a>'
        f'</div>'
        f'<p style="text-align:center;margin:8px 0 0;font-size:12px;color:#888;">'
        f'The button becomes active in the app 15 minutes before your slot.</p>'
    )


def send_reschedule_requested_email(
    *,
    to_email: str,
    patient_name: str,
    old_date_str: str,
    old_time_str: str,
    new_date_str: str,
    new_time_str: str,
    therapist_name: str | None = None,
    appointment_id: str | None = None,
    consultation_type: str | None = None,
    meeting_link: str | None = None,  # accepted for signature stability; unused (link is cleared)
) -> None:
    """Acknowledge a PATIENT's reschedule request. The appointment is now back to
    PENDING and awaiting admin approval — this email must NOT claim the change is
    confirmed. A separate approval email follows once an admin approves."""
    rows = ""
    alt = True
    type_label = _meeting_type_label(consultation_type)
    if type_label:
        rows += _row("Type", type_label, alt=alt)
        alt = not alt
    if therapist_name:
        rows += _row("🩺 Therapist", therapist_name, alt=alt)
        alt = not alt
    rows += _row("📅 Previous", f"{old_date_str} · {old_time_str}", alt=alt,
                 value_color="#b00020")
    alt = not alt
    rows += _row("🕓 Requested", f"{new_date_str} · {new_time_str}", alt=alt,
                 value_color="#1a73e8")
    alt = not alt
    rows += _row("📌 Status", "Awaiting admin approval", alt=alt, value_color="#e67e00")
    alt = not alt
    if appointment_id:
        rows += _row("🔖 Appointment ID", appointment_id, alt=alt)
    footer = (
        '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
        'Your request has been sent to our team for approval — your appointment '
        'is <strong>not confirmed yet</strong>. '
        + ('For this online consultation, a new meeting link will be issued once '
           'it is approved. ' if consultation_type == "online" else '')
        + "We'll email you as soon as it's approved (or if we can't accommodate it)."
        '</p>'
    )
    html = _appointment_shell(
        heading="🔄 Reschedule Request Received",
        heading_color="#e67e00",
        intro_html=(
            f"Hi {patient_name}, we've received your request to move this "
            "appointment. It's now pending approval from our team:"
        ),
        rows_html=rows,
        footer_html=footer,
    )
    send_email(to_email=to_email, subject="Reschedule Requested — APX PRO", html_body=html)


def send_reschedule_admin_notification_email(
    *,
    to_email: str,
    admin_name: str | None,
    patient_name: str,
    old_date_str: str,
    old_time_str: str,
    new_date_str: str,
    new_time_str: str,
    consultation_type: str | None = None,
    appointment_id: str | None = None,
) -> None:
    """Notify an admin that a patient reschedule request is awaiting review."""
    rows = ""
    alt = True
    rows += _row("👤 Patient", patient_name, alt=alt)
    alt = not alt
    type_label = _meeting_type_label(consultation_type)
    if type_label:
        rows += _row("Type", type_label, alt=alt)
        alt = not alt
    rows += _row("📅 Previous", f"{old_date_str} · {old_time_str}", alt=alt,
                 value_color="#b00020")
    alt = not alt
    rows += _row("🕓 Requested", f"{new_date_str} · {new_time_str}", alt=alt,
                 value_color="#1a73e8")
    alt = not alt
    if appointment_id:
        rows += _row("🔖 Appointment ID", appointment_id, alt=alt)
    footer = (
        '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
        'Please review this request in the APX PRO Admin Panel → Appointments '
        '(Pending) and approve or reject it.</p>'
    )
    greeting = f"Hi {admin_name}, " if admin_name else "Hi, "
    html = _appointment_shell(
        heading="🔔 Reschedule Request Awaiting Review",
        heading_color="#e67e00",
        intro_html=(
            f"{greeting}a patient has requested to reschedule an appointment. "
            "It is now pending your approval:"
        ),
        rows_html=rows,
        footer_html=footer,
    )
    send_email(to_email=to_email, subject="Reschedule Request — Action Needed — APX PRO",
               html_body=html)


def send_appointment_cancelled_email(
    *,
    to_email: str,
    patient_name: str,
    date_str: str,
    time_str: str,
    therapist_name: str | None = None,
    reason: str | None = None,
    appointment_id: str | None = None,
) -> None:
    """Notify the patient that their appointment has been cancelled."""
    rows = ""
    alt = True
    if therapist_name:
        rows += _row("🩺 Therapist", therapist_name, alt=alt)
        alt = not alt
    rows += _row("📅 Cancelled Slot", f"{date_str} · {time_str}", alt=alt,
                 value_color="#b00020")
    alt = not alt
    if reason:
        rows += _row("📝 Reason", reason, alt=alt)
        alt = not alt
    if appointment_id:
        rows += _row("🔖 Appointment ID", appointment_id, alt=alt)
    footer = (
        '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
        'Changed your mind? You can book a new session anytime through the '
        'APX PRO app.'
        '</p>'
    )
    html = _appointment_shell(
        heading="✕ Appointment Cancelled",
        heading_color="#b00020",
        intro_html=(
            f"Hi {patient_name}, your appointment has been cancelled. "
            "The details of the cancelled session are below:"
        ),
        rows_html=rows,
        footer_html=footer,
    )
    send_email(to_email=to_email, subject="Appointment Cancelled — APX PRO", html_body=html)


def send_appointment_approved_email(
    *,
    to_email: str,
    patient_name: str,
    date_str: str,
    time_str: str,
    consultation_type: str | None = None,
    meeting_link: str | None = None,
    therapist_name: str | None = None,
    appointment_id: str | None = None,
    is_reschedule: bool = False,
    clinic_address: str | None = None,
) -> None:
    """Notify the patient that an admin approved their appointment. Online →
    includes the Google Meet link; Physical → includes the clinic address.
    When `is_reschedule` is set, the copy reflects a rescheduled-appointment
    approval instead of an initial booking approval."""
    rows = ""
    alt = True
    type_label = _meeting_type_label(consultation_type)
    if type_label:
        rows += _row("Type", type_label, alt=alt)
        alt = not alt
    if therapist_name:
        rows += _row("🩺 Therapist", therapist_name, alt=alt)
        alt = not alt
    rows += _row("📅 Date", date_str, alt=alt)
    alt = not alt
    rows += _row("⏰ Time", time_str, alt=alt)
    alt = not alt
    if consultation_type == "physical" and clinic_address:
        rows += _row("📍 Location", clinic_address, alt=alt)
        alt = not alt
    if appointment_id:
        rows += _row("🔖 Appointment ID", appointment_id, alt=alt)

    if consultation_type == "online" and meeting_link:
        footer = _join_button(meeting_link)
    elif consultation_type == "physical":
        addr = f" at {clinic_address}" if clinic_address else ""
        footer = (
            '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
            f'Please arrive 10 minutes early for your visit{addr}.</p>'
        )
    else:
        footer = (
            '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
            'Please arrive 10 minutes early for your visit.</p>'
        )

    if is_reschedule:
        heading = "✓ Rescheduled Appointment Approved"
        intro = (
            f"Hi {patient_name}, good news — your rescheduled appointment has "
            "been approved by our team. Updated details below:"
        )
        subject = "Rescheduled Appointment Approved — APX PRO"
    else:
        heading = "✓ Appointment Confirmed"
        intro = (
            f"Hi {patient_name}, good news — your appointment has been "
            "confirmed by our team. Details below:"
        )
        subject = "Appointment Confirmed — APX PRO"

    html = _appointment_shell(
        heading=heading,
        heading_color="#1a73e8",
        intro_html=intro,
        rows_html=rows,
        footer_html=footer,
    )
    send_email(to_email=to_email, subject=subject, html_body=html)


def send_appointment_rejected_email(
    *,
    to_email: str,
    patient_name: str,
    date_str: str,
    time_str: str,
    therapist_name: str | None = None,
    reason: str | None = None,
    appointment_id: str | None = None,
    consultation_type: str | None = None,
    is_reschedule: bool = False,
) -> None:
    """Notify the patient that their appointment request was not approved. When
    `is_reschedule` is set, the copy reflects a rejected RESCHEDULE request."""
    rows = ""
    alt = True
    type_label = _meeting_type_label(consultation_type)
    if type_label:
        rows += _row("Type", type_label, alt=alt)
        alt = not alt
    if therapist_name:
        rows += _row("🩺 Therapist", therapist_name, alt=alt)
        alt = not alt
    slot_label = "📅 Requested New Slot" if is_reschedule else "📅 Requested Slot"
    rows += _row(slot_label, f"{date_str} · {time_str}", alt=alt, value_color="#b00020")
    alt = not alt
    if reason:
        rows += _row("📝 Reason", reason, alt=alt)
        alt = not alt
    if appointment_id:
        rows += _row("🔖 Appointment ID", appointment_id, alt=alt)

    if is_reschedule:
        heading = "Reschedule Request Not Approved"
        intro = (
            f"Hi {patient_name}, unfortunately your request to reschedule this "
            "appointment could not be approved. Details below:"
        )
        subject = "Reschedule Request Update — APX PRO"
        footer = (
            '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
            'Your appointment was not moved. You can submit a different time '
            'through the APX PRO app, or contact us for help.</p>'
        )
    else:
        heading = "Appointment Not Confirmed"
        intro = (
            f"Hi {patient_name}, unfortunately your appointment request could "
            "not be confirmed. Details below:"
        )
        subject = "Appointment Update — APX PRO"
        footer = (
            '<p style="margin:20px 0 0;font-size:13px;color:#888;">'
            'You can book a different slot anytime through the APX PRO app.</p>'
        )

    html = _appointment_shell(
        heading=heading,
        heading_color="#b00020",
        intro_html=intro,
        rows_html=rows,
        footer_html=footer,
    )
    send_email(to_email=to_email, subject=subject, html_body=html)


def send_verification_email(to_email: str, otp: str) -> None:
    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;
                background:#0A0B10;padding:32px;border-radius:12px;">
      <h2 style="color:#00F2FE;margin:0 0 8px;">APX PRO</h2>
      <p style="color:#9098B1;font-size:15px;margin:0 0 24px;">
        Welcome! Verify your email with this code to activate your account:
      </p>
      <div style="text-align:center;padding:24px;background:#131520;
                  border-radius:10px;margin-bottom:24px;">
        <span style="font-size:40px;font-weight:bold;letter-spacing:14px;
                     color:#ffffff;">{otp}</span>
      </div>
      <p style="color:#9098B1;font-size:13px;margin:0 0 8px;">
        This code expires in <strong style="color:#ffffff;">10 minutes</strong>.
        Do not share it with anyone.
      </p>
      <p style="color:#4A5060;font-size:12px;margin:0;">
        If you didn't create an APX PRO account, you can safely ignore this email.
      </p>
    </div>
    """
    send_email(to_email, "APX PRO — Verify Your Email", html)
