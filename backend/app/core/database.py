from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.core.config import settings

# Create engine (configured for PostgreSQL)
engine = create_engine(
    settings.DATABASE_URL,
    # pool_pre_ping helps detect dropped connections
    pool_pre_ping=True
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    """
    Database dependency context manager for FastAPI routes.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
