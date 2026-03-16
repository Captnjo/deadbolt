# Phase 2: Agent API Bridge - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Expose the existing Rust axum HTTP server to Flutter via FRB StreamSink bridge, build the Agent API sidebar page with key management UI, and implement read-only query endpoints. The Rust agent server (routes, middleware, intent lifecycle, graceful shutdown) is already implemented in `deadbolt_core/src/agent/` — this phase is about creating the FRB bridge layer (`api/agent.rs`), Flutter providers, the Agent API landing page, and wiring everything together. Intent posting and signing prompts are Phase 3 scope.

**Requirements covered:** AGNT-01, AGNT-02, AGNT-10, AGNT-11, AGNT-12, AGNT-13, AGNT-14, AGNT-15, INFR-05, INFR-08

</domain>

<decisions>
## Implementation Decisions

### Server Lifecycle
- Auto-start if previously enabled — if user had the server running when they last closed the app, it starts automatically on next launch; off by default for first-time users
- Server toggle lives on the Agent API landing page (not Settings)
- Port binding uses SO_REUSEADDR to reclaim port from TIME_WAIT state after crash recovery; if port is truly in use by another process, show error
- Server errors surface as inline status on the Agent API page (red indicator + error message), no popups or toasts
- Server status indicator: green "Running on :9876" / red "Error: [message]" / gray "Stopped"

### API Key Management UX
- Keys are masked by default (db_••••x7f2) but revealable with auth challenge (app password)
- Optional user-defined labels at creation (e.g., "Claude agent", "Trading bot"); blank defaults to "API Key 1", "API Key 2", etc.
- Soft limit of 10 keys
- Revocation: swipe-to-delete on key row, then confirm dialog, requires auth challenge (per Phase 1 decision: create/delete API key requires password)
- Key creation also requires auth challenge
- Full key shown once at creation in a copyable dialog; afterward, masked unless user reveals with password

### Agent API Landing Page
- All-in-one dashboard: server toggle + status at top, API keys list in middle, curl test section at bottom — single scrollable page, no sub-navigation
- Empty state (no keys): guided setup with explanation text ("Connect AI agents to your wallet. They can query balances, request transactions, and more.") and prominent "Create Your First Key" button; server toggle visible but disabled until a key exists
- Quick Test section: dropdown selector with all available endpoints (/health, /wallet, /balance, /tokens, /price, /history); selecting one generates the full curl command with the user's real bearer token; copy button
- Sidebar position: after Contacts, before Settings (Dashboard → History → Contacts → Agent API → Settings)

### Query Endpoint Responses
- /wallet — returns wallet address (existing)
- /balance — SOL balance + all SPL token balances with mint addresses + USD values for each (using existing Helius/Jupiter price data)
- /tokens — SPL token list with balances, mint addresses, metadata
- /price?mints=... — dedicated endpoint returning current USD prices for requested mints; separate from /balance so agents can check prices without exposing holdings
- /history — last 20 transactions by default; supports ?limit=N (max 100) and ?before=signature for cursor-based pagination; uses existing Helius enriched history
- /health — existing health check (status, version)
- No NFT endpoint in Phase 2 — defer to later if agents need it
- All query endpoints require valid bearer token but no user approval

### Claude's Discretion
- StreamSink event format and DTO structure for Rust→Dart bridge
- FRB bridge singleton pattern (can follow existing OnceLock<RwLock<>> from wallet.rs)
- Exact Agent API page layout spacing and styling (follow existing brand theme)
- curl command formatting and which key is pre-selected in the dropdown
- Whether /tokens and /balance share underlying data fetch or call separately
- Error response JSON structure for query endpoints

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Rust Agent Server (existing — to be bridged)
- `rust/deadbolt_core/src/agent/server.rs` — AgentServer with start/stop, AppState, routes (/health, /intent, /intent/{id}/status, /wallet), graceful shutdown via oneshot channel, intent_sender mpsc channel
- `rust/deadbolt_core/src/agent/auth.rs` — Bearer token middleware with constant_time_eq validation
- `rust/deadbolt_core/src/agent/guardrails.rs` — GuardrailsEngine for rate-limiting and whitelisting
- `rust/deadbolt_core/src/agent/intent.rs` — Intent/IntentType/IntentStatus types and lifecycle
- `rust/deadbolt_core/src/agent/mod.rs` — Module exports
- `rust/deadbolt_core/src/models/config.rs` — AppConfig with api_tokens Vec<String>, persisted to ~/.deadbolt/config.json with 0o600 permissions

### FRB Bridge (pattern to follow)
- `rust/deadbolt_bridge/src/api/wallet.rs` — OnceLock<RwLock<WalletManager>> singleton pattern, async FRB functions
- `rust/deadbolt_bridge/src/api/auth.rs` — Password hashing, app lock state FFI functions
- `rust/deadbolt_bridge/src/api/mod.rs` — Module registration (add agent module here)
- `rust/deadbolt_bridge/Cargo.toml` — FRB 2.11.1, StreamSink support via SseCodec

### Flutter Integration Points
- `lib/shared/app_shell.dart` — NavigationRail with 4 destinations (add 5th for Agent API)
- `lib/features/settings/settings_screen.dart` — Settings screen structure (may need Agent API link)
- `lib/providers/api_keys_provider.dart` — Existing API key storage pattern (SharedPreferences) for reference
- `lib/theme/brand_theme.dart` — Solar Flare orange, Onyx Black, text styles

### Axum & Dependencies
- `rust/deadbolt_core/Cargo.toml` — axum 0.8, tokio, tower, tower-http 0.6, uuid, constant_time_eq, serde

### Research & Architecture
- `.planning/research/PITFALLS.md` — Port binding TIME_WAIT issue, SO_REUSEADDR recommendation
- `.planning/research/ARCHITECTURE.md` — Auth layer design, FRB bridge patterns

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AgentServer` in server.rs: Full HTTP server with start/stop, route handlers, intent lifecycle — needs bridge exposure only
- `AppConfig` in config.rs: API token persistence with file-level encryption permissions — reuse for key storage
- `OnceLock<RwLock<>>` singleton pattern from wallet.rs: Exact pattern needed for AgentServer bridge singleton
- `brand_theme.dart`: All colors/styles for the new Agent API page
- `SecuritySettingsSection` / `showAuthChallengeDialog`: Auth challenge pattern established in Phase 1 — reuse for key create/delete/reveal

### Established Patterns
- Riverpod Notifier/NotifierProvider for all state management
- GoRouter for navigation — add /agent-api route
- SharedPreferences for non-sensitive settings (server enabled state can go here)
- FRB async functions for Rust↔Dart communication
- Axum 0.8 route syntax with curly brace path params `{id}`

### Integration Points
- `app_shell.dart` NavigationRail: Add 5th destination between Contacts and Settings
- `api/mod.rs` in deadbolt_bridge: Register new agent module
- `AppState.intent_sender`: mpsc channel already exists for streaming intents to Flutter via StreamSink
- `WalletManager`: Balance and token data already accessible — query endpoints can read from existing managers
- Helius API: Already integrated for enriched transaction history and token metadata

</code_context>

<specifics>
## Specific Ideas

- All-in-one dashboard layout inspired by Stripe's API key management — clean, functional, everything visible at once
- Guided empty state should make agents feel accessible, not developer-only — "Connect AI agents to your wallet" framing
- Server toggle disabled until at least one key exists — prevents running a server with no way to auth
- Curl command dropdown should auto-select the first key if only one exists; if multiple, let user pick which key to use

</specifics>

<deferred>
## Deferred Ideas

- NFT query endpoint — add later if agents need it
- Batch intents — AGNT-V2-01, deferred to v2
- Long-poll /subscribe endpoint — AGNT-V2-02, deferred to v2
- Remote bridge service — AGNT-V2-03, deferred to v2
- Intent posting (POST /intent) and signing prompt UI — Phase 3 scope

</deferred>

---

*Phase: 02-agent-api-bridge*
*Context gathered: 2026-03-16*
