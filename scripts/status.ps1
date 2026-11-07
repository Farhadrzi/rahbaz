<#
.SYNOPSIS
  Show container state and probe the gateway (and notifier, and credentials if a management key is given).

.PARAMETER ManagementKey
  Plaintext management.secret-key. Falls back to $env:RAHBAZ_MANAGEMENT_KEY.
  Without it the per-provider credential summary is skipped.
#>
[CmdletBinding()]
param(
    [string]$ManagementKey = $env:RAHBAZ_MANAGEMENT_KEY
)

. "$PSScriptRoot\_common.ps1"

Assert-DockerReady

Write-Info '== docker compose ps =='
Invoke-Compose ps
Write-Host ''

$failed = $false

# 1. Gateway liveness (no key needed)
Write-Info '== Gateway =='
$root = Invoke-Probe "$($script:ApiBase)/"
if ($root.Ok) {
    Write-Ok "GET /           HTTP $($root.Status)  gateway is up"
} elseif ($root.Status -gt 0) {
    Write-Warn "GET /           HTTP $($root.Status)  gateway answered with an error"
} else {
    Write-Err "GET /           no response: $($root.Error)"
    $failed = $true
}

# 2. Authenticated model list (proves the gateway key works and models are loaded)
$key = Get-GatewayKey
if ($key -and -not $failed) {
    $models = Invoke-Probe "$($script:ApiBase)/v1/models" -Headers @{ Authorization = "Bearer $key" }
    if ($models.Ok) {
        $count = '?'
        try { $count = @(($models.Body | ConvertFrom-Json).data).Count } catch { }
        Write-Ok "GET /v1/models  HTTP $($models.Status)  $count model(s) visible with the gateway key"
        if ($count -eq 0) { Write-Warn '  No models yet - log in at least one account (scripts\login-*.ps1).' }
    } elseif ($models.Status -eq 401) {
        Write-Err 'GET /v1/models  HTTP 401  gateway key in config.yaml was rejected'
        $failed = $true
    } else {
        Write-Warn "GET /v1/models  failed: HTTP $($models.Status) $($models.Error)"
    }
} elseif (-not $key) {
    Write-Warn 'No api-keys entry found in config.yaml - skipping /v1/models check.'
}

if (Test-ConfigHasPlaceholders) {
    Write-Warn 'config.yaml still has "change-me-*" placeholder keys.'
}

# 3. Credentials per provider via management API
Write-Host ''
Write-Info '== Credentials (management API) =='
if ($ManagementKey -and ($root.Ok -or $root.Status -gt 0)) {
    $cred = Invoke-Probe "$($script:ApiBase)/v8/management/credentials" -Headers @{ Authorization = "Bearer $ManagementKey" }
    if ($cred.Ok) {
        try {
            $files = @(($cred.Body | ConvertFrom-Json).files)
            if ($files.Count -eq 0) {
                Write-Warn 'No credentials loaded.'
            } else {
                $files | Group-Object provider | Sort-Object Name | ForEach-Object {
                    $disabled = @($_.Group | Where-Object { $_.disabled -eq $true }).Count
                    $line = '{0,-14} total={1}  disabled={2}' -f $_.Name, $_.Count, $disabled
                    Write-Host "  $line"
                }
            }
        } catch {
            Write-Warn "Could not parse credentials response: $($_.Exception.Message)"
        }
    } elseif ($cred.Status -eq 404) {
        Write-Warn 'HTTP 404: management API is off. Set management.secret-key in config.yaml and restart.'
    } elseif ($cred.Status -eq 401) {
        Write-Err 'HTTP 401: management key rejected.'
    } else {
        Write-Warn "Credentials call failed: HTTP $($cred.Status) $($cred.Error)"
    }
} else {
    Write-Host '  Skipped. Pass -ManagementKey <key> (or set $env:RAHBAZ_MANAGEMENT_KEY) for a per-provider summary.'
    $authDir = Get-AuthDir
    if (Test-Path -LiteralPath $authDir) {
        $n = @(Get-ChildItem -LiteralPath $authDir -Filter '*.json' -File).Count
        Write-Host "  auths\ currently holds $n credential file(s)."
    }
}

# 4. Notifier (optional sidecar)
Write-Host ''
Write-Info '== switch-notifier =='
$n = Invoke-Probe "$($script:NotifierBase)/status"
if ($n.Ok) {
    Write-Ok "GET /status     HTTP $($n.Status)"
    if ($n.Body) { Write-Host "  $($n.Body.Trim())" }
} else {
    Write-Warn "Not reachable on $($script:NotifierBase) (may not be built/started yet): $($n.Error)"
}

if ($failed) { exit 1 }
