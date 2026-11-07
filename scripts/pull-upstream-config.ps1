<#
.SYNOPSIS
  Optional helper: download upstream CLIProxyAPI's config.example.yaml for reference and
  compare its top-level sections with RahBaz's config.

.DESCRIPTION
  Use this when config\config.example.yaml looks insufficient or upstream changed its
  layout (upstream moved to a grouped "v8" layout: server, management, access, oauth,
  routing, requests, upstream, observability, plugins).

  This script NEVER modifies config.yaml or config.example.yaml. It writes the upstream
  file to config\upstream.config.example.yaml (gitignored) and prints a section diff.

  Manual refresh workflow:
    1. .\scripts\pull-upstream-config.ps1
    2. Read config\upstream.config.example.yaml; copy only the keys you need into
       config\config.yaml (and the commented, secret-free version into config.example.yaml).
    3. Keep RahBaz invariants: routing.strategy=weighted-round-robin, session-affinity on,
       access.api-keys set, management.allow-remote=false.
    4. docker compose restart cliproxy
    5. .\scripts\status.ps1

  Upgrading the image itself:  .\scripts\up.ps1 -Pull

.PARAMETER Ref
  Git ref (branch, tag, commit) of router-for-me/CLIProxyAPI. Default: main.
.PARAMETER OutFile
  Where to save the upstream example. Default: config\upstream.config.example.yaml.
#>
[CmdletBinding()]
param(
    [string]$Ref = 'main',
    [string]$OutFile
)

. "$PSScriptRoot\_common.ps1"

if (-not $OutFile) { $OutFile = Join-Path $script:RepoRoot 'config\upstream.config.example.yaml' }
$url = "https://raw.githubusercontent.com/router-for-me/CLIProxyAPI/$Ref/config.example.yaml"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

Write-Info "Downloading $url"
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $OutFile
Write-Ok "Saved $OutFile"

function Get-TopLevelKeys([string]$Path) {
    $keys = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^([A-Za-z][A-Za-z0-9_-]*):') { $keys += $Matches[1] }
    }
    return @($keys | Select-Object -Unique)
}

$ours = Join-Path $script:RepoRoot 'config\config.example.yaml'
$upstreamKeys = Get-TopLevelKeys $OutFile
$ourKeys = Get-TopLevelKeys $ours

Write-Host ''
Write-Info 'Top-level sections'
Write-Host ('  upstream : ' + ($upstreamKeys -join ', '))
Write-Host ('  RahBaz   : ' + ($ourKeys -join ', '))

$missing = @($upstreamKeys | Where-Object { $ourKeys -notcontains $_ })
$extra = @($ourKeys | Where-Object { $upstreamKeys -notcontains $_ })
if ($missing.Count) { Write-Warn ('Upstream sections not in RahBaz example (ok if unused): ' + ($missing -join ', ')) }
if ($extra.Count)   { Write-Warn ('RahBaz sections unknown upstream (check for renamed/legacy keys): ' + ($extra -join ', ')) }
if (-not $missing.Count -and -not $extra.Count) { Write-Ok 'Section sets match.' }

Write-Host ''
Write-Host 'Next: review the file, copy what you need into config\config.yaml, then:'
Write-Host '  docker compose restart cliproxy ; .\scripts\status.ps1'
