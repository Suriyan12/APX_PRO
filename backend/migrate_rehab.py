"""
Run once to create the 4 rehab tables in the existing SQL Server database.

    (venv) python migrate_rehab.py
"""
from app.core.database import Base, engine
from app.models.models import (  # noqa: F401 — imports register models with Base
    RehabProgram,
    RehabExercise,
    RehabWorkoutSession,
    RehabExerciseCompletion,
)

tables = [
    RehabProgram.__table__,
    RehabExercise.__table__,
    RehabWorkoutSession.__table__,
    RehabExerciseCompletion.__table__,
]

print("Creating rehab tables...")
Base.metadata.create_all(engine, tables=tables)
print("Done.")
