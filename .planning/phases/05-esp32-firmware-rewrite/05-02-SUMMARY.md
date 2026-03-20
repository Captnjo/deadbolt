---
phase: 05-esp32-firmware-rewrite
plan: 02
subsystem: hardware
tags: [rust, esp32, serial, frb, bip39, factory-reset, entropy]

# Dependency graph
requires:
  - phase: 05-esp32-firmware-rewrite
    provides: "Plan 01 — new firmware JSON command protocol (generate/reset/entropy_check)"
provides:
  - "Esp32Bridge::generate() — sends generate cmd, validates 12 mnemonic words, updates stored pubkey/address"
  - "Esp32Bridge::factory_reset() — sends reset cmd with 60s timeout and button-hold loop"
  - "Esp32Bridge::check_entropy() — single-shot entropy_check cmd, returns Ok or error"
  - "generate_hardware_keypair() FRB fn — drives full generate flow with 60s timeout"
  - "factory_reset_hardware() FRB fn — drives reset flow with 30s timeout"
  - "check_hardware_entropy() FRB fn — single-shot entropy verification"
  - "get_hardware_pubkey() FRB fn — lightweight ping+pubkey for auto-connect verification (HWLT-03)"
affects: [05-03, 05-04, 05-05, flutter-hardware-wallet-ui]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FRB bridge functions are synchronous (pub fn, not pub async fn) — FRB v2 runs them on background thread"
    - "Hardware bridge methods share GENERATE_TIMEOUT const for both generate and factory_reset flows"
    - "get_hardware_pubkey uses lightweight ping+pubkey sequence, not full Esp32Bridge::connect(), for auto-connect path"

key-files:
  created: []
  modified:
    - rust/deadbolt_core/src/hardware/esp32_bridge.rs
    - rust/deadbolt_bridge/src/api/hardware.rs

key-decisions:
  - "GENERATE_TIMEOUT (60s) reused for factory_reset — both require 5s BOOT hold plus device operation time"
  - "get_hardware_pubkey skips Esp32Bridge struct (full connect path) — it uses raw serial + serde_json::Value for a lighter-weight pubkey query used only for auto-connect mismatch detection"
  - "wallet registration after generate stays in Flutter layer (after mnemonic quiz) — Rust returns words only, does not touch WalletManager"
  - "factory_reset_hardware timeout is 30s (not 60s) — reset is faster than key generation; no PBKDF2 involved"

patterns-established:
  - "Multi-step response loops: send command, loop reading responses, match on status field (generating/pending -> ok/error)"
  - "Hardware init sequence: 500ms sleep, newline flush, 100ms sleep, ClearBuffer::Input — consistent across all new FRB fns"

requirements-completed: [HWLT-01, HWLT-03]

# Metrics
duration: 2min
completed: 2026-03-20
---

# Phase 5 Plan 02: Rust Bridge Extensions Summary

**ESP32 bridge extended with generate/factory_reset/check_entropy methods in deadbolt_core and four matching FRB pub functions in deadbolt_bridge (rust_lib_deadbolt) enabling BIP39 keypair generation, factory reset, entropy verification, and auto-connect pubkey comparison**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-20T08:29:11Z
- **Completed:** 2026-03-20T08:31:30Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Extended `Esp32Bridge` in deadbolt_core with three new public methods (`generate`, `factory_reset`, `check_entropy`) plus a `words` field on the Response struct and a `GENERATE_TIMEOUT` constant
- Added four new synchronous FRB bridge functions to deadbolt_bridge (`generate_hardware_keypair`, `factory_reset_hardware`, `check_hardware_entropy`, `get_hardware_pubkey`) following established serial init pattern
- Both crates compile cleanly (`cargo check` passes for deadbolt_core and rust_lib_deadbolt)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend esp32_bridge.rs with new Response field and bridge methods** - `c29fb52` (feat)
2. **Task 2: Add FRB bridge functions for hardware keypair generation, reset, and pubkey verification** - `21615db` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified
- `rust/deadbolt_core/src/hardware/esp32_bridge.rs` — Added `words` field to Response, `GENERATE_TIMEOUT` const, `generate()`, `factory_reset()`, `check_entropy()` public methods
- `rust/deadbolt_bridge/src/api/hardware.rs` — Added `std::time::Instant` import and four new pub functions: `generate_hardware_keypair`, `factory_reset_hardware`, `check_hardware_entropy`, `get_hardware_pubkey`

## Decisions Made
- `GENERATE_TIMEOUT` (60s) is reused for `factory_reset` — both operations require a 5-second BOOT button hold and the upper bound is conservative
- `get_hardware_pubkey` bypasses the full `Esp32Bridge::connect()` path and uses raw serial + `serde_json::Value` — lighter-weight for auto-connect pubkey checks that don't need signing capability
- Wallet registration after `generate_hardware_keypair` is intentionally deferred to the Flutter layer (after the mnemonic quiz) — Rust returns words only
- `factory_reset_hardware` uses a 30s timeout (not 60s) since no PBKDF2 is involved in the reset path

## Deviations from Plan

None — plan executed exactly as written.

One minor discovery: the bridge package name in Cargo.toml is `rust_lib_deadbolt` (not `deadbolt_bridge` as referenced in the plan's verify command). The correct `cargo check` invocation is `-p rust_lib_deadbolt`. No code changes required.

## Issues Encountered
- Plan verification command referenced `-p deadbolt_bridge` but the actual Cargo.toml package name is `rust_lib_deadbolt`. Identified by running `cargo check -p deadbolt_bridge` (error) then inspecting `Cargo.toml`. Corrected to `-p rust_lib_deadbolt` — compiled with only pre-existing FRB macro warnings, zero errors.

## Next Phase Readiness
- Rust bridge is fully extended — Flutter FRB codegen will expose `generateHardwareKeypair`, `factoryResetHardware`, `checkHardwareEntropy`, `getHardwarePubkey` to Dart
- Plan 03 (firmware C code) and Plan 04 (Flutter UI) can proceed independently on these foundations

## Self-Check: PASSED

- esp32_bridge.rs: FOUND
- hardware.rs: FOUND
- 05-02-SUMMARY.md: FOUND
- commit c29fb52: FOUND
- commit 21615db: FOUND

---
*Phase: 05-esp32-firmware-rewrite*
*Completed: 2026-03-20*
