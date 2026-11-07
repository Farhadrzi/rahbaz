<#
.SYNOPSIS
  Add one Codex (OpenAI / ChatGPT OAuth) account to RahBaz. Run once per account.

.DESCRIPTION
  Runs `docker compose exec cliproxy /CLIProxyAPI/CLIProxyAPI --codex-login --no-browser`.
  OAuth callback port: 1455 (published on 127.0.0.1 by compose.yaml).
  Make sure no local Codex CLI login flow is running at the same time (it also uses 1455).

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

Invoke-ProviderLogin -Provider 'Codex' -LoginFlag '--codex-login' -CallbackPort 1455 `
    -TryBrowser:$TryBrowser -RestartAfter:$RestartAfter `
    -ExtraNote 'Note: port 1455 is also used by the native Codex CLI login; do not run both at once.'
