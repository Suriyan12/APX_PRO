import sys
import os

# Append parent directory to sys.path to allow app imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.database import engine, Base
# Import models to ensure they are registered on the Base metadata
from app.models.models import (
    User,
    RefreshToken,
    Appointment,
    MedicalReport,
    PostureScan,
    ExerciseProgram,
    UserAssignedProgram,
    Exercise,
    WorkoutLog,
    ProgressLog,
)

def create_tables():
    print("Connecting to SQL Server and creating tables...")
    try:
        Base.metadata.create_all(bind=engine)
        print("Database tables created successfully!")
    except Exception as e:
        print(f"Error creating tables: {e}")
        print("\nPlease check that your database URL in app/core/config.py is correct and SQL Server is running.")

if __name__ == "__main__":
    create_tables()
