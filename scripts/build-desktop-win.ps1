#Requires -Version 5.1
<#
.SYNOPSIS
  Build the RahBaz Windows NSIS installer from the T3-fork client.
#>
[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')]
    [string]$Arch = 'x64',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$client = Join-Path $root 'clients\rahbaz-client'
$out = Join-Path $root 'release\desktop\win'

if (-not (Test-Path -LiteralPath (Join-Path $client 'package.json'))) {
    throw "RahBaz Client missing at $client. Run scripts\bootstrap-rahbaz-client.ps1 -CloneIfMissing"
}

$envPs1 = Join-Path $env:APPDATA 'vite-plus\env.ps1'
if (Test-Path -LiteralPath $envPs1) {
    . $envPs1
} else {
    Write-Warning 'vite-plus env.ps1 not found; ensure vp/node are on PATH'
}

$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
    [System.Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path

New-Item -ItemType Directory -Force -Path $out | Out-Null
Set-Location -LiteralPath $client

$buildArgs = @(
    'scripts/build-desktop-artifact.ts',
    '--platform', 'win',
    '--target', 'nsis',
    '--arch', $Arch,
    '--verbose',
    '--output-dir', $out
)
if ($SkipBuild) { $buildArgs += '--skip-build' }

Write-Host "Building RahBaz Windows desktop ($Arch) -> $out"
& node @buildArgs
if ($LASTEXITCODE -ne 0) { throw "Desktop build failed with exit $LASTEXITCODE" }

Write-Host ''
Write-Host "Done. Installers:"
Get-ChildItem -LiteralPath $out -File | ForEach-Object { Write-Host "  $($_.FullName)" }
