<#
.SYNOPSIS
    Copy selected secrets from backend/.env to the Azure App Service settings.

.DESCRIPTION
    Reads backend/.env locally and pushes an explicit ALLOW-LIST of keys to
    `az webapp config appsettings set`. Values are never printed, never logged,
    and never leave your machine except in the az call itself.

    Only the keys in $ALLOW below are copied. Everything else is skipped on
    purpose — several local values would BREAK the deployment if copied:

      DATABASE_URL              local points at localhost / Windows auth;
                                Azure must keep its own Azure SQL connection
      SECRET_KEY                Azure has its own generated key; overwriting it
                                invalidates every issued JWT
      ENVIRONMENT               must stay "production" on Azure
      DEVELOPMENT_MODE          must stay false — the app REFUSES TO START with
                                DEVELOPMENT_MODE=true when ENVIRONMENT=production
      ALLOWED_ORIGINS           different origin on Azure
      FIREBASE_CREDENTIALS_PATH a Windows path is meaningless on Linux
      FCM_ENABLED               needs the service-account file uploaded first
      SMTP_*                    already configured directly on Azure

.PARAMETER Apply
    Actually push the settings. Without it the script only reports what it WOULD
    do (no values shown, no changes made).

.EXAMPLE
    .\sync-env-to-azure.ps1              # report only
    .\sync-env-to-azure.ps1 -Apply       # push to Azure
#>
param(
    [string]$ResourceGroup = "apx-rg",
    [string]$WebApp        = "apx-api-sr",
    [string]$EnvFile,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

# Keys safe to copy from local .env to Azure.
$ALLOW = @(
    "RAZORPAY_KEY_ID",
    "RAZORPAY_KEY_SECRET",
    "GDRIVE_OAUTH_CLIENT_ID",
    "GDRIVE_OAUTH_CLIENT_SECRET",
    "GDRIVE_OAUTH_REFRESH_TOKEN",
    "GDRIVE_ROOT_FOLDER_ID",
    "GDRIVE_ROOT_FOLDER_NAME",
    "FIREBASE_PROJECT_ID",
    "MEDICAL_RECORD_MAX_FILE_SIZE_MB",
    "STUDY_MATERIAL_MAX_FILE_SIZE_MB",
    "REHAB_VIDEO_MAX_FILE_SIZE_MB",
    "NOTES_PRICE",
    "CLINIC_ADDRESS"
)

# Keys deliberately refused, with the reason shown to the user.
$REFUSE = [ordered]@{
    "DATABASE_URL"             = "local points at localhost; Azure must keep its Azure SQL string"
    "SECRET_KEY"               = "Azure has its own; overwriting invalidates all issued JWTs"
    "ENVIRONMENT"              = "must stay 'production' on Azure"
    "DEVELOPMENT_MODE"         = "must stay false; app refuses to start otherwise in production"
    "ALLOWED_ORIGINS"          = "different origin on Azure"
    "FIREBASE_CREDENTIALS_PATH" = "a Windows path is meaningless on Linux"
    "FCM_ENABLED"              = "needs the service-account file uploaded first"
    "SMTP_HOST"                = "already set on Azure"
    "SMTP_PORT"                = "already set on Azure"
    "SMTP_USER"                = "already set on Azure"
    "SMTP_PASSWORD"            = "already set on Azure"
}

# ── Locate az (the installer's PATH entry is not always present) ───────────────
$az = (Get-Command az -ErrorAction SilentlyContinue).Source
if (-not $az) {
    foreach ($p in @(
        "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd",
        "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd")) {
        if (Test-Path $p) { $az = $p; break }
    }
}
if (-not $az) { throw "Azure CLI not found. Install it, or open a new shell so PATH refreshes." }

# ── Locate .env ───────────────────────────────────────────────────────────────
if (-not $EnvFile) { $EnvFile = Join-Path $PSScriptRoot "..\backend\.env" }
if (-not (Test-Path $EnvFile)) { throw ".env not found at $EnvFile" }
Write-Host "Reading $EnvFile" -ForegroundColor DarkGray
Write-Host "(values are never printed by this script)`n" -ForegroundColor DarkGray

# ── Parse .env the way python-dotenv does: last occurrence of a key wins ──────
$parsed = [ordered]@{}
$dupes  = @{}
foreach ($line in Get-Content $EnvFile) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    $i = $t.IndexOf("=")
    if ($i -lt 1) { continue }
    $k = $t.Substring(0, $i).Trim()
    $v = $t.Substring($i + 1).Trim()
    # strip one layer of matching quotes
    if (($v.StartsWith('"') -and $v.EndsWith('"') -and $v.Length -ge 2) -or
        ($v.StartsWith("'") -and $v.EndsWith("'") -and $v.Length -ge 2)) {
        $v = $v.Substring(1, $v.Length - 2)
    }
    if ($parsed.Contains($k)) { $dupes[$k] = $true }
    $parsed[$k] = $v
}

if ($dupes.Count -gt 0) {
    Write-Host "WARNING: duplicate keys in .env (the LAST occurrence wins):" -ForegroundColor Yellow
    $dupes.Keys | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host ""
}

# ── Decide what to send ───────────────────────────────────────────────────────
$toSend = [ordered]@{}
Write-Host "WILL COPY:" -ForegroundColor Cyan
foreach ($k in $ALLOW) {
    if (-not $parsed.Contains($k)) { continue }
    $v = $parsed[$k]
    if ([string]::IsNullOrWhiteSpace($v)) {
        Write-Host ("  {0,-34} skipped (empty in .env)" -f $k) -ForegroundColor DarkGray
        continue
    }
    $toSend[$k] = $v
    Write-Host ("  {0,-34} {1} chars" -f $k, $v.Length) -ForegroundColor Green
}
if ($toSend.Count -eq 0) { Write-Host "  (nothing)" -ForegroundColor DarkGray }

Write-Host "`nWILL NOT COPY (deliberate):" -ForegroundColor Cyan
foreach ($k in $REFUSE.Keys) {
    if ($parsed.Contains($k)) {
        Write-Host ("  {0,-34} {1}" -f $k, $REFUSE[$k]) -ForegroundColor DarkGray
    }
}

$unknown = $parsed.Keys | Where-Object { $ALLOW -notcontains $_ -and -not $REFUSE.Contains($_) }
if ($unknown) {
    Write-Host "`nNOT RECOGNISED (left alone; add to `$ALLOW if needed):" -ForegroundColor Cyan
    $unknown | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

if (-not $Apply) {
    Write-Host "`nREPORT ONLY - nothing was sent. Re-run with -Apply to push." -ForegroundColor Yellow
    exit 0
}
if ($toSend.Count -eq 0) {
    Write-Host "`nNothing to send." -ForegroundColor Yellow
    exit 0
}

# ── Push in one call (one restart instead of N) ────────────────────────────────
Write-Host "`nPushing $($toSend.Count) setting(s) to $WebApp ..." -ForegroundColor Cyan
$args = @("webapp","config","appsettings","set","-g",$ResourceGroup,"-n",$WebApp,"--settings")
foreach ($k in $toSend.Keys) { $args += "$k=$($toSend[$k])" }
$args += @("--output","none")

& $az @args
if ($LASTEXITCODE -ne 0) { throw "az failed with exit code $LASTEXITCODE" }

# ── Verify by NAME only ───────────────────────────────────────────────────────
Write-Host "Done. Verifying (names only):" -ForegroundColor Green
# NOTE: do NOT redirect a native exe's stderr here. Windows PowerShell 5.1 wraps
# each stderr line in an ErrorRecord (NativeCommandError), which under
# $ErrorActionPreference="Stop" throws even when az exited 0 - and the az CLI
# prints a harmless 32-bit-Python warning to stderr on every call. Relaxing the
# preference for the verify step keeps a cosmetic warning from masking success.
$ErrorActionPreference = "Continue"
$names = & $az webapp config appsettings list -g $ResourceGroup -n $WebApp --query "[].name" -o tsv
foreach ($k in $toSend.Keys) {
    $ok = $names -contains $k
    Write-Host ("  {0,-34} {1}" -f $k, $(if ($ok) { "SET" } else { "MISSING" })) `
        -ForegroundColor $(if ($ok) { "Green" } else { "Red" })
}

Write-Host "`nThe app restarts automatically (~30s). Google Drive and Razorpay" -ForegroundColor DarkGray
Write-Host "flows should work once it is back up." -ForegroundColor DarkGray
Write-Host "NOTE: push notifications still need the Firebase service-account JSON" -ForegroundColor DarkGray
Write-Host "      uploaded and FCM_ENABLED=true - not handled by this script." -ForegroundColor DarkGray
