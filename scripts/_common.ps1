# RahBaz shared helpers. Dot-source from other scripts:
#   . "$PSScriptRoot\_common.ps1"
# Windows PowerShell 5.1 compatible. Keep this file pure ASCII (5.1 reads
# BOM-less files as ANSI).

$ErrorActionPreference = 'Stop'

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ComposeFile = Join-Path $script:RepoRoot 'compose.yaml'
$script:ApiBase = 'http://127.0.0.1:8317'
$script:ServiceName = 'cliproxy'
$script:ContainerBinary = '/CLIProxyAPI/CLIProxyAPI'

function Write-Info([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host $Message -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host $Message -ForegroundColor Yellow }
function Write-Err([string]$Message)  { Write-Host $Message -ForegroundColor Red }

# Run `docker compose` against this repo regardless of the caller's cwd.
function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$ComposeArgs)
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile @ComposeArgs
}

function Assert-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'docker was not found on PATH. Install Docker Desktop and reopen the terminal.'
    }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # native stderr must not throw under 5.1
    try {
        & docker info *> $null
        $ok = ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $previous
    }
    if (-not $ok) {
        throw 'Docker daemon is not reachable. Start Docker Desktop, wait for "Engine running", then retry.'
    }
}

# Value of NAME from .env (compose reads the same file), else $Default.
function Get-DotEnvValue {
    param([string]$Name, [string]$Default = '')
    $file = Join-Path $script:RepoRoot '.env'
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $file) {
            if ($line -match ('^\s*' + [regex]::Escape($Name) + '\s*=\s*(.*?)\s*$')) {
                $value = $Matches[1].Trim('"').Trim("'")
                if ($value) { return $value }
            }
        }
    }
    return $Default
}

# Resolve a path from .env (relative paths are relative to the repo root).
function Resolve-RepoPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return [System.IO.Path]::GetFullPath((Join-Path $script:RepoRoot $Path))
}

function Get-AuthDir   { Resolve-RepoPath (Get-DotEnvValue 'CLI_PROXY_AUTH_PATH' './auths') }
function Get-ConfigPath { Resolve-RepoPath (Get-DotEnvValue 'CLI_PROXY_CONFIG_PATH' './config/config.yaml') }

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    # Go's YAML parser dislikes a BOM; Set-Content -Encoding UTF8 adds one on 5.1.
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function New-RandomKey([string]$Prefix = 'rb') {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return $Prefix + '-' + (([BitConverter]::ToString($bytes) -replace '-', '').ToLower())
}

# First client key under access.api-keys (v8) or legacy top-level api-keys.
function Get-GatewayKey {
    $cfg = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return $null }
    $text = [System.IO.File]::ReadAllText($cfg)
    $m = [regex]::Match($text, '(?ms)(?:^|\n)\s*access:\s*.*?^\s*api-keys:\s*\r?\n\s*-\s*["'']?([^"''\s#]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($text, '(?m)^\s*api-keys:\s*\r?\n\s*-\s*["'']?([^"''\s#]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# True when config.yaml still carries the example placeholders.
function Test-ConfigHasPlaceholders {
    $cfg = Get-ConfigPath
    if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return $false }
    $text = [System.IO.File]::ReadAllText($cfg)
    return ($text -match 'change-me-rahbaz-gateway-key' -or $text -match 'change-me-management-key')
}

# HTTP probe that never throws. Returns @{ Ok; Status; Body; Error }.
function Invoke-Probe {
    param([string]$Url, [hashtable]$Headers = @{}, [int]$TimeoutSec = 5)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -Headers $Headers -TimeoutSec $TimeoutSec
        return @{ Ok = $true; Status = [int]$r.StatusCode; Body = [string]$r.Content; Error = $null }
    } catch {
        $status = 0
        $body = ''
        $resp = $null
        if ($_.Exception.PSObject.Properties['Response']) { $resp = $_.Exception.Response }
        if ($resp) {
            try { $status = [int]$resp.StatusCode } catch { }
        }
        return @{ Ok = $false; Status = $status; Body = $body; Error = $_.Exception.Message }
    }
}

function Test-ServiceRunning([string]$Service) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $running = @(Invoke-Compose ps --status running --services 2>$null)
    } finally {
        $ErrorActionPreference = $previous
    }
    return ($running -contains $Service)
}

# Interactive OAuth login inside the running container.
# Default is --no-browser: the container cannot open a browser, so the CLI
# prints a URL for you to open on the Windows host. The provider then redirects
# to http://localhost:<CallbackPort>/..., which Docker publishes to the container.
function Invoke-ProviderLogin {
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$LoginFlag,
        [Parameter(Mandatory = $true)][int]$CallbackPort,
        [switch]$TryBrowser,
        [switch]$RestartAfter,
        [string]$ExtraNote = ''
    )

    Assert-DockerReady
    if (-not (Test-ServiceRunning $script:ServiceName)) {
        throw "Service '$($script:ServiceName)' is not running. Run .\scripts\up.ps1 first."
    }

    $authDir = Get-AuthDir
    $before = @()
    if (Test-Path -LiteralPath $authDir) {
        $before = @(Get-ChildItem -LiteralPath $authDir -Filter '*.json' -File | ForEach-Object { $_.Name })
    }

    Write-Info "== $Provider OAuth login =="
    Write-Host "Callback port : $CallbackPort (published as 127.0.0.1:$CallbackPort -> container)"
    Write-Host 'Run this once per account. Repeat the script for account #2, #3, ...'
    Write-Host ''
    if ($TryBrowser) {
        Write-Host 'Mode: the CLI will try to open a browser (usually does nothing inside Docker).'
    } else {
        Write-Host 'Steps:'
        Write-Host '  1. The CLI prints a login URL below. Open it in your Windows browser.'
        Write-Host '  2. Sign in with the account you want to add and approve access.'
        Write-Host "  3. The browser is redirected to http://localhost:$CallbackPort/... and the login completes."
        Write-Host "     If that page fails to load, copy the full redirect URL from the address bar,"
        Write-Host "     try 127.0.0.1 instead of localhost, or paste the URL into the CLI if it asks."
    }
    if ($ExtraNote) { Write-Host $ExtraNote }
    Write-Host ''

    $cliArgs = @('exec', $script:ServiceName, $script:ContainerBinary, $LoginFlag)
    if (-not $TryBrowser) { $cliArgs += '--no-browser' }
    Write-Host ('> docker compose ' + ($cliArgs -join ' ')) -ForegroundColor DarkGray
    Invoke-Compose @cliArgs
    $exit = $LASTEXITCODE

    if ($exit -ne 0) {
        Write-Err "Login command exited with code $exit."
        Write-Host 'See docs\OPERATOR_RUNBOOK.md -> "Troubleshooting OAuth on Windows Docker".'
        exit $exit
    }

    $after = @()
    if (Test-Path -LiteralPath $authDir) {
        $after = @(Get-ChildItem -LiteralPath $authDir -Filter '*.json' -File | ForEach-Object { $_.Name })
    }
    $added = @($after | Where-Object { $before -notcontains $_ })
    Write-Host ''
    if ($added.Count -gt 0) {
        Write-Ok "New credential file(s) in ${authDir}:"
        $added | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Warn "No new *.json appeared in $authDir (re-login of an existing account overwrites its file)."
    }

    if ($RestartAfter) {
        Write-Info 'Restarting cliproxy so it reloads credentials...'
        Invoke-Compose restart $script:ServiceName
    } else {
        Write-Host 'The proxy normally hot-reloads auths/. If the new account is missing from status,'
        Write-Host '  run: docker compose restart cliproxy   (Docker Desktop bind mounts can miss file events)'
    }
    Write-Host 'Verify: .\scripts\status.ps1 -ManagementKey <key>'
}
