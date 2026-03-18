---
phase: 3
slug: agent-signing-prompt
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in SDK) + Rust `#[test]` |
| **Config file** | none — flutter_test is implicit; Rust uses `#[cfg(test)]` modules inline |
| **Quick run command** | `flutter test test/ && cd rust && cargo test -p deadbolt_core` |
| **Full suite command** | `flutter test test/ && cd rust && cargo test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/ && cd rust && cargo test -p deadbolt_core`
- **After every plan wave:** Run `flutter test test/ && cd rust && cargo test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | AGNT-03 | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::intent` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | AGNT-03 | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::intent::tests` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 1 | AGNT-04 | unit (Dart) | `flutter test test/intent_model_test.dart` | ❌ W0 | ⬜ pending |
| 03-02-02 | 02 | 1 | AGNT-04 | widget (Dart) | `flutter test test/signing_prompt_sheet_test.dart` | ❌ W0 | ⬜ pending |
| 03-03-01 | 03 | 1 | AGNT-05 | unit (Dart) | `flutter test test/intent_provider_test.dart` | ❌ W0 | ⬜ pending |
| 03-03-02 | 03 | 1 | AGNT-05 | widget (Dart) | `flutter test test/app_shell_badge_test.dart` | ❌ W0 | ⬜ pending |
| 03-04-01 | 04 | 2 | AGNT-06 | manual | manual (needs live RPC) | N/A | ⬜ pending |
| 03-05-01 | 05 | 2 | AGNT-07 | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::server::tests::test_approve_reject_intent` | ✅ | ⬜ pending |
| 03-05-02 | 05 | 2 | AGNT-07 | unit (Dart) | `flutter test test/intent_provider_test.dart` | ❌ W0 | ⬜ pending |
| 03-06-01 | 06 | 3 | AGNT-08 | manual + integration | manual E2E | N/A | ⬜ pending |
| 03-07-01 | 07 | 3 | AGNT-09 | unit (Rust) | `cd rust && cargo test -p deadbolt_core agent::server` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/intent_model_test.dart` — covers AGNT-03/AGNT-04 (PendingIntent parsing, all IntentType variants)
- [ ] `test/intent_provider_test.dart` — covers AGNT-05/AGNT-07 (state transitions, queue management)
- [ ] `test/signing_prompt_sheet_test.dart` — covers AGNT-04 (widget smoke test, no FRB calls needed)
- [ ] `test/app_shell_badge_test.dart` — covers AGNT-05 (badge visibility based on pendingIntentCountProvider)
- [ ] Rust: `intent.rs` serde test for new `SignMessage` variant — covers AGNT-03

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| simulateTransaction with replaceRecentBlockhash=true | AGNT-06 | Requires live Solana RPC connection | 1. POST a send_sol intent via agent API 2. Observe simulation results appear in signing prompt overlay 3. Verify replaceRecentBlockhash and sigVerify flags in RPC call |
| Sign-and-submit pipeline calls update_intent_status at each step | AGNT-08 | Full E2E flow across Rust server + Flutter UI + Solana network | 1. Approve a pending intent 2. Verify status transitions: pending → approved → signing → submitted → confirmed/failed 3. Verify agent polling returns correct status at each step |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
