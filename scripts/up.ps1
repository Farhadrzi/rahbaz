<#
.SYNOPSIS
  Start the RahBaz stack (cliproxy + switch-notifier) on Docker Desktop.

.DESCRIPTION
  - Creates .env from .env.example and config\config.yaml from config\config.example.yaml
    when missing. A fresh config.yaml gets a random gateway API key and management key.
  - Ensures auths\, logs\cliproxy, logs\notifier and plugins\ exist.
  - Runs `docker compose up -d --build` and waits for the gateway to answer.

.PARAMETER NoBuild
  Skip --build (faster restarts when the notifier has not changed).
.PARAMETER ProxyOnly
  Start only cliproxy. Also chosen automatically when services\switch-notifier\Dockerfile
  does not exist yet.
.PARAMETER Pull
  `docker compose pull cliproxy` first (picks up a newer upstream image).
.PARAMETER WaitSeconds
  How long to wait for the gateway to answer (default 60).
#>
[CmdletBinding()]
param(
    [switch]$NoBuild,
    [switch]$ProxyOnly,
    [switch]$Pull,
    [int]$WaitSeconds = 60
)

. "$PSScriptRoot\_common.ps1"

Assert-DockerReady
$root = $script:RepoRoot

# --- .env -------------------------------------------------------------------
$envFile = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Copy-Item -LiteralPath (Join-Path $root '.env.example') -Destination $envFile
    Write-Ok 'Created .env from .env.example'
}

# --- config.yaml ------------------------------------------------------------
$configPath = Get-ConfigPath
$configDir = Split-Path -Parent $configPath
if (-not (Test-Path -LiteralPath $configDir)) { New-Item -ItemType Directory -Force -Path $configDir | Out-Null }

if (Test-Path -LiteralPath $configPath -PathType Container) {
    # Docker creates a directory when a bind-mounted file is missing at first start.
    throw "$configPath is a directory (Docker creates one when the file is missing). Stop the stack, delete that directory, and rerun."
}

if (-not (Test-Path -LiteralPath $configPath)) {
    $example = Join-Path $root 'config\config.example.yaml'
    $text = [System.IO.File]::ReadAllText($example)
    $gatewayKey = New-RandomKey 'rbgw'
    $mgmtKey = New-RandomKey 'rbmgmt'
    $text = $text.Replace('change-me-rahbaz-gateway-key', $gatewayKey).Replace('change-me-management-key', $mgmtKey)
    Write-Utf8NoBom $configPath $text
    Write-Ok "Created $configPath from config.example.yaml with fresh random keys."
    Write-Host '  Gateway API key (for T3):  open config.yaml -> access.api-keys[0]'
    Write-Warn "  Management key (shown ONCE; the proxy bcrypt-hashes it in config.yaml): $mgmtKey"
    Write-Host '  Save it now if you want status.ps1 / management API access.'
} elseif (Test-ConfigHasPlaceholders) {
    Write-Warn 'config.yaml still contains "change-me-*" placeholder keys. Replace them with long random values.'
}

# --- runtime directories ----------------------------------------------------
$dirs = @(
    (Get-AuthDir),
    (Resolve-RepoPath (Get-DotEnvValue 'CLI_PROXY_LOG_PATH' './logs/cliproxy')),
    (Join-Path $root 'logs\notifier'),
    (Resolve-RepoPath (Get-DotEnvValue 'CLI_PROXY_PLUGIN_PATH' './plugins'))
)
foreach ($d in $dirs) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        Write-Host "Created $d"
    }
}

# --- compose up -------------------------------------------------------------
$services = @()
$notifierDockerfile = Join-Path $root 'services\switch-notifier\Dockerfile'
if ($ProxyOnly) {
    $services = @($script:ServiceName)
} elseif (-not (Test-Path -LiteralPath $notifierDockerfile)) {
    Write-Warn 'services\switch-notifier\Dockerfile not found - starting cliproxy only.'
    $services = @($script:ServiceName)
}

if ($Pull) {
    Write-Info 'Pulling upstream image...'
    Invoke-Compose pull $script:ServiceName
    if ($LASTEXITCODE -ne 0) { throw "docker compose pull failed (exit $LASTEXITCODE)" }
}

$upArgs = @('up', '-d')
if (-not $NoBuild) { $upArgs += '--build' }
$upArgs += $services

Write-Info ('docker compose ' + ($upArgs -join ' '))
Invoke-Compose @upArgs
if ($LASTEXITCODE -ne 0) { throw "docker compose up failed (exit $LASTEXITCODE)" }

# --- wait for gateway -------------------------------------------------------
# GET / needs no API key; /v1/* does.
Write-Info "Waiting up to $WaitSeconds s for the gateway..."
$deadline = (Get-Date).AddSeconds($WaitSeconds)
$up = $false
while ((Get-Date) -lt $deadline) {
    $probe = Invoke-Probe "$($script:ApiBase)/" -TimeoutSec 3
    if ($probe.Ok -or $probe.Status -gt 0) { $up = $true; break }
    Start-Sleep -Seconds 2
}

Write-Host ''
if ($up) { Write-Ok 'Gateway is answering.' } else { Write-Warn 'Gateway did not answer yet. Check: docker compose logs cliproxy' }

Write-Host ''
Write-Info 'Endpoints (all bound to 127.0.0.1)'
Write-Host "  API (T3 clients)    $($script:ApiBase)         Claude base URL"
Write-Host "                      $($script:ApiBase)/v1      OpenAI / Codex base URL"
Write-Host "  Management API      $($script:ApiBase)/v8/management   (needs management.secret-key)"
Write-Host "  Switch events (SSE) $($script:NotifierBase)/events     (switch-notifier)"
Write-Host "  Switch status       $($script:NotifierBase)/status"
Write-Host '  OAuth callbacks     1455 (Codex)  54545 (Claude)  51121 (Antigravity)'
Write-Host ''
Write-Info 'Next'
Write-Host '  .\scripts\login-claude.ps1       # repeat per account'
Write-Host '  .\scripts\login-codex.ps1'
Write-Host '  .\scripts\login-antigravity.ps1'
Write-Host '  .\scripts\status.ps1'
