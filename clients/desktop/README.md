# RahBaz desktop (stub)

Planned: a small Windows tray app (Linux/macOS later) that wraps the RahBaz stack. Not built yet.

## Planned features

- Start / stop the stack (`docker compose up -d` / `down` via `compose.yaml`)
- Status icon driven by `http://127.0.0.1:8791/health` and gateway reachability on `:8317`
- Toast notification whenever the switch-notifier emits an SSE event on `http://127.0.0.1:8791/events` (credential/account rotation due to quota, auth, or errors)
- Shortcuts to the login scripts and `logs/switches.jsonl`

## Available now

`watch-switches.ps1` prints switch events from the SSE stream to the console:

```powershell
.\clients\desktop\watch-switches.ps1
.\clients\desktop\watch-switches.ps1 -Url http://127.0.0.1:8791/events -Toast
```

`-Toast` shows a best-effort Windows balloon notification per event. It reconnects automatically if the notifier restarts.
