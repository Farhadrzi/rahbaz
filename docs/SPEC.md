# RahBaz Product Spec (v0.2)

## Vision

A private, local OpenRouter: one Hub holds every subscription and model; one Client connects only to that Hub. You set model/account priority in the Hub and never think about which provider CLI is logged in.

## Goals

1. Hub exposes OpenAI-compatible `/v1/models` + chat for all pooled accounts.
2. Client (T3 fork) has exactly one provider: RahBaz.
3. Client model picker = Hub catalog.
4. Account OAuth and failover live only in the Hub.
5. Windows + Docker Desktop first.

## Non-goals (v0.2)

- Shipping mobile/remote parity on day one
- Replacing OpenCode with a from-scratch HTTP agent runtime
- Multi-tenant cloud SaaS

## Functional requirements

### Hub

- FR-H1: OAuth login for Claude, Codex, Antigravity (+ others upstream supports)
- FR-H2: `GET /v1/models` lists models from logged-in credentials
- FR-H3: Weighted routing + session affinity + quota failover
- FR-H4: Operator can set priority via weights / aliases

### Client

- FR-C1: Single visible provider `rahbaz`
- FR-C2: Fetches and displays Hub model list
- FR-C3: All turns go to Hub base URL with gateway key
- FR-C4: Startup explains how to start Hub if unreachable
- FR-C5: Stock Claude/Codex/Antigravity/Cursor/etc providers hidden or removed

## Success criteria

1. After logging accounts, `scripts/list-models.ps1` prints a non-empty catalog.
2. RahBaz Client picker matches that catalog.
3. A chat completion is served by the Hub without any direct provider login in the Client.
4. Standalone desktop installers exist for Windows (NSIS) and Linux (AppImage); macOS DMG buildable on a Mac.
