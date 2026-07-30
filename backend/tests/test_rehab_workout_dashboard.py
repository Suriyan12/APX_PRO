"""
Tests for the admin rehabilitation workout dashboard:

  - patient completes a workout → admin progress/compliance/history update
  - compliance & progress are scoped to the ACTIVE program only
  - admins can VIEW progress but can never mark a workout complete
  - patients cannot reach the admin dashboard endpoints
  - workout history is paginated, newest first
  - admin appointment-history endpoint is admin-only

Runs on the shared SQLite TestClient from conftest.py.
"""
import uuid
import pytest

from tests.conftest import PATIENT_A_ID, PATIENT_B_ID, ADMIN_ID, _Session
from app.models.models import (
    RehabProgram, RehabExercise, RehabWorkoutSession, RehabExerciseCompletion,
)

REHAB = "/api/v1/rehab"


@pytest.fixture(autouse=True)
def _clean_rehab():
    """Isolate every test — no leftover programs/sessions between runs."""
    def _wipe():
        with _Session() as db:
            db.query(RehabExerciseCompletion).delete()
            db.query(RehabWorkoutSession).delete()
            db.query(RehabExercise).delete()
            db.query(RehabProgram).delete()
            db.commit()
    _wipe()
    yield
    _wipe()


# ── helpers ───────────────────────────────────────────────────────────────────

def _create_program(api, patient_id=PATIENT_A_ID, days=10, title="Knee Rehab"):
    api.as_user(ADMIN_ID)
    r = api.post(f"{REHAB}/programs", json={
        "patient_id": str(patient_id),
        "title": title,
        "estimated_duration_days": days,
    })
    assert r.status_code == 201, r.text
    return r.json()


def _add_exercise(api, program_id, name="Squat"):
    api.as_user(ADMIN_ID)
    r = api.post(f"{REHAB}/programs/{program_id}/exercises", json={
        "name": name, "sets": 3, "reps": 10, "exercise_type": "reps",
    })
    assert r.status_code == 201, r.text
    return r.json()


def _complete_one_session(api, program_id, exercise_id, patient_id=PATIENT_A_ID):
    api.as_user(patient_id)
    r = api.post(f"{REHAB}/sessions/start", json={"program_id": program_id})
    assert r.status_code == 201, r.text
    session = r.json()
    r = api.post(f"{REHAB}/sessions/{session['id']}/complete", json={
        "duration_seconds": 300,
        "exercises": [
            {"exercise_id": exercise_id, "sets_completed": 3, "is_skipped": False},
        ],
    })
    assert r.status_code == 200, r.text
    return r.json()


# ── tests ───────────────────────────────────────────────────────────────────

def test_completion_updates_admin_progress_and_history(api):
    program = _create_program(api, days=10)
    exercise = _add_exercise(api, program["id"])

    # Before any workout: admin sees an active program, nothing completed.
    api.as_user(ADMIN_ID)
    r = api.get(f"{REHAB}/patients/{PATIENT_A_ID}/progress")
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["has_active_program"] is True
    assert d["completed_sessions"] == 0
    assert d["assigned_sessions"] == 10
    assert d["remaining_sessions"] == 10
    assert d["today_status"] == "not_started"
    assert d["last_completed_at"] is None

    # Patient completes today's workout.
    _complete_one_session(api, program["id"], exercise["id"])

    # Admin IMMEDIATELY sees the completion reflected.
    api.as_user(ADMIN_ID)
    d = api.get(f"{REHAB}/patients/{PATIENT_A_ID}/progress").json()
    assert d["completed_sessions"] == 1
    assert d["remaining_sessions"] == 9
    assert d["today_status"] == "completed"
    assert d["last_completed_at"] is not None
    assert d["overall_progress_percent"] == 10.0     # 1/10
    assert d["compliance_percent"] == 100.0           # 1 of 1 expected today

    # History reflects it, newest first.
    hist = api.get(f"{REHAB}/patients/{PATIENT_A_ID}/sessions").json()
    assert hist["total"] == 1
    assert len(hist["items"]) == 1
    item = hist["items"][0]
    assert item["status"] == "completed"
    assert item["program_title"] == "Knee Rehab"
    assert item["exercises_completed"] == 1


def test_progress_is_scoped_to_active_program_only(api):
    # Program A: complete one session while it is active.
    prog_a = _create_program(api, days=10, title="Program A")
    ex_a = _add_exercise(api, prog_a["id"])
    _complete_one_session(api, prog_a["id"], ex_a["id"])

    api.as_user(ADMIN_ID)
    d = api.get(f"{REHAB}/patients/{PATIENT_A_ID}/progress").json()
    assert d["completed_sessions"] == 1
    assert d["assigned_sessions"] == 10

    # Creating Program B deactivates A. The dashboard must now report B's OWN
    # (independent) progress — zero — not A's history.
    prog_b = _create_program(api, days=20, title="Program B")
    _add_exercise(api, prog_b["id"])

    api.as_user(ADMIN_ID)
    d = api.get(f"{REHAB}/patients/{PATIENT_A_ID}/progress").json()
    assert d["has_active_program"] is True
    assert d["program_id"] == prog_b["id"]
    assert d["assigned_sessions"] == 20
    assert d["completed_sessions"] == 0
    assert d["today_status"] == "not_started"


def test_admin_cannot_mark_a_workout_complete(api):
    program = _create_program(api)
    exercise = _add_exercise(api, program["id"])

    # Patient starts the session.
    api.as_user(PATIENT_A_ID)
    session = api.post(f"{REHAB}/sessions/start", json={"program_id": program["id"]}).json()

    # Admin attempts to complete the patient's session → forbidden (ownership).
    api.as_user(ADMIN_ID)
    r = api.post(f"{REHAB}/sessions/{session['id']}/complete", json={
        "duration_seconds": 120,
        "exercises": [{"exercise_id": exercise["id"], "sets_completed": 3, "is_skipped": False}],
    })
    assert r.status_code == 403


def test_patient_cannot_access_admin_dashboard(api):
    program = _create_program(api)
    _add_exercise(api, program["id"])

    api.as_user(PATIENT_A_ID)
    assert api.get(f"{REHAB}/patients/{PATIENT_A_ID}/progress").status_code == 403
    assert api.get(f"{REHAB}/patients/{PATIENT_A_ID}/sessions").status_code == 403


def test_no_active_program_returns_empty_dashboard(api):
    api.as_user(ADMIN_ID)
    d = api.get(f"{REHAB}/patients/{PATIENT_B_ID}/progress").json()
    assert d["has_active_program"] is False
    assert d["completed_sessions"] == 0
    assert d["today_status"] == "not_started"


def test_history_pagination(api):
    program = _create_program(api)
    exercise = _add_exercise(api, program["id"])
    # Two sessions in the same day are allowed (history is per-session).
    _complete_one_session(api, program["id"], exercise["id"])
    _complete_one_session(api, program["id"], exercise["id"])

    api.as_user(ADMIN_ID)
    page1 = api.get(f"{REHAB}/patients/{PATIENT_A_ID}/sessions?limit=1&offset=0").json()
    assert page1["total"] == 2
    assert len(page1["items"]) == 1
    page2 = api.get(f"{REHAB}/patients/{PATIENT_A_ID}/sessions?limit=1&offset=1").json()
    assert len(page2["items"]) == 1
    assert page1["items"][0]["id"] != page2["items"][0]["id"]


def test_admin_appointment_history_is_admin_only(api):
    # Patient cannot use the admin appointment-history endpoint.
    api.as_user(PATIENT_A_ID)
    assert api.get(f"/api/v1/appointments/patient/{PATIENT_A_ID}").status_code == 403

    # Admin can (empty history is a valid 200).
    api.as_user(ADMIN_ID)
    r = api.get(f"/api/v1/appointments/patient/{PATIENT_A_ID}")
    assert r.status_code == 200
    assert isinstance(r.json(), list)
