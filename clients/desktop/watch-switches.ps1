#Requires -Version 5.1
<#
.SYNOPSIS
  Print RahBaz switch events from the notifier SSE stream.
.PARAMETER Url
  SSE endpoint. Defaults to the local notifier.
.PARAMETER Toast
  Also show a best-effort Windows balloon notification per event.
.PARAMETER RetrySeconds
  Delay before reconnecting after the stream drops.
#>
[CmdletBinding()]
param(
    [string]$Url = 'http://127.0.0.1:8791/events',
    [switch]$Toast,
    [int]$RetrySeconds = 3
)

$ErrorActionPreference = 'Stop'

function Show-Toast([string]$Title, [string]$Text) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.BalloonTipTitle = $Title
        $n.BalloonTipText = $Text
        $n.Visible = $true
        $n.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 200
        $n.Dispose()
    } catch {
        Write-Warning "Toast failed: $($_.Exception.Message)"
    }
}

function Watch-Stream {
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    try {
        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Url)
        $req.Headers.Accept.ParseAdd('text/event-stream')
        $resp = $client.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $resp.EnsureSuccessStatusCode() | Out-Null
        Write-Host "[watch-switches] connected to $Url"
        $reader = New-Object System.IO.StreamReader($resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult())
        $event = 'message'
        $data = New-Object System.Collections.Generic.List[string]
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($line -eq '') {
                if ($data.Count -gt 0) {
                    $payload = $data -join "`n"
                    Write-Host ("[{0}] {1}: {2}" -f (Get-Date -Format 'HH:mm:ss'), $event, $payload)
                    if ($Toast) { Show-Toast "RahBaz: $event" $payload }
                }
                $event = 'message'
                $data.Clear()
            } elseif ($line.StartsWith(':')) {
                continue  # comment / keepalive
            } elseif ($line.StartsWith('event:')) {
                $event = $line.Substring(6).Trim()
            } elseif ($line.StartsWith('data:')) {
                $data.Add($line.Substring(5).TrimStart())
            }
        }
    } finally {
        $client.Dispose()
    }
}

Write-Host "[watch-switches] Ctrl+C to stop"
while ($true) {
    try {
        Watch-Stream
        Write-Warning "Stream closed."
    } catch {
        Write-Warning "Stream error: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $RetrySeconds
}
