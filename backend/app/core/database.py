import logging
import time

from sqlalchemy import create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker

from app.core.config import settings

logger = logging.getLogger(__name__)

# SQLAlchemy engine for MSSQL (pyodbc/pymssql).
#   pool_pre_ping  — validate a connection before use (drops dead sockets).
#   pool_recycle   — proactively recycle connections older than 30 min so the
#                    DB/idle-timeout never hands us a half-closed socket.
#   pool_size /    — a real pool (default was only 5) so concurrent requests
#   max_overflow     don't serialize on connection checkout under load.
# SQLite (used by the test suite) doesn't accept these pool args, so they are
# only applied to server database URLs.
_is_sqlite = settings.DATABASE_URL.startswith("sqlite")

_engine_kwargs = {"pool_pre_ping": True}
if not _is_sqlite:
    _engine_kwargs.update(pool_size=10, max_overflow=20, pool_recycle=1800)
    # Fail an individual login attempt quickly so the retry loop below can make
    # several attempts inside one request instead of burning its whole budget on
    # a single hung connect. pymssql accepts login_timeout; other drivers ignore
    # unknown kwargs at their own discretion, so this is applied best-effort.
    if settings.DATABASE_URL.startswith("mssql+pymssql"):
        _engine_kwargs["connect_args"] = {"login_timeout": 8, "timeout": 30}

engine = create_engine(settings.DATABASE_URL, **_engine_kwargs)


# ── Transient-failure retry (Azure SQL serverless auto-pause) ─────────────────
#
# A serverless Azure SQL database pauses itself after its auto-pause delay (60
# minutes on the free offer). The first connection afterwards does NOT wait for
# the resume: it fails after ~15s with error 40613 "Database ... is not
# currently available", while the resume continues in the background and
# completes ~40-50s later.
#
# Without a retry that made the app look broken rather than slow. The home
# screen issues eight requests in parallel, so a single paused database
# produced eight HTTP 500s over several minutes and every panel rendered its
# empty state. pool_pre_ping does not help here — it detects a dead socket on a
# pooled connection, but this is a brand-new connect to a server that is
# genuinely unavailable for the next few seconds.
#
# So: retry the connect on the documented transient error numbers until the
# resume finishes. Retrying turns "eight failures over four minutes" into one
# slow-but-successful first request, after which everything is warm.
#
# Reference: Azure SQL transient error numbers to retry.
_TRANSIENT_SQL_ERRORS = frozenset({
    40613,   # database is not currently available (serverless resuming)
    40197,   # service error processing the request; retry
    40501,   # service is busy (throttling)
    40540,   # service error; retry
    10928,   # resource ID limit reached
    10929,   # resource ID minimum guarantee not met
    49918,   # cannot process request; not enough resources
    49919,   # cannot process create/update request
    49920,   # cannot process request; too many operations
    4060,    # cannot open database (transient during failover/resume)
    4221,    # login to read-secondary failed due to replica lag
    64,      # connection was successfully established but then broken
    20,      # instance does not support encryption / transport-level slip
})

# Total wall-clock budget for waking a paused database. Sized against a measured
# resume of ~45-50s, with headroom. The Flutter client's timeouts must exceed
# this or it will give up while the server is still legitimately waiting.
_CONNECT_RETRY_BUDGET_SECONDS = 75
_CONNECT_RETRY_BACKOFF = (1, 2, 4, 6, 8, 10, 10, 10, 10, 10)


def _is_transient(exc: BaseException) -> bool:
    """True when an exception looks like a retryable Azure SQL condition.

    Checks the driver's error number where available and falls back to the
    message, because pymssql surfaces the number inside a bytes payload rather
    than a structured field.
    """
    for arg in getattr(exc, "args", ()):
        if isinstance(arg, int) and arg in _TRANSIENT_SQL_ERRORS:
            return True
    text = str(exc).lower()
    return any(
        marker in text
        for marker in (
            "is not currently available",
            "adaptive server connection failed",
            "server is not found or not accessible",
            "the service is currently busy",
            "login timeout expired",
            "connection was successfully established",
        )
    )


if not _is_sqlite:

    @event.listens_for(engine, "do_connect")
    def _connect_with_retry(dialect, conn_rec, cargs, cparams):
        """Replace the dialect's connect with a retrying one.

        Returning a connection from `do_connect` short-circuits SQLAlchemy's own
        connect, so this is the supported hook for adding retry around the very
        first socket to the database.
        """
        deadline = time.monotonic() + _CONNECT_RETRY_BUDGET_SECONDS
        last_exc = None
        for attempt, pause in enumerate(_CONNECT_RETRY_BACKOFF, start=1):
            try:
                return dialect.dbapi.connect(*cargs, **cparams)
            except Exception as exc:  # driver-specific; normalised by _is_transient
                if not _is_transient(exc):
                    raise
                last_exc = exc
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                sleep_for = min(pause, remaining)
                logger.warning(
                    "Database unavailable (attempt %d) - likely a serverless "
                    "resume; retrying in %.0fs. %s",
                    attempt, sleep_for, str(exc)[:160],
                )
                time.sleep(sleep_for)
        logger.error(
            "Database still unavailable after %ds; giving up.",
            _CONNECT_RETRY_BUDGET_SECONDS,
        )
        raise last_exc


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
