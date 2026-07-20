# APX PRO FastAPI Backend Engine

Production-grade, asynchronous backend built with FastAPI, SQLAlchemy, and PostgreSQL.

## Getting Started

### 1. Requirements

- Python 3.10+
- PostgreSQL Database

### 2. Setup Environment

Create a virtual environment and install the required dependencies:

```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Database Migration & Initialization

Make sure PostgreSQL is running, and create a database named `apx_pro`.
You can customize the DB connection string in the environment variable:

```bash
set DATABASE_URL=postgresql://username:password@localhost:5432/apx_pro
```

To create all tables immediately on startup (for quick local development), we have enabled SQLAlchemy base binding. To use migrations:

```bash
alembic init migrations
alembic revision --autogenerate -m "Initial schema setup"
alembic upgrade head
```

### 4. Running the Development Server

Start the API server locally:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Once running, navigate to:
- Interactive Swagger API Documentation: [http://localhost:8000/docs](http://localhost:8000/docs)
- Alternative Redoc Documentation: [http://localhost:8000/redoc](http://localhost:8000/redoc)

## Features Included

1. **JWT & OTP Auth**: Under `app/api/v1/auth.py`. Handles access/refresh token rotation.
2. **Online Consultation**: Under `app/api/v1/appointments.py`. For calendar scheduling and slots management.
3. **Medical Reports**: Under `app/api/v1/reports.py`. Integrates with AWS S3 pre-signed upload URLs.
4. **Posture Scans**: Under `app/api/v1/posture.py`. Custom video uploads and admin feedback scoring.
5. **Workout Logs**: Under `app/api/v1/programs.py`. Tracks exercise completion and serves videos from CloudFront CDN.
6. **Progress Tracker**: Under `app/api/v1/progress.py`. Logs daily measurement metrics.
7. **Razorpay Payments**: Under `app/api/v1/payment.py`. Generates payment order details and verifies signatures.
