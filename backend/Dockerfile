# APX PRO backend — production image.
# Python 3.13 + the Microsoft ODBC Driver 18 that pyodbc needs to reach MSSQL.
FROM python:3.13-slim-bookworm

# ── System deps: Microsoft ODBC Driver 18 + unixODBC (for pyodbc) ──────────────
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gnupg apt-transport-https ca-certificates gcc g++ unixodbc-dev \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list \
       | sed 's|https://packages.microsoft.com|[signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com|' \
       > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc \
    && apt-get purge -y curl gnupg \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first so this layer is cached across code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App code (see .dockerignore — venv/.env/secrets are excluded).
COPY . .

EXPOSE 8000

# Single uvicorn process. The app's startup hook schedules the notification
# cleanup job; keep to one process (or make workers idempotent) so it runs once.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
