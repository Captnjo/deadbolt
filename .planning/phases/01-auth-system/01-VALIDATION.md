---
phase: 1
slug: auth-system
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust built-in tests (`cargo test`) + Flutter widget tests (`flutter test`) |
| **Config file** | Rust: `#[cfg(test)]` blocks; Flutter: `pubspec.yaml` dev_dependencies |
| **Quick run command** | `cargo test -p deadbolt_core auth -- --test-threads=1` |
| **Full suite command** | `cargo test -p deadbolt_core && flutter test test/` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cargo test -p deadbolt_core auth` (Rust tasks) or `flutter test test/` (Flutter tasks)
- **After every plan wave:** Run `cargo test -p deadbolt_core && flutter test test/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | AUTH-08 | unit (Rust) | `cargo test -p deadbolt_core auth::password` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | AUTH-08 | unit (Rust) | `cargo test -p deadbolt_core auth::password::test_wrong_password` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | AUTH-01 | widget test | `flutter test test/lock_screen_test.dart` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | AUTH-02 | unit (Dart) | `flutter test test/auth_provider_test.dart` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | AUTH-03 | unit (Dart) | `flutter test test/auth_provider_test.dart` | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 2 | INFR-06 | unit (Rust) | `cargo test -p deadbolt_core agent::auth` | ✅ partial | ⬜ pending |
| 01-03-02 | 03 | 2 | INFR-07 | unit (Rust) | `cargo test -p deadbolt_core crypto::vault::test_zeroize` | ❌ W0 | ⬜ pending |
| 01-04-01 | 04 | 2 | AUTH-04/06 | widget test | `flutter test test/auth_challenge_dialog_test.dart` | ❌ W0 | ⬜ pending |
| 01-04-02 | 04 | 2 | AUTH-07 | unit (Rust) | `cargo test -p deadbolt_core auth::password::test_change_password` | ❌ W0 | ⬜ pending |
| 01-05-01 | 05 | 2 | Pitfall 8 | unit (Rust) | `cargo test -p deadbolt_core auth::lock_state` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `rust/deadbolt_core/src/auth/mod.rs` — new auth module
- [ ] `rust/deadbolt_core/src/auth/password.rs` — set/verify/change password + tests
- [ ] `rust/deadbolt_core/src/auth/lock_state.rs` — AtomicBool + tests
- [ ] `rust/deadbolt_bridge/src/api/auth.rs` — FRB-exposed auth functions
- [ ] `test/lock_screen_test.dart` — Flutter widget tests for lock screen
- [ ] `test/auth_provider_test.dart` — Flutter unit tests for AuthNotifier
- [ ] `test/auth_challenge_dialog_test.dart` — Flutter widget test for challenge modal
- [ ] `DeadboltError::WalletLocked` variant addition to `models/mod.rs`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Idle timeout triggers lock after configured period | AUTH-03 | Real timer behavior needs wall-clock wait | Set idle to 10s, leave app, verify lock screen appears |
| Window focus lost → timer paused | AUTH-03 | Requires OS window events | Minimize app during idle countdown, restore, verify timer reset |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
