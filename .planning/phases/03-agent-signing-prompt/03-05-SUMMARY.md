---
phase: 03-agent-signing-prompt
plan: 05
subsystem: api
tags: [rust, flutter-rust-bridge, ed25519, signing, intent]

# Dependency graph
requires:
  - phase: 03-agent-signing-prompt
    provides: SignMessageIntent model, intent_provider approve pipeline, FRB codegen infrastructure
provides:
  - sign_message Rust bridge function in sign.rs (hex in -> hex signature out, no on-chain tx)
  - FRB-generated signMessage Dart binding in sign.dart
  - SignMessageIntent approve path: calls bridge, skips sendTransaction, transitions to confirmed
affects:
  - phase verification (gap 1 and gap 3 closed)
  - 03-06-PLAN.md (simulation gap)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "sign_message returns SignedTxDto with empty base64 — message signing produces signature only, no on-chain tx"
    - "isSignMessage early-return guard in approve() skips sendTransaction + pollConfirmation path"
    - "FRB sign.dart is authoritative home for message signing — functions added to sign.rs, not agent.rs"

key-files:
  created: []
  modified:
    - rust/deadbolt_bridge/src/api/sign.rs
    - lib/src/rust/api/sign.dart
    - lib/providers/intent_provider.dart
    - lib/src/rust/frb_generated.dart
    - rust/deadbolt_bridge/src/frb_generated.rs

key-decisions:
  - "sign_message placed in sign.rs (not agent.rs) — semantically correct grouping with sign_serialized_transaction, maps to FRB-generated sign.dart"
  - "SignedTxDto reused for sign_message with empty base64 field — no new type needed; Dart side ignores base64 for sign_message intents"
  - "isSignMessage early-return in approve() before sendTransaction — clean separation of message-signing vs transaction-submission paths"

patterns-established:
  - "sign_message hex-in/hex-out pattern: decode hex bytes -> sign raw bytes -> encode signature as hex"
  - "approve() early-return pattern for intent types that don't need on-chain submission"

requirements-completed: [AGNT-03, AGNT-08]

# Metrics
duration: 8min
completed: 2026-03-18
---

# Phase 03 Plan 05: sign_message Bridge and SignMessageIntent Wiring Summary

**Ed25519 sign_message Rust bridge function wired end-to-end: approving a SignMessageIntent now produces a real hex signature and transitions to confirmed, skipping on-chain submission**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-18T14:12:00Z
- **Completed:** 2026-03-18T14:20:00Z
- **Tasks:** 2
- **Files modified:** 7 (sign.rs + FRB codegen regenerated 6 Dart/Rust binding files)

## Accomplishments
- Added `pub fn sign_message(message_hex: String) -> Result<SignedTxDto, String>` to `sign.rs` following the established `sign_serialized_transaction` pattern
- Ran FRB codegen to generate `signMessage({required String messageHex})` binding in `lib/src/rust/api/sign.dart`
- Replaced `throw UnimplementedError` in `intent_provider.dart` SignMessageIntent branch with real `sign_bridge.signMessage()` call
- Added `isSignMessage` early-return guard in `approve()` that calls `updateIntentStatus(confirmed)` and returns without calling `sendTransaction` or `_pollConfirmation`
- Closed verification gap 1 (sign_message unimplemented) and gap 3 (Sign button crashes on sign_message)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add sign_message function to Rust bridge sign.rs** - `5024cc9` (feat)
2. **Task 2: Run FRB codegen and wire SignMessageIntent signing in Dart** - `1dc0742` (feat)

## Files Created/Modified
- `rust/deadbolt_bridge/src/api/sign.rs` - Added `sign_message` function (hex decode, get_active_signer, sign raw bytes, return SignedTxDto with empty base64)
- `lib/src/rust/api/sign.dart` - FRB-regenerated; now contains `signMessage({required String messageHex})` binding
- `lib/providers/intent_provider.dart` - Added `sign_bridge` import, replaced UnimplementedError with real bridge call, added isSignMessage early-return guard in `approve()`
- `lib/src/rust/frb_generated.dart` - FRB-regenerated to include sign_message dispatch
- `rust/deadbolt_bridge/src/frb_generated.rs` - FRB-regenerated to include sign_message handler
- `lib/src/rust/api/agent.dart`, `send.dart`, `auth.dart`, `hardware.dart`, `types.dart`, `wallet.dart` - FRB-regenerated (consistent re-emission, no functional change)

## Decisions Made
- Used `SignedTxDto` with empty `base64` for sign_message response — avoids a new return type; Dart side only reads `signature` for sign_message intents
- Placed `sign_message` in `sign.rs` (not `agent.rs`) — groups with the other signing functions, FRB generates it into the stable `sign.dart` file
- `isSignMessage` early-return in `approve()` is cleanest approach: no conditional logic scattered through submission/polling code

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Verification gaps 1 and 3 are now closed
- sign_message end-to-end path is complete: agent POST -> pending intent -> user taps Sign -> Ed25519 signature -> confirmed status
- Phase 03 verification can now confirm 11/12 must-haves (pending simulation gap from plan 06)

---
*Phase: 03-agent-signing-prompt*
*Completed: 2026-03-18*

## Self-Check: PASSED

- sign.rs: FOUND
- sign.dart: FOUND
- intent_provider.dart: FOUND
- 03-05-SUMMARY.md: FOUND
- Commit 5024cc9: FOUND
- Commit 1dc0742: FOUND
