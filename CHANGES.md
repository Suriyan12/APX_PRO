# APX PRO — Change Log & Session Notes

> **Purpose**: This file tracks every significant change made to the codebase.  
> Start a new session by saying: _"Read CHANGES.md and continue from where we left off."_  
> After each session, append new changes to the bottom under a dated section.

---

## Stack Reference

| Layer | Technology |
|---|---|
| Frontend | Flutter (Web + Android), Riverpod, GoRouter, Dio |
| Backend | FastAPI, SQLAlchemy, PostgreSQL, Pydantic v2 |
| Storage | AWS S3 (presigned URLs for upload/download) |
| Auth | JWT (access + refresh tokens), FlutterSecureStorage |
| Video | `chewie` + `video_player` packages |
| PDF | `pdfrx` package |

---

## Engineering Standards (always apply)

- Never hardcode secrets — use env vars
- Hash passwords with bcrypt before storing
- Always verify JWTs server-side
- Users must NOT get direct S3 URLs — serve presigned GET URLs only (1hr expiry)
- Public `/register` endpoint always forces `role = UserRole.PATIENT` regardless of request body
- Admin creation only via `backend/create_admin.py` server-side script

---

## Session 1 — Core Build + Admin Panel + Glass UI

### 1. Network Layer

**File**: `lib/core/network/auth_interceptor.dart`
- Platform-aware base URL:
  ```dart
  static final String baseUrl = kIsWeb
      ? 'http://localhost:8000/api/v1'
      : 'http://10.0.2.2:8000/api/v1';
  ```
- Fixes Android emulator connection timeout (emulator cannot reach `localhost`, must use `10.0.2.2`)

**File**: `lib/core/network/api_client.dart`
- Added `patch()` method (was missing — needed for `PATCH /users/{id}/status`)

---

### 2. Auth Controller Fix

**File**: `lib/features/auth/presentation/controllers/auth_controller.dart`
- Fixed `isAdmin` getter — was `== 'ADMIN'` (broken)
- Pydantic v2 serializes `str` enums by VALUE (lowercase), so `UserRole.ADMIN` → `"admin"`
- Fix: `userRole?.toLowerCase() == 'admin'`
- Stores `user_role` and `user_email` in FlutterSecureStorage on login

---

### 3. Upload URL Method Fix (405 Error)

**File**: `lib/features/assessment/presentation/assessment_screen.dart`  
**File**: `lib/features/scan/presentation/scan_tab.dart`
- Both were calling `_apiClient.get('/reports/upload-url')` and `_apiClient.get('/scans/upload-url')`
- Backend expects `POST`, not `GET` → was returning 405 Method Not Allowed
- Fixed both to use `.post(...)`

---

### 4. Backend — New Endpoints

**File**: `backend/app/api/v1/users.py`
```
POST   /users/          — admin create user (any role)
DELETE /users/{id}      — permanent delete with cascade
PATCH  /users/{id}/status — toggle is_active
```

**File**: `backend/app/api/v1/auth.py`
- Security fix: register endpoint now forces `role = UserRole.PATIENT` regardless of client input

**File**: `backend/app/schemas/schemas.py`
- Added `AdminCreateUserRequest` (full_name, email, phone, password, role)
- Added `PatientSummary` (id, full_name, email, phone)
- Added `patient: Optional[PatientSummary]` to `PostureScanResponse`

**File**: `backend/create_admin.py` *(new)*
- Run: `python create_admin.py` from `backend/` directory
- Creates admin: `admin@apxpro.com` / `Admin@123456`

---

### 5. Glass Design System

**File**: `lib/core/theme/glass.dart` *(new)*

Core widgets — use these everywhere, do NOT create custom glass manually:

| Widget | Purpose |
|---|---|
| `GlassCard` | Universal glass card with blur + tint + specular border |
| `GlassOrbBackground` | 3-orb radial gradient background (cyan, purple, pink) — wrap every Scaffold body |
| `GlassBottomNav` | Floating pill bottom nav with animated selected state |
| `GlassAppBar` | Blurred app bar, implements `PreferredSizeWidget` |
| `showGlassDialog<T>()` | Glass-styled dialog helper |

**Key design tokens:**
- Background: `#0A0B10`
- Primary (cyan): `#00F2FE`
- Secondary (violet): `#8A2BE2`
- Accent (pink): `#FF2A54`
- Success: `#00E676`
- Warning: `#FFD600`
- Glass tint: `Color(0x12FFFFFF)` (7% white)
- Specular top border: `Color(0x40FFFFFF)`

**Scaffold pattern** (required for glass to work):
```dart
Scaffold(
  backgroundColor: AppColors.background,
  extendBody: true,
  extendBodyBehindAppBar: true,
  appBar: GlassAppBar(...),
  body: GlassOrbBackground(child: SafeArea(child: ...)),
)
```

---

### 6. Full App Glass Rewrite — All 25 Screens

All screens rewritten with glass theme. Key screens:

| Screen | File |
|---|---|
| Dashboard | `lib/features/dashboard/presentation/dashboard_screen.dart` |
| Home Tab | `lib/features/dashboard/presentation/home_tab.dart` |
| Admin Panel | `lib/features/admin/presentation/admin_panel_screen.dart` |
| Admin Users | `lib/features/admin/presentation/admin_users_screen.dart` |
| Admin Scans | `lib/features/admin/presentation/admin_scans_screen.dart` |
| Scan Review | `lib/features/admin/presentation/admin_scan_review_screen.dart` |
| User Detail | `lib/features/admin/presentation/admin_user_detail_screen.dart` |
| Progress | `lib/features/progress/presentation/progress_screen.dart` |
| Assessment | `lib/features/assessment/presentation/assessment_screen.dart` |
| Scan Tab | `lib/features/scan/presentation/scan_tab.dart` |
| Consultation | `lib/features/consultation/presentation/consultation_tab.dart` |
| Auth screens | `login_screen`, `register_screen`, `otp_screen`, `forgot_password_screen`, `onboarding_screen` |
| Notes screens | `notes_home_screen`, `note_viewer_screen`, `notes_purchase_screen` |
| Admin notes | `admin_notes_screen`, `upload_note_screen`, `edit_note_screen` |
| Other | `subscription_screen`, `programs_tab` |

**Admin panel special pattern:**
```dart
// GlobalKey to call showAddUserSheet() from parent FAB
final _usersKey = GlobalKey<AdminUsersScreenState>();
// AdminUsersScreen state class is PUBLIC (not _private) for key access
```

---

### 7. Flutter Web — BackdropFilter Rendering Bug Fix

**Bug**: On Flutter Web HTML renderer, `BackdropFilter` creates a compositing layer that renders the blur OVER its children — making all icons, text, and widgets inside the card invisible.

**Affected**: ALL 22 files using `BackdropFilter`

**Fix pattern** (applied to every occurrence):
```dart
// BEFORE (broken on web — content invisible)
ClipRRect(
  borderRadius: BorderRadius.circular(N),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: X, sigmaY: Y),
    child: Container(decoration: ..., child: CONTENT),
  ),
)

// AFTER (correct — content visible above blur layer)
ClipRRect(
  borderRadius: BorderRadius.circular(N),
  child: Stack(
    children: [
      Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: X, sigmaY: Y),
          child: Container(decoration: ...), // NO child content here
        ),
      ),
      Padding(padding: ..., child: CONTENT), // content renders above blur
    ],
  ),
)
```

**Files fixed:**
- `lib/core/theme/glass.dart` — GlassCard, showGlassDialog, GlassAppBar
- `login_screen.dart` — 5 patterns (email/password fields, buttons)
- `register_screen.dart` — 2 patterns
- `otp_screen.dart` — 2 patterns
- `forgot_password_screen.dart` — 4 patterns
- `onboarding_screen.dart` — 1 pattern
- `progress_screen.dart` — 2 patterns
- `assessment_screen.dart` — 2 patterns
- `scan_tab.dart` — 1 pattern
- `admin_scan_review_screen.dart` — 3 patterns (Retry, feedback field, Submit)
- `admin_users_screen.dart` — 5 patterns (search, form fields, buttons)
- `admin_panel_screen.dart` — 2 patterns (tab bar, FAB)
- `admin_user_detail_screen.dart` — 2 patterns
- `consultation_tab.dart` — 4 patterns
- `subscription_screen.dart` — 3 patterns
- `programs_tab.dart` — 2 patterns
- `notes_home_screen.dart` — 5 patterns
- `note_viewer_screen.dart` — 3 patterns
- `notes_purchase_screen.dart` — 1 pattern
- `admin_notes_screen.dart` — 4 patterns
- `upload_note_screen.dart` — 3 patterns
- `edit_note_screen.dart` — 5 patterns

---

### 8. Appointment Visibility Fix

**Symptoms**: Booking succeeded (201 + success snackbar) but appointment not visible in "My Appointments".

**Root causes found and fixed:**

**Bug A — Backend Decimal serialization** (`backend/app/schemas/schemas.py`)
- `consultation_fee`, `discount_amount`, `final_amount` columns are `Numeric(10,2)` → SQLAlchemy returns Python `Decimal`
- Pydantic v2 `Optional[float]` field + `Decimal` value caused serialization failure → 500 error from `GET /appointments/my`
- Fix: Added `model_validate` override in `AppointmentResponse` to coerce `Decimal → float` before validation
- Also migrated from old `class Config:` to `model_config = {"from_attributes": True}`

**Bug B — Silent error swallowing** (`lib/features/consultation/presentation/consultation_tab.dart`)
- `catch (_)` discarded the actual exception with no feedback
- Fix: Changed to typed `on ApiException catch (e)` + general `catch (e)`, sets `_appointmentError` state

**Bug C — Default filter excluded new bookings**
- Default `_filter = 'upcoming'` uses `start.isAfter(DateTime.now())` — timezone edge cases could exclude slots
- Fix: Changed default to `_filter = 'all'`; switches to `'all'` after every successful booking

**Bug D — UX: section not in view**
- "My Appointments" section is far below the booking form; users didn't know to scroll
- Fix: Added `ScrollController`, auto-scrolls to bottom 300ms after booking success

**Fix: Error state UI**
- Shows error message + Retry button in appointments section instead of silent empty state

---

## Known Remaining Items / Future Work

- [ ] Payment integration (Razorpay) — subscription and notes purchase endpoints exist, UI stubs in place
- [ ] Posture scan video upload on mobile (camera recording) — web uses file picker only (`kIsWeb` guard)
- [ ] Admin appointment view — currently patients only see their own; admin sees by `admin_id` (may be null for unassigned)
- [ ] Push notifications for appointment reminders
- [ ] PDF viewer in note_viewer_screen uses `pdfrx` — `PdfViewerController` does NOT have `.dispose()` (extends `ValueListenable<Matrix4>`, not `ChangeNotifier`)

---

## How to Run

### Backend
```powershell
cd "D:\APX PRO\backend"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Flutter (web)
```powershell
cd "D:\APX PRO"
flutter run -d chrome
```

### Create admin user (first time only)
```powershell
cd "D:\APX PRO\backend"
python create_admin.py
# credentials: admin@apxpro.com / Admin@123456
```

### Clean rebuild (after large changes)
```powershell
cd "D:\APX PRO"
flutter clean && flutter pub get && flutter run -d chrome
```

---

## Session 2 — [Date: append new changes below]

> Add new session entries here with the date and a brief description of changes.
