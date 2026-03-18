---
phase: 03-agent-signing-prompt
plan: 02
subsystem: ui
tags: [flutter, riverpod, dart, solana, intent-queue, state-management, signing-pipeline]

# Dependency graph
requires:
  - phase: 03-agent-signing-prompt
    provides: "IntentEvent FRB bridge stubs (streamIntents, approveIntent, rejectIntent, updateIntentStatus)"
  - phase: 02-agent-api-bridge
    provides: "agent.dart stub, AgentServerNotifier, server lifecycle"
provides:
  - "PendingIntent model with sealed AgentIntentType hierarchy (5 variants)"
  - "IntentNotifier with stream subscription, queue management, signing pipeline"
  - "intentProvider, pendingIntentCountProvider, firstPendingIntentProvider"
  - "rootNavigatorKeyProvider for global bottom sheet access"
affects: [03-agent-signing-prompt plan 03, any future feature consuming intent queue]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sealed class hierarchy for intent types — exhaustive pattern matching in Dart 3"
    - "NotifierProvider with StreamSubscription + onDispose for stream lifecycle"
    - "resubscribe() pattern for reconnecting streams when server restarts"
    - "copyWith on immutable model for state transitions without mutation"
    - "Stub functions in agent.dart for Rust operations pending FRB codegen"

key-files:
  created:
    - lib/models/intent.dart
    - lib/providers/intent_provider.dart
  modified:
    - lib/routing/app_router.dart
    - lib/src/rust/api/agent.dart

key-decisions:
  - "signMessage stub added to agent.dart (not send.dart) — agent.dart is hand-written stub, send.dart is FRB-generated and must not be modified"
  - "Simulation deferred (SimulationPhase.idle) for SendSol/SendToken — buildUnsignedSendSol/buildUnsignedSendToken don't exist in FRB-generated send.dart; requires future Rust-side unsigned tx builder"
  - "approve() sends SignedTxDto.base64 to sendTransaction — sign returns ({base64, signature}) record matching actual send.dart API"
  - "sign_message approve path returns empty base64 with signature only — no on-chain tx submission for message signing"

patterns-established:
  - "Intent type hierarchy: sealed AgentIntentType + concrete variants, parsed from JSON via factory constructor"
  - "Intent lifecycle: pending -> signing -> submitting -> confirmed/failed/rejected (tracks each RPC step)"
  - "Auto-reject unsupported intents immediately on receipt with descriptive error"

requirements-completed: [AGNT-04, AGNT-05, AGNT-06, AGNT-07, AGNT-08, AGNT-09]

# Metrics
duration: 3min
completed: 2026-03-18
---

# Phase 03 Plan 02: Agent Signing Prompt - State Management Layer Summary

**Dart intent model with sealed 5-variant AgentIntentType hierarchy, IntentNotifier streaming from Rust bridge with queue/approve/reject/retry/signing pipeline, three Riverpod providers, and rootNavigatorKeyProvider for global bottom sheet access.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-18T06:57:02Z
- **Completed:** 2026-03-18T06:59:52Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created `lib/models/intent.dart` with sealed `AgentIntentType` hierarchy (SendSol, SendToken, Swap, Stake, SignMessage), `PendingIntent` model with `fromEvent` factory, `copyWith`, `timeAgo`, simulation state, lifecycle tracking
- Created `lib/providers/intent_provider.dart` with full `IntentNotifier`: stream subscription to FRB bridge, auto-reject for unsupported stake intents, approve/reject/retry public API, signing pipeline reusing send_bridge, confirmation polling via `getSignatureStatuses`
- Exposed `rootNavigatorKeyProvider` in `app_router.dart` wrapping the existing private `_rootNavigatorKey` for global bottom sheet access

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Dart intent model + expose navigator key** - `24a8935` (feat)
2. **Task 2: Create IntentNotifier with stream subscription and signing pipeline** - `0ca401d` (feat)

## Files Created/Modified
- `lib/models/intent.dart` - Sealed AgentIntentType hierarchy, PendingIntent model, SwapQuotePreview, enums
- `lib/providers/intent_provider.dart` - IntentNotifier, intentProvider, pendingIntentCountProvider, firstPendingIntentProvider
- `lib/routing/app_router.dart` - Added rootNavigatorKeyProvider
- `lib/src/rust/api/agent.dart` - Added signMessage stub

## Decisions Made
- `signMessage` stub added to `agent.dart` (not `send.dart`) — `agent.dart` is a hand-written stub file; `send.dart` is FRB-generated and must not be modified
- Simulation deferred (`SimulationPhase.idle`) for SendSol/SendToken intents — `buildUnsignedSendSol`/`buildUnsignedSendToken` don't exist in FRB-generated `send.dart`; requires future Rust-side unsigned transaction builder
- `approve()` uses `SignedTxDto.base64` for `sendTransaction` — actual send.dart returns `SignedTxDto` not raw strings; signing pipeline adapted accordingly
- `sign_message` approve path skips `sendTransaction` (returns empty base64 with signature only) — message signing has no on-chain transaction to submit

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected send_bridge API calls to match actual FRB-generated signatures**
- **Found during:** Task 2 (IntentNotifier signing pipeline)
- **Issue:** Plan assumed `signSendSol(from:, to:, lamports:, recentBlockhash:)` but actual generated API is `signSendSol(toAddress:, lamports:, recentBlockhash:)` — no `from` param (implicit from active wallet), returns `SignedTxDto` not `String`
- **Fix:** Used `toAddress:` named param, used `result.base64` and `result.signature` from `SignedTxDto`, same correction for `signSendToken` (uses `mintAddress:` not `mint:`)
- **Files modified:** `lib/providers/intent_provider.dart`
- **Committed in:** `0ca401d` (Task 2 commit)

**2. [Rule 1 - Bug] Corrected confirmation polling to use getSignatureStatuses (plural)**
- **Found during:** Task 2 (confirmation polling)
- **Issue:** Plan called `rpc.getSignatureStatus(signature)` (singular) but actual SolanaRpcClient has `getSignatureStatuses(List<String>)` returning `List<String?>`
- **Fix:** Used `rpc.getSignatureStatuses([signature])` with `.firstOrNull` to extract the status
- **Files modified:** `lib/providers/intent_provider.dart`
- **Committed in:** `0ca401d` (Task 2 commit)

**3. [Rule 1 - Bug] Added signMessage stub to agent.dart instead of modifying FRB-generated send.dart**
- **Found during:** Task 2 (sign_message intent signing)
- **Issue:** Plan directed adding `signMessage` stub to `send.dart` but that file is FRB-generated and must not be modified
- **Fix:** Added `signMessage` stub to `agent.dart` (hand-written stub file) where it logically belongs
- **Files modified:** `lib/src/rust/api/agent.dart`
- **Committed in:** `0ca401d` (Task 2 commit)

**4. [Rule 2 - Missing Critical] Simulation deferred with idle phase (no buildUnsigned functions exist)**
- **Found during:** Task 2 (background simulation)
- **Issue:** Plan assumed `send_bridge.buildUnsignedSendSol`/`buildUnsignedSendToken` exist but FRB-generated send.dart has no such functions
- **Fix:** `_runSimulation` sets `SimulationPhase.idle` for all intent types — simulation UI will show nothing rather than crashing; deferred until Rust exposes unsigned tx builder
- **Files modified:** `lib/providers/intent_provider.dart`
- **Committed in:** `0ca401d` (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (3 Rule 1 API mismatches, 1 Rule 2 deferred feature)
**Impact on plan:** All auto-fixes necessary for correctness against actual generated API. Simulation deferral is acceptable — simulation is enhancement not blocker for signing prompt UI.

## Issues Encountered
- send.dart is FRB-generated (not a stub as the plan context implied) — required routing signMessage to agent.dart stub instead
- Unsigned transaction builders don't exist in the bridge yet — simulation feature deferred

## Next Phase Readiness
- Intent model and all providers are ready for Plan 03 UI widgets to consume
- `intentProvider`, `pendingIntentCountProvider`, `firstPendingIntentProvider` all exported and functional
- `rootNavigatorKeyProvider` available for global bottom sheet display
- Simulation feature gap documented — UI can hide simulation section when `SimulationPhase.idle`

---
*Phase: 03-agent-signing-prompt*
*Completed: 2026-03-18*
