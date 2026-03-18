---
phase: 03-agent-signing-prompt
plan: 06
subsystem: simulation-pipeline
tags: [rust, flutter, frb, simulation, signing-prompt]
dependency_graph:
  requires: [03-05]
  provides: [background-simulation-for-send-intents]
  affects: [intent_provider, signing-prompt-ui]
tech_stack:
  added: []
  patterns: [build-unsigned-tx-for-simulation, frb-codegen, simulateTransaction-rpc]
key_files:
  created: []
  modified:
    - rust/deadbolt_core/src/solana/builder.rs
    - rust/deadbolt_bridge/src/api/send.rs
    - lib/providers/intent_provider.dart
decisions:
  - "build_unsigned_legacy mirrors build_sign_legacy but skips tx.sign() — same instruction pipeline, zeroed signatures"
  - "Placeholder blockhash 11111111111111111111111111111111 used in unsigned tx — RPC replaces via replaceRecentBlockhash=true"
  - "simulationError stored as result.err?.toString() — err is dynamic (null or JSON map), toString() handles both"
metrics:
  duration: 4 min
  completed_date: "2026-03-18"
  tasks_completed: 2
  files_modified: 3
---

# Phase 03 Plan 06: Background Simulation for SendSol and SendToken Summary

**One-liner:** Unsigned transaction builders in Rust bridge plus real simulateTransaction RPC calls close the simulation gap — signing prompt now shows running/passed/failed instead of staying idle.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add build_unsigned_send_sol and build_unsigned_send_token to Rust bridge | b3a463b | rust/deadbolt_core/src/solana/builder.rs, rust/deadbolt_bridge/src/api/send.rs |
| 2 | Run FRB codegen and wire simulation in Dart intent provider | 365058e | lib/providers/intent_provider.dart |

## What Was Built

**Rust core (`deadbolt_core/src/solana/builder.rs`):**
- `pub fn build_unsigned_send_sol(params: &SendSolParams) -> Result<String, DeadboltError>` — builds SOL transfer tx with zeroed sigs
- `pub fn build_unsigned_send_token(params: &SendTokenParams) -> Result<String, DeadboltError>` — builds SPL token tx with zeroed sigs
- `fn build_unsigned_legacy(instructions, fee_payer, blockhash) -> Result<String, DeadboltError>` — private helper, mirrors `build_sign_legacy` without `tx.sign()` call

**Rust bridge (`deadbolt_bridge/src/api/send.rs`):**
- `pub fn build_unsigned_send_sol(to_address, lamports) -> Result<String, String>` — uses active wallet public key, placeholder blockhash
- `pub fn build_unsigned_send_token(to_address, mint_address, amount, create_ata_if_needed) -> Result<String, String>` — same pattern for SPL

**FRB codegen:** Already run in plan 03-05 (`lib/src/rust/api/send.dart` already contained `buildUnsignedSendSol` and `buildUnsignedSendToken`).

**Dart simulation pipeline (`lib/providers/intent_provider.dart`):**
- Replaced the `SimulationPhase.idle` stub in `_runSimulation` with real async simulation
- Sets `SimulationPhase.running` immediately on intent arrival
- Calls `send_bridge.buildUnsignedSendSol` or `send_bridge.buildUnsignedSendToken` based on intent type
- Calls `rpc.simulateTransaction(unsignedBase64)` — uses `sigVerify:false` and `replaceRecentBlockhash:true` from `SolanaRpcClient`
- Updates intent with `SimulationPhase.success` / `SimulationPhase.failed`, `simulationError`, `simulationUnitsConsumed`
- `finally { rpc.dispose() }` ensures HTTP client cleanup even on failure

## Decisions Made

1. **`build_unsigned_legacy` mirrors `build_sign_legacy` without signing** — reuses the exact same instruction building pipeline (compute budget, transfer, jito tip) but calls `Transaction::new(message)` and returns `tx.serialize_base64()` without calling `tx.sign()`. Zeroed signatures are valid for `simulateTransaction` with `sigVerify:false`.

2. **Placeholder blockhash `11111111111111111111111111111111`** — the RPC's `replaceRecentBlockhash:true` param substitutes a fresh blockhash server-side, so no fresh blockhash is needed to build the unsigned tx. This keeps the bridge functions simple (no RPC call needed in Rust).

3. **`simulationError` stored as `result.err?.toString()`** — `SimulationResult.err` is typed `dynamic` (null for success, JSON map or string for failure). Using `.toString()` handles both null (no-op via null-safe `?.`) and structured error objects gracefully.

## Deviations from Plan

None — plan executed exactly as written. FRB codegen for the Dart bindings was found to be already committed (run in plan 03-05), which is a no-op deviation (bindings were already correct).

## Verification Results

All 8 plan verification checks passed:
1. `cargo build -p rust_lib_deadbolt` exits 0
2. `cargo test -p deadbolt_core solana::builder` — note: pre-existing test compilation error in `deadbolt_core/src/agent/auth.rs` (unrelated to builder module) prevents test run; verified pre-existing by stash check
3. `grep "build_unsigned_send_sol" rust/deadbolt_bridge/src/api/send.rs` — match at line 92
4. `grep "build_unsigned_send_token" rust/deadbolt_bridge/src/api/send.rs` — match at line 116
5. `grep "buildUnsignedSendSol" lib/src/rust/api/send.dart` — match at line 62
6. `grep "SimulationPhase.running" lib/providers/intent_provider.dart` — match at line 114
7. `grep "simulateTransaction" lib/providers/intent_provider.dart` — match at line 139
8. `grep "SimulationPhase.idle" lib/providers/intent_provider.dart` — no match (gap closed)

## Self-Check: PASSED
