<#
.SYNOPSIS
  Add one Claude (Anthropic OAuth) account to RahBaz. Run once per account.

.DESCRIPTION
  Runs `docker compose exec cliproxy /CLIProxyAPI/CLIProxyAPI --claude-login --no-browser`.
  OAuth callback port: 54545 (published on 127.0.0.1 by compose.yaml).

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

Invoke-ProviderLogin -Provider 'Claude' -LoginFlag '--claude-login' -CallbackPort 54545 `
    -TryBrowser:$TryBrowser -RestartAfter:$RestartAfter
