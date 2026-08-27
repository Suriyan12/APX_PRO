# APX PRO backend on Azure — no Docker

This is the record of the live testing deployment, not a generic guide. The
resource names below are the real ones.

| Piece | Azure service | Name |
|---|---|---|
| Database | Azure SQL Database (serverless, free offer) | `apx-sql-sr` / `apx_pro` |
| API | Azure App Service (Linux, Python 3.13) | `apx-api-sr` |
| Group | Resource Group, Central India | `apx-rg` |

Live at **https://apx-api-sr.azurewebsites.net** — cost **$0/month**.

**No Docker.** The `Dockerfile`, `docker-compose.yml`, `Caddyfile` and
`init-db.sh` in this folder belong to the VPS path only. App Service runs the
source zip directly and terminates TLS itself, so Caddy is not involved.

**Driver:** Azure uses `mssql+pymssql://`, not `pyodbc`. `pymssql` is already in
`requirements.txt` and bundles its own TDS client, so App Service needs no
`msodbcsql` system package. Local dev keeps using pyodbc + Windows auth —
nothing about the local setup changes.

---

## Read this first: five things that cost real time

1. **Register the SQL provider before anything else.** A new subscription has
   `Microsoft.Sql` unregistered, and `az sql server create` fails with
   `MissingSubscriptionRegistration` instead of registering it for you (the App
   Service CLI *does* auto-register `Microsoft.Web`, which is why this is easy to
   get caught out by).

   ```powershell
   az provider register --namespace Microsoft.Sql --wait
   ```

2. **No `@` or symbols in the SQL password.** `@` separates credentials from the
   host in a URL, so a password containing it silently reparses the connection
   string — the host becomes `<rest-of-password>@apx-sql-sr...` and you get a
   confusing DNS/login error. Azure SQL only needs upper + lower + digit, so
   letters and digits are enough. If a symbol is unavoidable, always build the
   URL with `[uri]::EscapeDataString($DBPASS)`.

3. **Deploy the code BEFORE setting the startup command.** Setting
   `--startup-file` on an empty app makes App Service run uvicorn against a
   missing module, crash, and restart in a loop. On the F1 Free tier that burned
   the whole 60-CPU-minute daily quota in ~40 minutes (`WPStopRequests: 86`),
   putting the site into `state: QuotaExceeded` and returning 403 to the
   deployment endpoint until 00:00 UTC.

4. **Keep the app RUNNING during deploy.** `az webapp deploy` polls until the
   site reports started. Deploying to a stopped app makes the CLI loop on
   `Starting the site...` and exit 1 — even though the deployment itself
   succeeded. Check `az webapp log deployment show` before believing the exit
   code.

5. **`init_db` needed a model fix to work at all.** See the next section.

---

## The schema bug this deployment exposed

`python -m app.init_db` could never build the schema on a fresh SQL Server.
`appointments` and `posture_scans` each had **two** foreign keys to `users` with
delete actions (`patient_id ON DELETE CASCADE` plus `admin_id` / `reviewed_by`
`ON DELETE SET NULL`). SQL Server rejects that outright:

```
(1785) Introducing FOREIGN KEY constraint ... may cause cycles or
multiple cascade paths.
```

The test suite runs on SQLite, which does not enforce the rule, and the local
database was built up through the numbered migrations rather than `create_all`
— so it had never surfaced.

Fixed by dropping `ondelete` from `Appointment.admin_id` and
`PostureScan.reviewed_by`. Nothing is lost: `UserService.delete_user_and_data`
already nulls both columns in Python before deleting a user, so the DB-level
rule was pure redundancy. Both lines carry comments to stop it being re-added.

**`schema.sql` still has the same flaw** and is badly out of date (11 tables;
missing `notifications`, `help_videos`, `device_tokens`, and all `rehab_*` /
`notes_*`). Migration 001's header still tells people to use it for a fresh
install — that advice is wrong. Delete or regenerate it.

---

## Provisioning, in order

```powershell
az login
az provider register --namespace Microsoft.Sql --wait     # gotcha 1 above

az group create -n apx-rg -l centralindia
```

### Database

Pick a password with letters and digits only (gotcha 2).

```powershell
$sec = Read-Host "New SQL admin password" -AsSecureString
$DBPASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

az sql server create -g apx-rg -n apx-sql-sr -l centralindia --admin-user apxadmin --admin-password $DBPASS
```

Reserved admin names Azure rejects: `admin`, `administrator`, `sa`, `root`,
`guest`, `public`, `dbmanager`, `loginmanager`.

```powershell
az sql db create -g apx-rg -s apx-sql-sr -n apx_pro --edition GeneralPurpose --compute-model Serverless --family Gen5 --capacity 2 --use-free-limit --free-limit-exhaustion-behavior AutoPause --backup-storage-redundancy Local
```

GP Serverless is the **cheapest** option, not an upgrade: it is the only tier
with a free allowance (100k vCore-sec + 32 GB/mo). `AutoPause` on exhaustion
means it **stops rather than billing**.

```powershell
az sql server firewall-rule create -g apx-rg -s apx-sql-sr -n allow-azure --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0
$ip = (Invoke-RestMethod https://api.ipify.org)
az sql server firewall-rule create -g apx-rg -s apx-sql-sr -n my-pc --start-ip-address $ip --end-ip-address $ip
```

### App Service

```powershell
az appservice plan create -g apx-rg -n apx-plan --is-linux --sku F1
az webapp create -g apx-rg -p apx-plan -n apx-api-sr --runtime "PYTHON:3.13"

az webapp update -g apx-rg -n apx-api-sr --https-only true
az webapp config set -g apx-rg -n apx-api-sr --ftps-state Disabled
```

`--https-only` ships **off** — plain HTTP is allowed until you set it.

### Settings

`DATABASE_URL` must be set before the first deploy: the app's fallback uses
`pyodbc`, which is not installed on Linux, so it would crash-loop.

```powershell
$b = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$secret = ([Convert]::ToBase64String($b)) -replace '\+','-' -replace '/','_' -replace '=',''
$URL = "mssql+pymssql://apxadmin:$([uri]::EscapeDataString($DBPASS))@apx-sql-sr.database.windows.net:1433/apx_pro"

az webapp config appsettings set -g apx-rg -n apx-api-sr --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true ENVIRONMENT=production DEVELOPMENT_MODE=false FCM_ENABLED=false ALLOWED_ORIGINS=https://apx-api-sr.azurewebsites.net "SECRET_KEY=$secret" "DATABASE_URL=$URL" --output none
$secret = $null
```

`SECRET_KEY` is the only setting the app refuses to start without.

---

## Schema and migrations

```powershell
cd "D:\APX PRO\backend"
$env:DATABASE_URL = $URL
.\venv\Scripts\python.exe -m app.init_db
```

`init_db` **prints** errors instead of crashing — read the last line rather than
trusting the exit code. You want `Database tables created successfully!`

```powershell
$env:AZURE_SQL_PASSWORD = $DBPASS
cd "D:\APX PRO\deploy"
.\apply-migrations.ps1 -Server apx-sql-sr.database.windows.net -Database apx_pro -User apxadmin
```

Note `AZURE_SQL_PASSWORD` takes the **raw** password — sqlcmd receives it
directly, not through a URL, so it must not be percent-encoded.

`apply-migrations.ps1` exists because two sqlcmd flags are easy to miss:

- **`-I`** (QUOTED_IDENTIFIER ON) — sqlcmd leaves this OFF, and the *filtered*
  unique indexes in migrations 014 and 018 cannot be created without it.
  Pasting the files into the Portal query editor fails on exactly the two
  indexes that protect against replayed payments and multiple featured videos.
- **`-N`** (encrypt) — Azure SQL refuses unencrypted connections.

It also handles the 64 `GO` batch separators across 15 files (`GO` is a sqlcmd
directive, not SQL, so a plain Python runner throws syntax errors), treats
"already exists" as `[skip]` rather than failure (expected — `init_db` created
the tables), and verifies both indexes exist afterwards instead of assuming.

Expected: `17 applied, 1 skipped, 0 failed`, both indexes `present`.

---

## Deploy

Build a clean zip from git-tracked files. This excludes `.env`,
`firebase-service-account.json`, `oauth_client.json` and `venv/` automatically,
and the root `.gitattributes` drops `media/` (27 MB of unused legacy samples)
and `tests/`. Result: ~126 KB.

```powershell
cd "D:\APX PRO"
git archive --worktree-attributes --format=zip --output backend.zip HEAD:backend
az webapp deploy -g apx-rg -n apx-api-sr --src-path backend.zip --type zip
```

`git archive` packs the **committed** tree — commit your changes first, or build
the zip from `git ls-files` if you need working-tree content.

---

## Admin user

```powershell
cd "D:\APX PRO\backend"
$env:DATABASE_URL = (az webapp config appsettings list -g apx-rg -n apx-api-sr --query "[?name=='DATABASE_URL'].value | [0]" -o tsv).Trim()
$env:ADMIN_EMAIL = "you@example.com"; $env:ADMIN_NAME = "APX Admin"; $env:ADMIN_PHONE = "9876543210"
$s2 = Read-Host "app admin password" -AsSecureString
$env:ADMIN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
.\venv\Scripts\python.exe create_admin.py
Remove-Item Env:\ADMIN_PASSWORD, Env:\ADMIN_EMAIL, Env:\ADMIN_NAME, Env:\ADMIN_PHONE, Env:\DATABASE_URL
```

Pulling `DATABASE_URL` from Azure rather than retyping the password avoids the
`18456` login-failed loop entirely.

`users.phone` is UNIQUE, so whatever you set is reserved permanently — use a
real number (login accepts email *or* phone).

---

## Point the app at it

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=https://apx-api-sr.azurewebsites.net/api/v1
flutter build appbundle --dart-define=API_BASE_URL=https://apx-api-sr.azurewebsites.net/api/v1
```

---

## Error codes you will hit

| Code | Means | Fix |
|---|---|---|
| `40613` "not currently available" | serverless DB was **asleep** (auto-pause 60 min) | wait ~30s and retry — the failed attempt triggers the wake |
| `40615` "IP not allowed" | your **dynamic IP changed** | update the `my-pc` rule (below) |
| `18456` "Login failed" | wrong SQL password | pull `DATABASE_URL` from Azure instead of retyping |
| `MissingSubscriptionRegistration` | provider not registered | `az provider register --namespace Microsoft.Sql --wait` |
| 403 / "Web App - Unavailable" | F1 **CPU quota exhausted** | resets 00:00 UTC; check `az webapp show -g apx-rg -n apx-api-sr --query state` |

Refresh the firewall rule after an IP change:

```powershell
$ip=(Invoke-RestMethod https://api.ipify.org); az sql server firewall-rule update -g apx-rg -s apx-sql-sr -n my-pc --start-ip-address $ip --end-ip-address $ip
```

The `allow-azure` rule is what the deployed API uses, so **a changed home IP
never affects the live app** — only scripts run from your PC.

---

## Verifying a deployment

```powershell
Invoke-WebRequest https://apx-api-sr.azurewebsites.net/
```

That endpoint does **not** touch the database. To prove the DB connection, POST
a bogus login — **HTTP 400** means the query ran and found no user (a broken
connection gives 500):

```powershell
Invoke-WebRequest -Uri "https://apx-api-sr.azurewebsites.net/api/v1/auth/login" -Method POST -Body @{username="probe@example.invalid";password="NotReal123"}
```

Login is `OAuth2PasswordRequestForm` — **form-encoded with `username`**, not
JSON. Posting JSON gives 422.

Expected in production mode: `/docs` and `/api/v1/openapi.json` both 404,
`/api/v1/users/me` 401, and HSTS + `nosniff` + `X-Frame-Options: DENY` +
`no-referrer` present.

---

## Cost and cleanup

- **App Service F1**: free forever. Limits: **60 CPU-min/day**, 1 GB disk, no
  Always On — so ~30s cold starts, and the nightly notification-cleanup loop in
  `main.py` does not run. B1 (~$0.018/hr ≈ $13/mo, billed hourly) removes all
  three.
- **Azure SQL free offer**: 100k vCore-sec + 32 GB/mo, one per subscription.
  Auto-pauses after 60 min idle, adding ~30–60s to the next request.
- **Delete everything**: `az group delete -n apx-rg --yes`

---

## Before this is more than a test deployment

- `main.py:79` sets `allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+"`,
  so any localhost origin is accepted even in production. Convenient for
  testing; tighten it for real use.
- `FCM_ENABLED=false` — push notifications are off. Enable by uploading the
  Firebase service account and setting `FIREBASE_CREDENTIALS_PATH`.
- Razorpay, Google Drive and SMTP settings are unset; those flows will fail
  until added as app settings.
- No backups configured beyond Azure SQL's built-in point-in-time restore.
