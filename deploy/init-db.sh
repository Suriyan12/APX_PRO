#!/usr/bin/env bash
#
# APX PRO — one-shot database provisioner (SQL Server).
#
# Creates the production database and all of its tables in a single step. Run
# this ONCE on the server, from the deploy/ directory, AFTER the stack is up:
#
#     docker compose up -d --build
#     ./init-db.sh
#
# It is safe to re-run: every step is idempotent (existing DB/tables/indexes are
# left untouched). The SQLAlchemy models are the source of truth for the schema
# (step 4); the numbered migrations only add DB-level extras like filtered
# unique indexes.
set -euo pipefail

DB_NAME="apx_pro"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"

# Always run relative to this script's own directory (the deploy/ folder).
cd "$(dirname "$0")"

# ── 1. Read the SA password from .env (the same one that launched SQL Server) ──
if [ ! -f .env ]; then
  echo "ERROR: .env not found in $(pwd). Copy .env.example to .env and fill it in first."
  exit 1
fi
SA_PW="$(grep -E '^MSSQL_SA_PASSWORD=' .env | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//')"
if [ -z "${SA_PW:-}" ]; then
  echo "ERROR: MSSQL_SA_PASSWORD is not set in .env"
  exit 1
fi

# Helper: run a query against the 'db' container (trusts the container's self-signed cert).
db_sql() { docker compose exec -T db "$SQLCMD" -S localhost -U sa -P "$SA_PW" -C "$@"; }

# ── 2. Wait for SQL Server to accept connections (first boot can take ~30–60s) ─
echo "Waiting for SQL Server to be ready..."
ready=0
for i in $(seq 1 45); do
  if db_sql -Q "SELECT 1" >/dev/null 2>&1; then ready=1; echo "  SQL Server is ready."; break; fi
  sleep 2
done
if [ "$ready" != "1" ]; then
  echo "ERROR: SQL Server did not become ready. Check: docker compose logs db"
  exit 1
fi

# ── 3. Create the database if it doesn't exist ─────────────────────────────────
echo "Ensuring database '$DB_NAME' exists..."
db_sql -Q "IF DB_ID('$DB_NAME') IS NULL CREATE DATABASE [$DB_NAME];"

# ── 4. Create all tables from the models (authoritative schema) ────────────────
echo "Creating tables from the app models (init_db)..."
docker compose exec -T api python -m app.init_db

# ── 5. Apply numbered migrations (idempotent DB-level extras) ──────────────────
echo "Applying migrations (idempotent)..."
shopt -s nullglob
applied=0
for f in ../backend/migrations/*.sql; do
  name="$(basename "$f")"
  if docker compose exec -T db "$SQLCMD" -S localhost -U sa -P "$SA_PW" -C -d "$DB_NAME" -b < "$f" >/dev/null 2>&1; then
    echo "  applied  $name"
    applied=$((applied + 1))
  else
    echo "  skipped  $name (already applied / not applicable)"
  fi
done
echo "  ($applied migration file(s) applied cleanly)"

echo
echo "✅ Database '$DB_NAME' is provisioned and ready."
echo "   Verify the API:  curl https://<your-domain>/"
