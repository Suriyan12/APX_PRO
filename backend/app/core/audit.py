"""
Admin action audit trail.

Append-only structured log of privileged/destructive admin actions (user
delete, status toggle, note delete, access grant, …). Records only actor id,
action, and opaque target ids — never names or content — so the log itself
carries no PII. Route this logger to a durable/append-only sink in production
for compliance and forensics.

Mirrors the PHI audit logger in the medical-records module.
"""
import logging

audit_logger = logging.getLogger("apx.admin.audit")


def audit_admin(action: str, *, actor, target_id=None, detail: str = "") -> None:
    audit_logger.info(
        "ADMIN_ACTION action=%s actor=%s target=%s %s",
        action,
        getattr(actor, "id", actor),
        target_id if target_id is not None else "-",
        detail,
    )
