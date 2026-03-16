---
phase: 01-auth-system
plan: 01
subsystem: auth
tags: [rust, scrypt, keychain, atomicbool, ffi, flutter-rust-bridge, security]

# Dependency graph
requires: []
provides:
  - "Rust auth module: set_app_password, verify_app_password, change_app_password, has_app_password (deadbolt_core)"
  - "AtomicBool APP_LOCKED gate: is_app_locked, set_locked, assert_unlocked (deadbolt_core)"
  - "WalletLocked error variant in DeadboltError"
  - "get_active_signer and get_signer reject calls when APP_LOCKED=true"
  - "FFI bridge auth.rs: all auth functions exposed to Flutter via flutter_rust_bridge"
affects: [02-agent-api, 03-guardrails, 04-ui]

# Tech tracking
tech-stack:
  added:
    - "constant_time_eq = 0.3 (timing-safe byte comparison for password verification)"
  patterns:
    - "48-byte Keychain auth entry: [16B random salt || 32B scrypt-Desktop hash]"
    - "AtomicBool APP_LOCKED with SeqCst ordering as global app lock gate"
    - "assert_unlocked() called as first line in signer-access methods (lock gate pattern)"
    - "Auth bridge functions: scrypt operations are pub async, bool queries are pub fn sync"
    - "Test isolation: test-specific Keychain account names using process::id() to avoid conflicts"

key-files:
  created:
    - "rust/deadbolt_core/src/auth/mod.rs"
    - "rust/deadbolt_core/src/auth/lock_state.rs"
    - "rust/deadbolt_core/src/auth/password.rs"
    - "rust/deadbolt_bridge/src/api/auth.rs"
  modified:
    - "rust/deadbolt_core/src/models/error.rs (added WalletLocked variant)"
    - "rust/deadbolt_core/src/models/wallet_manager.rs (lock gate in get_active_signer and get_signer)"
    - "rust/deadbolt_core/src/lib.rs (added pub mod auth)"
    - "rust/deadbolt_core/Cargo.toml (added constant_time_eq = 0.3)"
    - "rust/deadbolt_bridge/src/api/mod.rs (added pub mod auth)"
    - "rust/deadbolt_bridge/src/api/wallet.rs (added storage_pub helper)"

key-decisions:
  - "Scrypt Desktop strength (log_n=17) for app password: matches existing vault KDF for consistency, ~400ms deliberate delay"
  - "48-byte Keychain storage format (16B salt || 32B hash) enables salt-per-password without separate Keychain entries"
  - "APP_LOCKED starts true: wallet is locked at startup, must call unlock_app after password verification"
  - "unlock_app iterates Keychain wallets and loads them into session, then clears lock flag — atomic unlock sequence"
  - "FRB codegen skipped: Flutter/Dart toolchain not available in execution environment; Rust bridge compiles cleanly"
  - "Test-specific Keychain accounts (using process::id()) avoid real app_password_hash Keychain pollution during tests"

patterns-established:
  - "Lock gate: call assert_unlocked() as first line in any function requiring app to be unlocked"
  - "Auth bridge: CPU-intensive ops (scrypt) are pub async, lightweight bool checks are #[frb(sync)] pub fn"
  - "Keychain isolation in tests: use unique account suffix to avoid state leakage between test runs"

requirements-completed: [AUTH-08, AUTH-01, AUTH-02]

# Metrics
duration: 19min
completed: 2026-03-16
---

# Phase 1 Plan 1: Auth System Foundation Summary

**Scrypt-backed app password in macOS Keychain with AtomicBool lock gate enforced on every signer access, plus FRB bridge exposing all 7 auth functions to Flutter**

## Performance

- **Duration:** 19 min
- **Started:** 2026-03-16T10:33:20Z
- **Completed:** 2026-03-16T10:52:10Z
- **Tasks:** 2 of 2
- **Files modified:** 10 (4 created, 6 modified)

## Accomplishments

- Built complete Rust auth module: password.rs with scrypt-Desktop hashing (48-byte [salt||hash] in Keychain), lock_state.rs with SeqCst AtomicBool gate starting locked
- Wired lock gate into wallet_manager: get_active_signer() and get_signer() now call assert_unlocked() first, returning WalletLocked error when APP_LOCKED=true
- Created FFI bridge auth.rs with correct sync/async split: scrypt ops are pub async (won't block Flutter main thread), bool checks are frb(sync) pub fn for fast UI
- All 16 new auth tests pass, all 8 existing wallet_manager tests pass (test_unlock_lock_sign updated to set APP_LOCKED=false for the signer calls)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Rust auth module with password storage and lock state** - `1751aea` (feat)
2. **Task 2: Create FFI bridge for auth functions** - `1cda4d7` (feat)

**Plan metadata:** see final docs commit

_Note: Task 1 used TDD approach — auth module written with inline #[cfg(test)] tests, all verified passing before commit_

## Files Created/Modified

- `rust/deadbolt_core/src/auth/mod.rs` - Auth module root, exports lock_state and password
- `rust/deadbolt_core/src/auth/lock_state.rs` - AtomicBool APP_LOCKED with set_locked, is_app_locked, assert_unlocked + 4 tests
- `rust/deadbolt_core/src/auth/password.rs` - Scrypt password hash in Keychain, set/verify/change/has functions + 8 tests
- `rust/deadbolt_core/src/models/error.rs` - Added WalletLocked variant
- `rust/deadbolt_core/src/models/wallet_manager.rs` - Added lock gate to get_active_signer and get_signer; updated test_unlock_lock_sign
- `rust/deadbolt_core/src/lib.rs` - Added pub mod auth
- `rust/deadbolt_core/Cargo.toml` - Added constant_time_eq = 0.3
- `rust/deadbolt_bridge/src/api/auth.rs` - FRB bridge: 7 auth functions with correct sync/async
- `rust/deadbolt_bridge/src/api/mod.rs` - Added pub mod auth
- `rust/deadbolt_bridge/src/api/wallet.rs` - Added storage_pub() for auth module use

## Decisions Made

- Scrypt Desktop strength (log_n=17) for password hashing: consistent with vault KDF, ~400ms deliberate delay deters brute force
- 48-byte format [16B salt || 32B hash] as single Keychain entry avoids managing separate salt entries
- Test-specific Keychain account names (using process::id()) prevent real `app_password_hash` Keychain entry pollution during tests
- FRB codegen skipped due to missing Flutter toolchain in environment; Rust bridge compiles cleanly, Dart file generation deferred to Flutter environment

## Deviations from Plan

**1. [Rule 3 - Blocking] Rust/cargo not in PATH — installed via rustup**
- **Found during:** Task 1 (first cargo check attempt)
- **Issue:** cargo not in PATH; rustup settings file present but binary missing from $HOME/.cargo/bin
- **Fix:** Re-ran rustup installer (`curl | sh`) which installed Rust 1.94.0; ran all cargo commands via explicit `/Users/jo/.cargo/bin` PATH prefix
- **Impact:** +5 minutes setup. No code changes required.

**2. [Rule 3 - Blocking] FRB codegen requires Flutter/Dart toolchain (not available)**
- **Found during:** Task 2 (flutter_rust_bridge_codegen generate)
- **Issue:** flutter_rust_bridge_codegen exits with "Dart/Flutter toolchain not available" — flutter and dart binaries not installed
- **Fix:** Installed flutter_rust_bridge_codegen via cargo, confirmed Rust bridge compiles (cargo build exits 0). Dart codegen (`lib/src/rust/api/auth.dart`) deferred to when Flutter toolchain is available
- **Impact:** auth.dart not generated; Rust side 100% complete. Run `flutter_rust_bridge_codegen generate` from project root when Flutter is installed.

---

**Total deviations:** 2 (both Rule 3 - blocking environment issues)
**Impact on plan:** No impact on code correctness. Rust layer fully implemented and tested. FRB codegen is a one-command step when Flutter is available.

## Issues Encountered

- Cargo binary discovery: rustup had a settings.toml but no bin directory. Resolved by reinstalling via rustup installer.
- Docker Linux build attempted to compile macOS Keychain (`security_framework`) on Linux — not viable for this macOS-native project.
- `cargo build -p deadbolt_bridge` uses package name `rust_lib_deadbolt` not `deadbolt_bridge` (from Cargo.toml).

## Next Phase Readiness

- Rust auth layer fully operational: password hashing, lock state, FFI bridge
- Phase 01-02 (password setup UI) can call `set_app_password` via FRB after codegen runs
- Phase 01-03 (biometric unlock) can call `is_app_locked`, `unlock_app`, `lock_app` via FRB
- Blocker: FRB codegen must be run in Flutter environment before Flutter code can call auth functions
- Pre-existing concern: verify Flutter SDK version before adopting local_auth 3.x (requires Flutter 3.29+)

## Self-Check: PASSED

All files verified on disk:
- FOUND: rust/deadbolt_core/src/auth/mod.rs
- FOUND: rust/deadbolt_core/src/auth/lock_state.rs
- FOUND: rust/deadbolt_core/src/auth/password.rs
- FOUND: rust/deadbolt_bridge/src/api/auth.rs
- FOUND: .planning/phases/01-auth-system/01-01-SUMMARY.md

All commits verified in git log:
- FOUND: 1751aea - feat(01-01): create Rust auth module with password storage and lock state
- FOUND: 1cda4d7 - feat(01-01): create FFI bridge auth module exposing auth functions to Flutter

---
*Phase: 01-auth-system*
*Completed: 2026-03-16*
