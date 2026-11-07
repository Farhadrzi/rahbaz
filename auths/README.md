# auths/

This directory is the Docker volume that holds **provider OAuth credentials**. compose.yaml mounts it into the proxy container:

```
./auths  ->  /root/.cli-proxy-api   (config: oauth.auth-dir: "~/.cli-proxy-api")
```

- One `*.json` file per logged-in account (Claude, Codex, Antigravity, ...), created by `scripts\login-*.ps1`.
- Files contain **refresh tokens**. Treat them like passwords: never commit, paste, or share them.
- Everything here except this README is gitignored.
- Surviving `docker compose down` / `restart` is the point; deleting a file removes that account from the pool.
- Optional per-account routing weight: add `"weight": N` at the top level of a file (`0` drains the account). See `docs/OPERATOR_RUNBOOK.md`.
- Back up with the commands in `docs/OPERATOR_RUNBOOK.md` (encrypt the archive).
