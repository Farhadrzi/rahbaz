#Requires -Version 5.1
<#
.SYNOPSIS
  Print the RahBaz Hub model catalog (OpenRouter-style GET /v1/models).
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8317',
    [string]$ApiKey
)

. "$PSScriptRoot\_common.ps1"

if (-not $ApiKey) { $ApiKey = Get-GatewayKey }
if (-not $ApiKey) {
    Write-Err 'No gateway API key. Set config/config.yaml access.api-keys or pass -ApiKey.'
    exit 1
}

$url = $BaseUrl.TrimEnd('/') + '/v1/models'
$probe = Invoke-Probe -Url $url -Headers @{ Authorization = "Bearer $ApiKey" } -TimeoutSec 10
if (-not $probe.Ok) {
    Write-Err "Hub catalog failed: HTTP $($probe.Status) $($probe.Error)"
    Write-Host 'Start the Hub with .\scripts\up.ps1 and log in at least one account.'
    exit 2
}

try {
    $json = $probe.Body | ConvertFrom-Json
} catch {
    Write-Err 'Hub returned non-JSON body.'
    Write-Host $probe.Body
    exit 2
}

$models = @()
if ($json.data) { $models = @($json.data) }
elseif ($json.models) { $models = @($json.models) }

Write-Info "RahBaz Hub catalog @ $url"
Write-Host "Models: $($models.Count)"
Write-Host ''
if ($models.Count -eq 0) {
    Write-Warn 'Catalog is empty. Run scripts\login-*.ps1 for each account, then retry.'
    exit 0
}

$models |
    ForEach-Object {
        $id = $_.id
        if (-not $id) { $id = $_.name }
        $owned = $_.owned_by
        if ($owned) { "{0,-48} {1}" -f $id, $owned } else { $id }
    } |
    Sort-Object
