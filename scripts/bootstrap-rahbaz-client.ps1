#Requires -Version 5.1
<#
.SYNOPSIS
  Ensure the RahBaz Client (T3 fork) checkout exists and print next steps.
#>
[CmdletBinding()]
param(
    [switch]$CloneIfMissing
)

. "$PSScriptRoot\_common.ps1"
$root = $script:RepoRoot
$client = Join-Path $root 'clients\rahbaz-client'

if (-not (Test-Path -LiteralPath (Join-Path $client '.git'))) {
    if (-not $CloneIfMissing) {
        Write-Err "RahBaz Client checkout missing at $client"
        Write-Host 'Re-run with -CloneIfMissing to shallow-clone pingdotgg/t3code.'
        exit 1
    }
    Write-Info 'Cloning T3 Code (shallow) into clients\rahbaz-client ...'
    git clone --depth 1 --single-branch https://github.com/pingdotgg/t3code.git $client
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
}

Write-Ok "Client checkout: $client"
if (Test-Path -LiteralPath (Join-Path $client 'README.rahbaz.md')) {
    Write-Host 'See clients\rahbaz-client\README.rahbaz.md for RahBaz-specific run steps.'
} else {
    Write-Warn 'README.rahbaz.md not written yet (single-provider patch still landing).'
    Write-Host 'Upstream build notes: clients\rahbaz-client\README.md (requires vp).'
}

Write-Host ''
Write-Info 'Hub must be up first:'
Write-Host '  .\scripts\up.ps1'
Write-Host '  .\scripts\login-*.ps1'
Write-Host '  .\scripts\list-models.ps1'
