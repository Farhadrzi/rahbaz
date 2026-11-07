<#
.SYNOPSIS
  Add one Antigravity (Google OAuth) account to RahBaz. Run once per account.

.DESCRIPTION
  Runs `docker compose exec cliproxy /CLIProxyAPI/CLIProxyAPI --antigravity-login --no-browser`.
  OAuth callback port: 51121 (published on 127.0.0.1 by compose.yaml).
  Antigravity models are consumed through Claude/Codex T3 instances pointed at RahBaz;
  the native T3 Antigravity provider bypasses the gateway.

.PARAMETER TryBrowser
  Omit --no-browser (the CLI will try to open a browser; normally pointless inside Docker).
.PARAMETER RestartAfter
  Restart cliproxy afterwards so it reloads credentials.
#>
[CmdletBinding()]
param(
    [switch]$TryBrowser,
    [switch]$RestartAfter
)

. "$PSScriptRoot\_common.ps1"

Invoke-ProviderLogin -Provider 'Antigravity' -LoginFlag '--antigravity-login' -CallbackPort 51121 `
    -TryBrowser:$TryBrowser -RestartAfter:$RestartAfter `
    -ExtraNote 'Note: make sure nothing else on this PC is listening on 51121 during login.'
