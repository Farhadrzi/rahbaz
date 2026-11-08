#Requires -Version 5.1
<#
.SYNOPSIS
  Verify T3 presets target only RahBaz (127.0.0.1:8317) and the gateway is reachable.
.DESCRIPTION
  Exit codes: 0 = OK, 1 = preset drift (or missing preset), 2 = gateway unreachable (with -RequireGateway).
  Preset drift always wins over reachability failures.
.PARAMETER RequireGateway
  Treat an unreachable gateway as a failure (exit 2). Default: warn only.
#>
[CmdletBinding()]
param(
    [switch]$RequireGateway,
    [string]$GatewayHost = '127.0.0.1',
    [int]$GatewayPort = 8317
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$allowedHostPort = "${GatewayHost}:${GatewayPort}"
$drift = New-Object System.Collections.Generic.List[string]

function Pass($m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red }

# ---- 1. Preset drift -------------------------------------------------------
$presets = @(
    @{ Path = 'clients\t3-presets\claude.env.example'; Required = @('ANTHROPIC_BASE_URL=http://127.0.0.1:8317', 'ANTHROPIC_AUTH_TOKEN=', 'ANTHROPIC_API_KEY=') },
    @{ Path = 'clients\t3-presets\codex.rahbaz.toml';  Required = @('model_provider = "rahbaz"', 'base_url = "http://127.0.0.1:8317/v1"', 'env_key = "RAHBAZ_API_KEY"', 'wire_api = "responses"') }
)

foreach ($p in $presets) {
    $file = Join-Path $root $p.Path
    if (-not (Test-Path -LiteralPath $file)) {
        Fail "missing preset: $($p.Path)"
        $drift.Add("missing $($p.Path)")
        continue
    }
    # Strip comment lines so documentation text can't trigger or mask checks.
    $lines = Get-Content -LiteralPath $file | Where-Object { $_ -notmatch '^\s*#' }
    $text = $lines -join "`n"
    $bad = $false

    foreach ($req in $p.Required) {
        if ($text -notlike "*$req*") {
            Fail "$($p.Path): missing expected line '$req'"
            $drift.Add("$($p.Path) missing '$req'")
            $bad = $true
        }
    }

    # Every URL must be http://127.0.0.1:8317[/...]
    foreach ($m in [regex]::Matches($text, '(?i)\b[a-z][a-z0-9+.-]*://([^\s"''/]+)')) {
        $authority = $m.Groups[1].Value
        if ($authority -ne $allowedHostPort) {
            Fail "$($p.Path): foreign host '$authority' (only $allowedHostPort allowed)"
            $drift.Add("$($p.Path) foreign host $authority")
            $bad = $true
        }
    }
    # Catch bare hostnames of common upstreams even without a scheme.
    if ($text -match '(?i)\b(api\.anthropic\.com|api\.openai\.com|chatgpt\.com|googleapis\.com|x\.ai)\b') {
        Fail "$($p.Path): direct upstream host '$($Matches[1])'"
        $drift.Add("$($p.Path) upstream host $($Matches[1])")
        $bad = $true
    }
    # Claude key must stay empty; auth token must not hold a real-looking key.
    if ($p.Path -like '*claude.env.example') {
        if ($text -match '(?m)^\s*ANTHROPIC_API_KEY=\s*\S') {
            Fail "$($p.Path): ANTHROPIC_API_KEY must be empty"
            $drift.Add("$($p.Path) ANTHROPIC_API_KEY not empty")
            $bad = $true
        }
        if ($text -match '(?m)^\s*ANTHROPIC_AUTH_TOKEN=(?!<)\S') {
            Fail "$($p.Path): ANTHROPIC_AUTH_TOKEN looks like a real value (use a <placeholder>)"
            $drift.Add("$($p.Path) token not placeholder")
            $bad = $true
        }
    }
    if (-not $bad) { Pass "$($p.Path) targets only $allowedHostPort" }
}

# ---- 2. Gateway reachability ----------------------------------------------
$gatewayUp = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect($GatewayHost, $GatewayPort, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(2000) -and $tcp.Connected) {
        $tcp.EndConnect($iar)
        $gatewayUp = $true
    }
    $tcp.Close()
} catch { }

if ($gatewayUp) {
    Pass "gateway TCP reachable at $allowedHostPort"
    try {
        # Any HTTP response (even 401/404) proves the HTTP listener is alive.
        $r = Invoke-WebRequest -Uri "http://$allowedHostPort/" -UseBasicParsing -TimeoutSec 3
        Pass "gateway HTTP responded ($($r.StatusCode))"
    } catch {
        $resp = $_.Exception.Response
        if ($resp) { Pass "gateway HTTP responded ($([int]$resp.StatusCode))" }
        else { Warn "gateway TCP open but HTTP failed: $($_.Exception.Message)" }
    }
} elseif ($RequireGateway) {
    Fail "gateway not reachable at $allowedHostPort"
} else {
    Warn "gateway not reachable at $allowedHostPort (stack down? run scripts/up.ps1; use -RequireGateway to fail)"
}

# ---- Result ---------------------------------------------------------------
if ($drift.Count -gt 0) {
    Fail "preset drift detected ($($drift.Count) issue(s))"
    exit 1
}
if ($RequireGateway -and -not $gatewayUp) { exit 2 }
Pass "T3 presets are RahBaz-only"
exit 0
