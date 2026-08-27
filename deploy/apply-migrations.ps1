<#
.SYNOPSIS
    Applies backend/migrations/*.sql to a SQL Server / Azure SQL database.

.DESCRIPTION
    Run this AFTER `python -m app.init_db` has created the tables from the models.
    init_db is the source of truth for the schema; these migrations only add
    DB-level extras (filtered unique indexes, CHECK constraints) that SQLAlchemy
    does not express.

    Because init_db already created every table, migrations that do a plain
    CREATE TABLE will fail with "There is already an object named ...". That is
    EXPECTED, not a problem - the script reports those as [skip] and keeps going.

    Two flags are essential and easy to get wrong:
      -I  QUOTED_IDENTIFIER ON. sqlcmd leaves this OFF by default, and filtered
          indexes (migration 014, 018) CANNOT be created without it.
      -N  Encrypt the connection. Azure SQL refuses unencrypted connections.

.PARAMETER Server
    e.g. apx-sql-sr.database.windows.net   (or "localhost" for local testing)

.PARAMETER Database
    e.g. apx_pro

.PARAMETER User
    SQL admin login, e.g. apxadmin. Omit to use Windows Authentication (local only).

.PARAMETER DryRun
    Parse and list what would run. Connects to nothing, changes nothing.

.EXAMPLE
    # Password is passed via the environment so it never lands in shell history
    # or the process command line:
    $env:AZURE_SQL_PASSWORD = "<your password>"
    .\apply-migrations.ps1 -Server apx-sql-sr.database.windows.net -Database apx_pro -User apxadmin
    Remove-Item Env:\AZURE_SQL_PASSWORD
#>
param(
    [Parameter(Mandatory = $false)][string]$Server,
    [string]$Database = "apx_pro",
    [string]$User,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ── Locate sqlcmd ─────────────────────────────────────────────────────────────
$sqlcmd = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
if (-not $sqlcmd) {
    $candidates = Get-ChildItem -Path "C:\Program Files\Microsoft SQL Server", `
                                      "C:\Program Files (x86)\Microsoft SQL Server", `
                                      "C:\Program Files\Microsoft SQL Server\Client SDK" `
                  -Filter "sqlcmd.exe" -Recurse -ErrorAction SilentlyContinue |
                  Sort-Object FullName -Descending
    if ($candidates) { $sqlcmd = $candidates[0].FullName }
}
if (-not $sqlcmd) { throw "sqlcmd.exe not found. Install the SQL Server command line tools." }
Write-Host "sqlcmd: $sqlcmd" -ForegroundColor DarkGray

# ── Collect migrations in order ───────────────────────────────────────────────
$migrationDir = Join-Path $PSScriptRoot "..\backend\migrations"
if (-not (Test-Path $migrationDir)) { throw "Migration folder not found: $migrationDir" }
$files = Get-ChildItem -Path $migrationDir -Filter "*.sql" | Sort-Object Name
if (-not $files) { throw "No .sql files found in $migrationDir" }
Write-Host "Found $($files.Count) migration file(s) in $migrationDir`n"

if ($DryRun) {
    foreach ($f in $files) {
        $go = (Select-String -Path $f.FullName -Pattern '^\s*GO\s*$').Count
        Write-Host ("  {0,-45} {1,4} GO batch(es)" -f $f.Name, $go)
    }
    Write-Host "`nDRY RUN - nothing was connected to and nothing was changed." -ForegroundColor Yellow
    exit 0
}

if (-not $Server) { throw "-Server is required (omit it only with -DryRun)." }

# ── Build the connection arguments ────────────────────────────────────────────
#   -I QUOTED_IDENTIFIER ON (required by the filtered indexes)
#   -N encrypt (required by Azure SQL)
#   -b non-zero exit code on SQL error, so $LASTEXITCODE is meaningful
#   -l login timeout: a serverless Azure SQL DB may be auto-paused and need to wake
$common = @("-S", $Server, "-d", $Database, "-I", "-N", "-b", "-l", "90")
if ($User) {
    if (-not $env:AZURE_SQL_PASSWORD) {
        throw "Set `$env:AZURE_SQL_PASSWORD before running (keeps the password out of the command line)."
    }
    # sqlcmd reads SQLCMDPASSWORD from the environment - avoids -P on the command line.
    $env:SQLCMDPASSWORD = $env:AZURE_SQL_PASSWORD
    $common += @("-U", $User)
} else {
    $common += "-E"   # Windows Authentication
    Write-Host "Using Windows Authentication (no -User given)." -ForegroundColor DarkGray
}

# ── Connectivity check before doing any work ──────────────────────────────────
Write-Host "Connecting to $Server / $Database ..." -NoNewline
& $sqlcmd @common -Q "SELECT 1" -h -1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host " FAILED" -ForegroundColor Red
    if ($env:SQLCMDPASSWORD) { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }
    throw "Could not connect. Check the server name, the firewall rule for your IP, and the password."
}
Write-Host " ok`n" -ForegroundColor Green

# ── Apply each file ───────────────────────────────────────────────────────────
$applied = @(); $skipped = @(); $failed = @()
foreach ($f in $files) {
    $out = & $sqlcmd @common -i $f.FullName 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("  [ ok ] {0}" -f $f.Name) -ForegroundColor Green
        $applied += $f.Name
    }
    elseif ($out -match "already an object named|already exists|Column names in each table must be unique|duplicate column") {
        # init_db already created this table/column from the models - expected.
        Write-Host ("  [skip] {0}  (already present)" -f $f.Name) -ForegroundColor DarkGray
        $skipped += $f.Name
    }
    else {
        Write-Host ("  [FAIL] {0}" -f $f.Name) -ForegroundColor Red
        Write-Host ($out.Trim() -split "`n" | Select-Object -First 4 | ForEach-Object { "         $_" })
        $failed += $f.Name
    }
}

# ── Verify the objects that only migrations can create ────────────────────────
Write-Host "`nVerifying migration-only objects:" -ForegroundColor Cyan
$checks = @(
    @{ Name = "UX_notes_purchases_payment_id"; Why = "blocks replayed Notes payments (014)" },
    @{ Name = "ux_help_videos_single_featured"; Why = "enforces one featured help video (018)" }
)
foreach ($c in $checks) {
    $r = (& $sqlcmd @common -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.indexes WHERE name = '$($c.Name)';" -h -1 | Out-String).Trim()
    if ($r -match "1") { Write-Host ("  present  {0}  - {1}" -f $c.Name, $c.Why) -ForegroundColor Green }
    else               { Write-Host ("  MISSING  {0}  - {1}" -f $c.Name, $c.Why) -ForegroundColor Yellow }
}

if ($env:SQLCMDPASSWORD) { Remove-Item Env:\SQLCMDPASSWORD -ErrorAction SilentlyContinue }

Write-Host ("`nSummary: {0} applied, {1} skipped (already present), {2} failed." -f $applied.Count, $skipped.Count, $failed.Count)
if ($failed.Count -gt 0) {
    Write-Host "Failed files:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host "Database is up to date." -ForegroundColor Green
