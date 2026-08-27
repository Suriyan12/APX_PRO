# Deploying the APX PRO backend (VPS + Docker + automatic HTTPS)

This runs three containers — **SQL Server**, the **FastAPI app**, and **Caddy**
(which terminates TLS and reverse-proxies the app). Only Caddy is exposed to the
internet; the database and app stay on Docker's internal network.

## 0. What you need
- A **domain** (e.g. `example.com`) and the ability to add a DNS record.
- A **VPS**: Ubuntu 22.04+, **2 GB RAM minimum** (4 GB recommended — SQL Server
  Express is memory-hungry), ~20 GB disk. (Hetzner CX22 / DigitalOcean 2–4 GB.)
- Your secrets: Razorpay keys, Google Drive OAuth values, `firebase-service-account.json`, SMTP creds.

## 1. Point your domain at the server
Create a DNS **A record**: `api.example.com` → your VPS public IP. Wait until
`ping api.example.com` shows the right IP (DNS can take a few minutes).

## 2. Install Docker on the server
```bash
curl -fsSL https://get.docker.com | sh
```
Log out/in so your user can run Docker (or use `sudo`).

## 3. Get the code onto the server
```bash
git clone https://github.com/Suriyan12/APX_PRO.git
cd APX_PRO/deploy
```

## 4. Configure
```bash
cp .env.example .env
nano .env          # fill in EVERY value; use the SAME strong SA password in
                   # MSSQL_SA_PASSWORD and DATABASE_URL

mkdir -p secrets
# copy your firebase-service-account.json into ./secrets/ (scp/paste)

nano Caddyfile     # set your real domain (api.example.com) and email
```

## 5. Launch
```bash
docker compose up -d --build
```
Caddy fetches a Let's Encrypt certificate automatically on first start (needs
ports 80/443 open in the VPS firewall).

## 6. One-time database setup
SQL Server starts empty. Provision the whole database in one step with the
included script (creates the DB, all tables from the models, and the migration
extras — all idempotent, safe to re-run):
```bash
chmod +x init-db.sh
./init-db.sh
```
That's it — no manual SQL needed. (Under the hood it waits for SQL Server,
creates `apx_pro`, runs `python -m app.init_db` to build every table from the
models, then applies `backend/migrations/*.sql` for DB-level extras.)

## 7. Verify
```bash
curl https://api.example.com/            # -> {"status":"online", ...}
```

## 8. Point the mobile app at it
Build the release app with your HTTPS API:
```bash
flutter build appbundle --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

## Operations
- **Logs:** `docker compose logs -f api`
- **Update after a git pull:** `docker compose up -d --build`
- **Backups (do this!):** snapshot the `mssql-data` volume, e.g.
  ```bash
  docker compose exec db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -No \
    -Q "BACKUP DATABASE apx_pro TO DISK='/var/opt/mssql/apx_pro.bak' WITH INIT;"
  ```
  then copy the `.bak` off the server on a schedule.
- **Firewall:** allow only 22 (SSH), 80, 443.

## Notes / caveats
- SQL Server **Express** caps at 10 GB per database and limited RAM/CPU — fine to
  start; move to a licensed edition or Azure SQL as you grow.
- Keep `.env`, `secrets/`, and your Play **upload keystore** OUT of git (already
  gitignored).
- This is a single-server setup (no HA). Add managed DB / multiple app replicas
  when traffic warrants it.
