<#
.SYNOPSIS
  Stop the RahBaz stack. Credentials in auths\ and logs in logs\ are kept.
#>
[CmdletBinding()]
param(
    [switch]$RemoveOrphans
)

. "$PSScriptRoot\_common.ps1"

Assert-DockerReady

$downArgs = @('down')
if ($RemoveOrphans) { $downArgs += '--remove-orphans' }

Write-Info ('docker compose ' + ($downArgs -join ' '))
Invoke-Compose @downArgs
if ($LASTEXITCODE -ne 0) { throw "docker compose down failed (exit $LASTEXITCODE)" }

Write-Ok 'RahBaz stopped. auths\ is untouched; restart with .\scripts\up.ps1'
