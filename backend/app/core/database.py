from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.core.config import settings

# SQLAlchemy engine for MSSQL (pyodbc/pymssql).
#   pool_pre_ping  — validate a connection before use (drops dead sockets).
#   pool_recycle   — proactively recycle connections older than 30 min so the
#                    DB/idle-timeout never hands us a half-closed socket.
#   pool_size /    — a real pool (default was only 5) so concurrent requests
#   max_overflow     don't serialize on connection checkout under load.
# SQLite (used by the test suite) doesn't accept these pool args, so they are
# only applied to server database URLs.
_engine_kwargs = {"pool_pre_ping": True}
if not settings.DATABASE_URL.startswith("sqlite"):
    _engine_kwargs.update(pool_size=10, max_overflow=20, pool_recycle=1800)

engine = create_engine(settings.DATABASE_URL, **_engine_kwargs)

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
