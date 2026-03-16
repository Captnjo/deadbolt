---
phase: 2
slug: agent-api-bridge
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | cargo test (Rust), flutter test (Dart) |
| **Config file** | None needed — standard cargo test |
| **Quick run command** | `cd rust && cargo test -p deadbolt_core agent -- --nocapture` |
| **Full suite command** | `cd rust && cargo test && flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd rust && cargo test -p deadbolt_core agent -- --nocapture`
- **After every plan wave:** Run `cd rust && cargo test && flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | AGNT-01 | unit | `cargo test -p deadbolt_core test_server_start_stop` | ✅ | ⬜ pending |
| 02-01-02 | 01 | 1 | AGNT-02 | unit | `cargo test -p deadbolt_core test_invalid_token_rejected` | ✅ | ⬜ pending |
| 02-01-03 | 01 | 1 | AGNT-10 | integration | `cargo test -p deadbolt_core test_query_endpoints` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 | 1 | AGNT-11 | unit | `cargo test -p deadbolt_bridge test_create_api_key` | ❌ W0 | ⬜ pending |
| 02-01-05 | 01 | 1 | AGNT-12 | unit | `cargo test -p deadbolt_bridge test_revoke_api_key_live` | ❌ W0 | ⬜ pending |
| 02-01-06 | 01 | 1 | AGNT-14 | widget | `flutter test test/agent_api_screen_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-07 | 01 | 1 | AGNT-15 | widget | `flutter test test/agent_provider_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-08 | 01 | 1 | INFR-08 | integration | `cargo test -p deadbolt_core test_port_released_after_stop` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `rust/deadbolt_core/src/agent/server.rs` — add `test_query_endpoints` covering AGNT-10
- [ ] `rust/deadbolt_bridge/src/api/agent.rs` — add `test_create_api_key` and `test_revoke_api_key_live` covering AGNT-11, AGNT-12
- [ ] `rust/deadbolt_core/src/agent/server.rs` — add `test_port_released_after_stop` for INFR-08
- [ ] `test/agent_api_screen_test.dart` — widget test for AGNT-14
- [ ] `test/agent_provider_test.dart` — provider test for AGNT-15

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Curl command contains real bearer token | AGNT-13 | Requires visual inspection of generated curl command in UI context | 1. Create API key 2. Open Quick Test section 3. Select any endpoint 4. Verify curl command includes valid bearer token |
| INFR-05 axum 0.8 route syntax | INFR-05 | Code review only — already confirmed | `grep -n '{id}' rust/deadbolt_core/src/agent/server.rs` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
