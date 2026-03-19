---
phase: 04-guardrails-engine
plan: 01
subsystem: api
tags: [rust, guardrails, frb, flutter-rust-bridge, solana]

# Dependency graph
requires:
  - phase: 03-agent-signing-prompt
    provides: agent server infrastructure (AppState, GuardrailsEngine, AgentServer)
  - phase: 02-agent-api-bridge
    provides: WalletManager singleton, config CRUD pattern in bridge
provides:
  - GuardrailsConfig.enabled master toggle with backward-compatible default true
  - GuardrailsEngine.check() master toggle enforcement
  - check_token_whitelist() method for manual transaction checks
  - Swap intent checks output_mint (not input_mint) against token whitelist
  - FRB bridge module: get_guardrails_config, update_guardrails_config, check_manual_transaction
  - start_agent_server loads real GuardrailsConfig from AppConfig
affects:
  - 04-02 (Flutter UI guardrails settings screen consumes these bridge functions)
  - 04-03 (token whitelist UI depends on check_token_whitelist and FRB bridge)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GuardrailsConfigDto DTO pattern: only expose fields relevant to v1 UI (enabled + token_whitelist)"
    - "Two-phase update pattern: persist to disk then push to live server in update_guardrails_config"
    - "check_token_whitelist standalone method avoids creating fake Intent objects for manual tx checks"
    - "pub(crate) fn agent_server() exposes singleton to sibling bridge modules"

key-files:
  created:
    - rust/deadbolt_bridge/src/api/guardrails.rs
  modified:
    - rust/deadbolt_core/src/models/config.rs
    - rust/deadbolt_core/src/agent/guardrails.rs
    - rust/deadbolt_bridge/src/api/mod.rs
    - rust/deadbolt_bridge/src/api/agent.rs
    - rust/deadbolt_core/src/agent/auth.rs
    - rust/deadbolt_core/src/agent/server.rs

key-decisions:
  - "Swap intents check output_mint (not input_mint) -- whitelist governs tokens you acquire"
  - "Agents CANNOT bypass guardrails -- check() has no bypass parameter, type system enforces this"
  - "GuardrailsConfig.enabled defaults to true via serde(default = 'default_true') for backward compat"
  - "check_token_whitelist is separate from check() to avoid constructing fake Intent for manual txs"
  - "update_guardrails_config does a two-phase update: persist to disk then push to live server engine"

patterns-established:
  - "default_true() helper function pattern for serde bool fields that must default true"
  - "fail-open on lock poison in bridge (return None) rather than propagating internal errors to UI"

requirements-completed: [GRDL-01, GRDL-02, GRDL-04, GRDL-05, INFR-04]

# Metrics
duration: 15min
completed: 2026-03-19
---

# Phase 04 Plan 01: Guardrails Engine Summary

**Rust guardrails engine hardened with master toggle, swap output_mint fix, check_token_whitelist method, and FRB bridge module for config read/write/check from Flutter**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-19T05:06:00Z
- **Completed:** 2026-03-19T05:20:53Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Added `enabled: bool` master toggle to `GuardrailsConfig` with backward-compatible serde default true -- old config.json files without the field parse as enabled
- Fixed `intent_mint()` to return `output_mint` for Swap intents (was incorrectly checking `input_mint`) so the whitelist governs what tokens an agent can acquire
- Added `check_token_whitelist(mint)` method to `GuardrailsEngine` for standalone whitelist checks without constructing Intent objects
- Created FRB bridge module `guardrails.rs` with `get_guardrails_config`, `update_guardrails_config`, and `check_manual_transaction` -- Flutter UI can now read and write guardrails config
- Fixed `start_agent_server` to load `mgr.config().guardrails.clone()` instead of `GuardrailsConfig::default()`, so user-configured whitelists are enforced when the server starts

## Task Commits

Each task was committed atomically:

1. **Task 1: Rust core -- enabled field, swap output_mint fix, check_token_whitelist, tests** - `82c5f3d` (feat)
2. **Task 2: FRB bridge guardrails module + fix start_agent_server config** - `8ae4bcc` (feat)

**Plan metadata:** (see below)

## Files Created/Modified

- `rust/deadbolt_core/src/models/config.rs` - Added enabled field with default_true serde helper, updated Default impl, added 3 backward-compat tests
- `rust/deadbolt_core/src/agent/guardrails.rs` - Master toggle in check(), output_mint fix, check_token_whitelist method, 6 new tests
- `rust/deadbolt_bridge/src/api/guardrails.rs` - New FRB bridge module: GuardrailsConfigDto, get/update/check functions
- `rust/deadbolt_bridge/src/api/mod.rs` - Added pub mod guardrails
- `rust/deadbolt_bridge/src/api/agent.rs` - Fixed start_agent_server to load real config, made agent_server() pub(crate), removed unused GuardrailsConfig import
- `rust/deadbolt_core/src/agent/auth.rs` - Fixed pre-existing test bug (mpsc -> broadcast)
- `rust/deadbolt_core/src/agent/server.rs` - Fixed pre-existing test bug (mpsc -> broadcast)

## Decisions Made

- Swap intents check `output_mint` (not `input_mint`) -- the whitelist governs what tokens agents can acquire, and output_mint is what they're getting
- `check_token_whitelist()` is a separate public method rather than building a fake Intent -- cleaner API for the bridge, avoids constructing dummy objects
- `update_guardrails_config` does a two-phase update: persist to disk first, then push to live server engine -- same pattern as `create_api_key`
- `agent_server()` changed to `pub(crate)` rather than `pub` -- accessible to sibling modules in same crate but not exposed to downstream crates

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing mpsc/broadcast type mismatch in test helpers**
- **Found during:** Task 1 (running cargo test after config changes)
- **Issue:** `server.rs` test (line 547) and `auth.rs` test (line 68) both used `mpsc::unbounded_channel()` to create `AppState.intent_sender`, but `AppState.intent_sender` is typed as `broadcast::Sender<Intent>`. This caused two compile errors blocking test execution.
- **Fix:** Replaced `let (tx, _rx) = mpsc::unbounded_channel()` with `let (tx, _rx) = broadcast::channel(16)` in both test helpers. Updated import in auth.rs from `tokio::sync::mpsc` to `tokio::sync::broadcast`.
- **Files modified:** `rust/deadbolt_core/src/agent/server.rs`, `rust/deadbolt_core/src/agent/auth.rs`
- **Verification:** `cargo test -p deadbolt_core --lib guardrails` and `--lib config` both pass after fix
- **Committed in:** `82c5f3d` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Pre-existing compile error blocking test execution. Fix was necessary for correctness. No scope creep.

## Issues Encountered

None beyond the pre-existing compile bug fixed above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- FRB bridge is ready: Flutter can call `get_guardrails_config()`, `update_guardrails_config()`, `check_manual_transaction()` after codegen runs
- GuardrailsEngine is hardened: master toggle, correct swap mint, no agent bypass
- Phase 04-02 (Flutter guardrails settings UI) can proceed immediately

## Self-Check: PASSED

- rust/deadbolt_bridge/src/api/guardrails.rs: FOUND
- rust/deadbolt_core/src/models/config.rs: FOUND
- rust/deadbolt_core/src/agent/guardrails.rs: FOUND
- .planning/phases/04-guardrails-engine/04-01-SUMMARY.md: FOUND
- Commit 82c5f3d: FOUND
- Commit 8ae4bcc: FOUND

---
*Phase: 04-guardrails-engine*
*Completed: 2026-03-19*
