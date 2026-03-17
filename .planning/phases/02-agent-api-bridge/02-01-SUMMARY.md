---
phase: 02-agent-api-bridge
plan: 01
subsystem: api
tags: [rust, axum, socket2, serde, agent-api, wallet-data, guardrails]

# Dependency graph
requires:
  - phase: 01-auth-system
    provides: AppState, auth_middleware, AgentServer, constant_time_eq token validation

provides:
  - WalletDataSnapshot struct with sol_balance, sol_usd, tokens, history, prices
  - TokenSnapshot and HistoryEntry types for cached wallet data
  - /balance, /tokens, /price, /history query handlers behind auth middleware
  - update_wallet_data() method on AgentServer for FRB bridge to push data
  - SO_REUSEADDR binding via socket2 replacing direct TcpListener::bind
  - AppConfig.api_key_labels HashMap<String, String> with serde(default) for backwards compat

affects: [02-agent-api-bridge, flutter-frb-bridge, agent-integration]

# Tech tracking
tech-stack:
  added: [socket2 = "0.5"]
  patterns:
    - RwLock<WalletDataSnapshot> in AppState for lock-free concurrent reads
    - socket2 SO_REUSEADDR pattern for crash-restart port binding
    - serde(default) HashMap field for backwards-compatible config extension

key-files:
  created: []
  modified:
    - rust/deadbolt_core/src/agent/server.rs
    - rust/deadbolt_core/src/agent/auth.rs
    - rust/deadbolt_core/src/models/config.rs
    - rust/deadbolt_core/Cargo.toml

key-decisions:
  - "RwLock (not Mutex) for wallet_data — readers (agent queries) vastly outnumber writers (FRB bridge refresh), RwLock allows concurrent reads"
  - "update_wallet_data() is on AgentServer not AppState — keeps the public API surface on the handle object, matching existing approve/reject_intent pattern"
  - "api_key_labels is a separate HashMap from api_tokens — tokens stay as Vec<String> for backwards compat; labels are opt-in metadata"

patterns-established:
  - "SO_REUSEADDR pattern: Socket::new + set_reuse_address(true) + set_nonblocking(true) + bind + listen + TcpListener::from_std"
  - "Snapshot cache pattern: RwLock<Snapshot> in AppState, update via handle method, read in handlers with read().unwrap()"

requirements-completed: [AGNT-01, AGNT-02, AGNT-10, INFR-05, INFR-08]

# Metrics
duration: 3min
completed: 2026-03-17
---

# Phase 2 Plan 01: Agent API Bridge - Query Endpoints Summary

**Axum agent server extended with WalletDataSnapshot cache, five query handlers (/balance /tokens /price /history), SO_REUSEADDR socket2 binding, and AppConfig api_key_labels for Flutter UI key management**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-17T05:34:23Z
- **Completed:** 2026-03-17T05:37:17Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- WalletDataSnapshot struct with TokenSnapshot and HistoryEntry types; RwLock in AppState; update_wallet_data() on AgentServer
- Four new query handlers (/balance, /tokens, /price, /history) registered in protected router behind auth_middleware
- SO_REUSEADDR via socket2 replaces direct TcpListener::bind — server survives crash-restart without "address in use"
- AppConfig.api_key_labels HashMap with serde(default) for backwards-compatible API key labeling in Flutter UI

## Task Commits

Each task was committed atomically:

1. **Task 1: WalletDataSnapshot, query handlers, SO_REUSEADDR** - `cee3ddc` (feat)
2. **Task 2: api_key_labels on AppConfig** - `6acf028` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `rust/deadbolt_core/src/agent/server.rs` - WalletDataSnapshot/TokenSnapshot/HistoryEntry structs, wallet_data RwLock in AppState, update_wallet_data(), SO_REUSEADDR socket2 binding, /balance /tokens /price /history handlers, 3 new tests
- `rust/deadbolt_core/src/agent/auth.rs` - test make_app helper updated with wallet_data field so auth tests compile
- `rust/deadbolt_core/src/models/config.rs` - api_key_labels HashMap field with serde(default), Default impl updated, 2 new tests
- `rust/deadbolt_core/Cargo.toml` - socket2 = "0.5" dependency added

## Decisions Made
- Used `RwLock` for `wallet_data` in AppState — agent query handlers read frequently, FRB bridge writes rarely; RwLock allows concurrent reads where Mutex would serialize them
- `update_wallet_data()` placed on `AgentServer` handle (not `AppState` directly) — consistent with existing `approve_intent`, `reject_intent` pattern; callers interact with the handle, not the internal state
- `api_key_labels` is a separate `HashMap<String, String>` rather than a parallel Vec or struct alongside `api_tokens` — cleanest backwards-compatible extension; old config files missing the key default to empty map via `serde(default)`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed borrow-checker error in test_update_wallet_data**
- **Found during:** Task 1 (server.rs tests compilation)
- **Issue:** `let data = server.state().wallet_data.read().unwrap()` held an immutable borrow across `server.stop()` (mutable borrow), causing E0502
- **Fix:** Wrapped the data assertions in a `{ }` block so the RwLockReadGuard drops before `server.stop()` is called
- **Files modified:** rust/deadbolt_core/src/agent/server.rs
- **Verification:** `cargo test -- agent` exits 0 with 18 tests passing
- **Committed in:** cee3ddc (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Borrow-checker fix is required for correctness. No scope creep.

## Issues Encountered
- Plan-specified test code had an implicit borrow-checker issue (RwLockReadGuard held across `server.stop()` mutable borrow). Resolved by scoping the guard within a block.

## User Setup Required
None - no external service configuration required.

## Self-Check: PASSED

All files verified present. Both task commits (cee3ddc, 6acf028) confirmed in git log.

## Next Phase Readiness
- WalletDataSnapshot cache is ready; FRB bridge (02-02) can call `server.update_wallet_data(snapshot)` when wallet data refreshes
- All five query endpoints (/balance, /tokens, /price, /history, /wallet) are live and protected by auth_middleware
- api_key_labels is ready for Flutter UI to read/write key labels alongside tokens
- INFR-05 confirmed: axum 0.8 `{id}` syntax already in use at `/intent/{id}/status`

---
*Phase: 02-agent-api-bridge*
*Completed: 2026-03-17*
