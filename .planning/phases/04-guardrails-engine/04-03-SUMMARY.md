---
phase: 04-guardrails-engine
plan: 03
subsystem: flutter-ui
tags: [flutter, guardrails, send, swap, state-management, riverpod]

# Dependency graph
requires:
  - phase: 04-01
    provides: FRB bridge checkManualTransaction stub + Rust guardrails engine
  - phase: 04-02
    provides: lib/src/rust/api/guardrails.dart stub with checkManualTransaction signature
affects:
  - send flow: guardrail check before every signAndSubmit; violation banner in _ReviewStep
  - swap flow: guardrail check on output token before every signAndSubmit; violation banner in review step

provides:
  - SendState.guardrailViolation and SendState.guardrailBypassed fields
  - SwapState.guardrailViolation and SwapState.guardrailBypassed fields
  - SendNotifier.checkGuardrails() and bypassGuardrails() methods
  - SwapNotifier.checkGuardrails() and bypassGuardrails() methods
  - Guardrail check injected at start of signAndSubmit() in both providers
  - Inline violation banner with Override with Password button on send review screen
  - Inline violation banner with Override with Password button on swap review screen
  - Confirm/Send button disabled when violation present and not bypassed

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "guardrailViolation/guardrailBypassed fields added to state models; reset() auto-clears both (const SendState() defaults)"
    - "copyWith nullable pattern: guardrailViolation can be cleared by callers who need to null it explicitly"
    - "One-shot bypass: bypassGuardrails() sets guardrailBypassed=true; reset() clears it -- bypass is per-transaction only"
    - "signAndSubmit() double-checks guardrails even if UI bypassed (defense in depth for non-UI callers)"
    - "Swap checks output_mint (what you acquire), send checks token mint (null for SOL = exempt)"

key-files:
  created: []
  modified:
    - lib/models/send.dart
    - lib/models/swap.dart
    - lib/providers/send_provider.dart
    - lib/providers/swap_provider.dart
    - lib/features/send/send_screen.dart
    - lib/features/swap/swap_screen.dart

key-decisions:
  - "SOL sends pass mint=null to checkManualTransaction -- SOL is exempt from token whitelist by engine design"
  - "NFT send flow (NftNotifier/SendNftState) intentionally unmodified -- NFTs exempt from guardrails in v1 per locked decision"
  - "signAndSubmit() re-checks guardrails even when UI already checked -- defense-in-depth against direct provider calls"
  - "guardrailBypassed resets on SendState()/SwapState() construction -- one-shot bypass per transaction, not persistent"

# Metrics
duration: 3min
completed: 2026-03-19
---

# Phase 04 Plan 03: Send/Swap Guardrail Enforcement Summary

**Guardrail enforcement wired into manual send and swap flows: state fields, provider checks before signing, and inline violation banners with password-override on both review screens**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-19T05:24:28Z
- **Completed:** 2026-03-19T05:27:13Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added `guardrailViolation` (String?) and `guardrailBypassed` (bool) fields to `SendState` and `SwapState`, with `copyWith` support and automatic reset via default constructors
- Added `checkGuardrails()` and `bypassGuardrails()` methods to `SendNotifier` and `SwapNotifier`
- Injected guardrail check at the very start of `signAndSubmit()` in both providers -- violation short-circuits with `return` and sets `guardrailViolation` state; bypassed transactions skip the check
- Send checks token mint (null for SOL, which passes the whitelist check); swap checks output token mint (the token being acquired)
- NFT send flow (`NftNotifier`/`SendNftState`) intentionally unmodified -- exempt from guardrails per locked decision
- Added inline violation banner (`Icons.shield_outlined`, `BrandColors.error`) to `_ReviewStep` in `send_screen.dart` with "Override with Password" `OutlinedButton` (warning color)
- Added matching inline violation banner to swap `_ReviewStep` in `swap_screen.dart`
- Override button calls `showAuthChallengeDialog(context)`; on success calls `bypassGuardrails()` which clears the banner and re-enables the confirm button
- Confirm/Send and Swap confirm buttons have `guardrailViolation != null && !guardrailBypassed` disabling condition added
- `dart analyze` reports no errors or warnings on all 6 modified files

## Task Commits

Each task was committed atomically:

1. **Task 1: Add guardrail fields to SendState/SwapState + provider enforcement** - `a371492` (feat)
2. **Task 2: Inline guardrail violation banners on send and swap review screens** - `d3f7ddf` (feat)

## Files Created/Modified

- `lib/models/send.dart` - Added guardrailViolation and guardrailBypassed to SendState fields, constructor, and copyWith
- `lib/models/swap.dart` - Added guardrailViolation and guardrailBypassed to SwapState fields, constructor, and copyWith
- `lib/providers/send_provider.dart` - Added guardrails_bridge import, checkGuardrails(), bypassGuardrails(), guardrail check in signAndSubmit()
- `lib/providers/swap_provider.dart` - Added guardrails_bridge import, checkGuardrails(), bypassGuardrails(), guardrail check in signAndSubmit()
- `lib/features/send/send_screen.dart` - Added auth_challenge_dialog import, violation banner in _ReviewStep, disabled Send button condition
- `lib/features/swap/swap_screen.dart` - Added auth_challenge_dialog import, violation banner in review step, disabled Swap button condition

## Decisions Made

- SOL sends pass `mint: null` to `checkManualTransaction` -- the Rust engine is designed to exempt null mints from the token whitelist, so SOL sends never trigger a whitelist violation
- NFT send flow is intentionally unmodified: `NftNotifier` uses `SendNftState` (a separate model from `SendState`) and its own separate code path -- NFTs are exempt from guardrails in v1 per locked decision
- `signAndSubmit()` re-checks guardrails even though the UI banner exposes `checkGuardrails()` separately -- defense-in-depth approach so direct provider calls also get checked
- `bypassGuardrails()` sets `guardrailBypassed=true` and clears `guardrailViolation` so the banner disappears immediately; `guardrailBypassed` resets on `reset()` call (one-shot, per-transaction only)

## Deviations from Plan

None - plan executed exactly as written. All 6 files modified match the plan's `files_modified` list. No unexpected issues encountered.

## Issues Encountered

None. Pre-existing `dart analyze` warnings in `history_screen.dart`, `agent_api_screen.dart`, and `lock_screen.dart` were noted as out-of-scope and not touched.

## User Setup Required

None - no external configuration required. UI changes activate when guardrails engine is built and FRB codegen runs.

## Next Phase Readiness

- Plan 04-02 (Flutter guardrails settings UI) can proceed -- the `checkManualTransaction` stub and bridge pattern are established
- Plan 04-04 (integration/wiring) can proceed -- send and swap flows now correctly enforce guardrails from the manual side
- Full enforcement activates after FRB codegen runs and replaces the `UnimplementedError` stubs

## Self-Check: PASSED

- lib/models/send.dart: FOUND
- lib/models/swap.dart: FOUND
- lib/providers/send_provider.dart: FOUND
- lib/providers/swap_provider.dart: FOUND
- lib/features/send/send_screen.dart: FOUND
- lib/features/swap/swap_screen.dart: FOUND
- .planning/phases/04-guardrails-engine/04-03-SUMMARY.md: FOUND
- Commit a371492: FOUND
- Commit d3f7ddf: FOUND

---
*Phase: 04-guardrails-engine*
*Completed: 2026-03-19*
