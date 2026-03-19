---
phase: 04
slug: guardrails-engine
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust: cargo test; Dart: flutter test |
| **Config file** | rust/deadbolt_core/Cargo.toml, pubspec.yaml |
| **Quick run command** | `cargo test -p deadbolt_core --lib guardrails && cargo test -p deadbolt_core --lib config` |
| **Full suite command** | `cargo test -p deadbolt_core && cargo build -p rust_lib_deadbolt` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cargo test -p deadbolt_core --lib guardrails && cargo test -p deadbolt_core --lib config`
- **After every plan wave:** Run `cargo test -p deadbolt_core && cargo build -p rust_lib_deadbolt`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | INFR-04, GRDL-01 | unit | `cargo test -p deadbolt_core --lib guardrails` | ✅ | ⬜ pending |
| 04-01-02 | 01 | 1 | GRDL-04 | unit | `cargo test -p deadbolt_core --lib guardrails` | ✅ | ⬜ pending |
| 04-02-01 | 02 | 1 | GRDL-01, GRDL-03 | build | `cargo build -p rust_lib_deadbolt` | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 | 2 | GRDL-07 | manual | Flutter UI inspection | N/A | ⬜ pending |
| 04-03-02 | 03 | 2 | GRDL-03 | manual | Flutter UI inspection | N/A | ⬜ pending |
| 04-04-01 | 04 | 3 | GRDL-04 | manual | Flutter send flow test | N/A | ⬜ pending |
| 04-04-02 | 04 | 3 | GRDL-06, GRDL-05 | manual | Flutter bypass + error test | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `rust/deadbolt_bridge/src/api/guardrails.rs` — bridge module stubs for FRB codegen
- [ ] Existing Rust test infrastructure covers guardrails unit tests

*Existing infrastructure covers Rust-side requirements. Bridge module is created during execution.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Token whitelist picker shows held tokens | GRDL-03 | UI widget rendering | Open Settings > Guardrails > Add Token, verify picker shows wallet tokens |
| Inline guardrail warning on send confirmation | GRDL-04 | Flutter UI interaction | Whitelist USDC only, attempt to send SOL token not in whitelist, verify warning banner |
| Password bypass on blocked transaction | GRDL-06 | Auth flow + UI | Trigger guardrail block, tap Override, enter password, verify tx proceeds |
| Master toggle requires password to disable | GRDL-07 | Auth flow + UI | Toggle guardrails off, verify password challenge appears |
| Agent receives specific error message | GRDL-05 | HTTP API test | Send curl with non-whitelisted token intent, verify 403 body contains specific violation |
| Config survives restart | INFR-04 | App lifecycle | Configure whitelist, restart app, verify settings persisted |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
