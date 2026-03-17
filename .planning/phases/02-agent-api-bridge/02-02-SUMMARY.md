---
phase: 02-agent-api-bridge
plan: 02
subsystem: api
tags: [rust, frb, flutter-rust-bridge, axum, agent-server, api-keys, rand, hex]

# Dependency graph
requires:
  - phase: 02-agent-api-bridge
    plan: 01
    provides: "AgentServer, AppState, WalletDataSnapshot, TokenSnapshot, HistoryEntry in deadbolt_core"

provides:
  - "FRB bridge module rust_lib_deadbolt::api::agent exposing agent server lifecycle and API key CRUD to Flutter"
  - "start_agent_server (async), stop_agent_server (sync), is_agent_server_running (sync)"
  - "create_api_key, revoke_api_key, list_api_keys (sync), get_full_api_key, update_agent_wallet_data"
  - "OnceLock<Mutex<Option<AgentServer>>> singleton for server handle"
  - "AgentStatusEvent and ApiKeyEntry DTO types for FRB serialization"
  - "mask_token helper producing db_••••xyz format"

affects:
  - "02-agent-api-bridge plan 03+ (Flutter Dart side wiring, intent stream)"
  - "Phase 4 (guardrails UI, wallet data push)"

# Tech tracking
tech-stack:
  added:
    - "rand = 0.8 (cryptographic token generation)"
  patterns:
    - "OnceLock<Mutex<Option<AgentServer>>> singleton for server handle (parallel to wallet.rs OnceLock<RwLock<WalletManager>>)"
    - "pub async fn for server start (I/O bound), #[frb(sync)] pub fn for read-only and shutdown ops"
    - "Dual-update pattern: key CRUD writes to AppConfig on disk AND live AppState in memory"
    - "JSON string params for complex nested types (tokens/history/prices) passed through FRB"

key-files:
  created:
    - "rust/deadbolt_bridge/src/api/agent.rs"
  modified:
    - "rust/deadbolt_bridge/src/api/mod.rs"
    - "rust/deadbolt_bridge/Cargo.toml"
    - "rust/deadbolt_core/src/agent/server.rs"

key-decisions:
  - "start_agent_server is pub async fn — FRB v2 runs on tokio runtime, async is correct and avoids block_on anti-pattern"
  - "stop_agent_server is #[frb(sync)] — stop() sends oneshot signal synchronously, safe for window close hook"
  - "_intent_rx from AgentServer::start is dropped for now — Phase 3 will wire to Flutter via StreamSink for signing prompts"
  - "JSON string params for update_agent_wallet_data — FRB v2 handles simple types well, complex nested Vec<Struct> is cleaner as JSON"
  - "Deserialize added to WalletDataSnapshot/TokenSnapshot/HistoryEntry — required for serde_json::from_str in bridge, no behavioral change to server"

patterns-established:
  - "FRB async/sync split: heavy or I/O ops use pub async fn, lightweight reads use #[frb(sync)] pub fn"
  - "Dual-update pattern established for all key CRUD ops: persist to AppConfig.save() then update live server AppState if server running"
  - "Token format: db_ prefix + 32 random bytes as lowercase hex = 67-char total, verified in test_create_api_key"
  - "Soft key limit: 10 keys max enforced at create_api_key layer"

requirements-completed: [AGNT-01, AGNT-02, AGNT-11, AGNT-12, AGNT-15, INFR-08]

# Metrics
duration: 7min
completed: 2026-03-17
---

# Phase 2 Plan 02: Agent API Bridge (FRB Module) Summary

**FRB bridge agent.rs exposing AgentServer lifecycle + API key CRUD to Flutter via OnceLock singleton with dual disk/memory updates**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-17T05:40:09Z
- **Completed:** 2026-03-17T05:47:00Z
- **Tasks:** 1 of 1
- **Files modified:** 4 (1 created)

## Accomplishments
- Created `rust/deadbolt_bridge/src/api/agent.rs` with full FRB bridge for server lifecycle and key CRUD
- OnceLock singleton pattern matches wallet.rs exactly; start is async, stop/is_running/list are sync
- Dual-update pattern: create/revoke API keys persist to disk config AND update live AppState.api_tokens
- 4 unit tests verify token format (67 chars, db_ prefix, hex body, uniqueness), revoke retain logic, masking, and initial state

## Task Commits

Each task was committed atomically:

1. **Task 1: Create FRB bridge agent.rs with server lifecycle and key CRUD** - `88709ec` (feat)

**Plan metadata:** (pending — docs commit below)

## Files Created/Modified
- `rust/deadbolt_bridge/src/api/agent.rs` - FRB bridge: start/stop server, API key CRUD, wallet data update, mask_token helper
- `rust/deadbolt_bridge/src/api/mod.rs` - Added `pub mod agent`
- `rust/deadbolt_bridge/Cargo.toml` - Added `rand = "0.8"` dependency
- `rust/deadbolt_core/src/agent/server.rs` - Added `Deserialize` to WalletDataSnapshot, TokenSnapshot, HistoryEntry

## Decisions Made
- `start_agent_server` is `pub async fn` — FRB v2 runs on tokio runtime, async correct, avoids block_on anti-pattern
- `stop_agent_server` is `#[frb(sync)]` — stop() sends oneshot signal, safe for window close hook
- `_intent_rx` dropped for now — Phase 3 will wire to Flutter via StreamSink for signing prompts
- JSON string params for wallet data — FRB handles simple types well, complex nested Vec<Struct> cleaner as JSON
- `Deserialize` added to snapshot types in deadbolt_core — required by bridge deserialization, no behavioral change to server

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added Deserialize derive to WalletDataSnapshot, TokenSnapshot, HistoryEntry**
- **Found during:** Task 1 (first build attempt)
- **Issue:** Plan's `update_agent_wallet_data` uses `serde_json::from_str::<Vec<TokenSnapshot>>` and `serde_json::from_str::<Vec<HistoryEntry>>`, but both types only had `#[derive(Serialize)]` — missing `Deserialize` caused compile errors E0277
- **Fix:** Added `Deserialize` to all three snapshot types in `deadbolt_core/src/agent/server.rs`
- **Files modified:** `rust/deadbolt_core/src/agent/server.rs`
- **Verification:** `cargo build -p rust_lib_deadbolt` exits 0; all 18 deadbolt_core agent tests still pass
- **Committed in:** `88709ec` (included in Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Required for the plan's own implementation to compile. No scope creep — derives only add deserialization capability to existing types.

## Issues Encountered
None beyond the deviation above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- FRB bridge module is ready for Flutter codegen (`flutter_rust_bridge_codegen`) to generate Dart bindings
- Plan 03 can now wire the Dart side: call start/stop, create/revoke keys, update wallet data
- `_intent_rx` is dropped — Phase 3 will need to store it and wire to Flutter via StreamSink for signing prompt notifications

---
*Phase: 02-agent-api-bridge*
*Completed: 2026-03-17*
