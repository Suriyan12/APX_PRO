# APX PRO — Production Readiness Checklist

_Living document. Updated after each remediation item._

**Current production readiness: 95%**

---

## ✅ Completed

### Ship-blockers
- **C4 — Legacy S3 code removed.** `/reports` & `/scans` (posture) routers/modules, `AWS_*`, `boto3` deleted. Drive-only storage.
- **C2 — CORS fixed.** `ALLOWED_ORIGINS` applied.
- **C3 — Rate limiting + reset-OTP lockout.** `slowapi` on all auth routes; `password_reset_tokens.attempts` 5-try lockout (migration 013).
- **Flutter scan UI removed.** Screens, nav, onboarding slide, stale test deleted.

### MEDIUM
- **M1 — App hardening.** Global exception handler, security headers, docs/OpenAPI off in prod, request body-size cap (`MAX_REQUEST_BODY_MB`).
- **M2 — Dependency pinning.**
- **M3 — DB pooling + indexes** (migration 015) + stale-comment fix.
- **M4 — Streaming uploads.** Notes **and** medical records now stream to Drive (bounded memory); rehab already did.
- **M5 — `DEVELOPMENT_MODE` prod guard.**
- **M6 — Password policy** (8–72 + letter & digit).
- **M7 — Data integrity.** Discount rollback; unique payment-id index (migration 014).
- **M8 — Test coverage.** 55 → 77 tests incl. PHI IDOR, payment gate, user-deletion transaction.

### LOW / hardening
- **Refresh-token hygiene** — expired tokens purged per user on issue.
- **Admin action audit log** — `apx.admin.audit` on user create/delete/status-toggle, note delete, notes grant/revoke.
- **User-deletion robustness** — orphan `subscriptions` cleanup guarded on table existence (no longer aborts the delete).
- **Semantics** — inactive user → 403 (was 400); corrected stale `Appointment.status` comment.
- **Flutter transport security (client side of C1).** Release builds forbid cleartext entirely; dev cleartext moved to a debug-only network config. Base URL is HTTPS-ready via `--dart-define=API_BASE_URL`. **Release APK builds verified** with an https define.
- **Flutter dead code removed** — unused `_programError` field.

## 🔜 Remaining (non-blocking / optional)

- **Async Drive offload** — Drive I/O runs inline in async endpoints (consistent across notes/rehab/medical-records). An optimization, not a correctness issue; convert to threadpool for higher throughput.
- **`onReorder` deprecation** — `admin_program_detail.dart:195` uses a deprecated callback (still functional). Migrate to `onReorderItem` when convenient (needs index-math care).
- **Soft-delete + retention** — hard deletes are intentional today; a soft-delete/retention policy is a product/compliance decision, not a code defect.

## ⛔ Blocked (owner input required)

- **C1 — Production domain + TLS cert + certificate pinning.** The client is now production-safe by default (HTTPS-only in release), but needs: (1) the real HTTPS API domain passed as `API_BASE_URL` at build, (2) TLS termination in front of the backend, (3) the server cert/public-key to implement pinning. All three require the deployment domain.

---

## Manual steps required before/at deploy

1. **Apply migrations** (idempotent): `013_password_reset_attempts.sql`, `014_notes_purchase_payment_unique.sql`, `015_appointment_indexes.sql`.
2. **Set `ENVIRONMENT=production`** in the backend `.env` (disables docs, enables HSTS + dev-mode guard).
3. **`pip install -r requirements.txt`** in the deploy env; confirm `google-api-python-client` resolves.
4. Run uvicorn with `--proxy-headers` (correct client IPs for rate limiting).
5. **Build the app with the production API:** `flutter build apk --release --dart-define=API_BASE_URL=https://<your-domain>/api/v1`.

## Change log

- Ship-blockers (C2/C3/C4) + Flutter scan removal.
- MEDIUM M1–M8 + LOW/hardening items implemented.
- 77 backend tests green; Flutter tests green; release APK builds with HTTPS-only network policy.
