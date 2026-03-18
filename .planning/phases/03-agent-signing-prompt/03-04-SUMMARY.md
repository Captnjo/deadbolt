---
phase: 03-agent-signing-prompt
plan: 04
status: complete
started: 2026-03-18
completed: 2026-03-18
---

## Summary

Human verification of the agent signing prompt system across all requirement IDs.

## Test Results

| # | Test | Result | Notes |
|---|------|--------|-------|
| 1 | Intent submission (AGNT-03) | ✓ | 201 with `"status": "pending"` |
| 2 | Signing prompt auto-show (AGNT-04) | ✓ | Sheet appears with correct preview |
| 3 | Dismiss behavior (AGNT-04) | ✓ | Sheet closes, intent stays pending |
| 4 | Queue + badge (AGNT-05) | ✓ | Badge increments, Pending Requests section shows all |
| 5 | Review from queue (AGNT-05) | ✓ | Tap Review opens correct intent |
| 6 | Simulation updates (AGNT-06) | ✓ | RPC error shown for unfunded wallet |
| 7 | Approve flow (AGNT-07, AGNT-08) | ⚠ | Error state works (unfunded wallet). Full signing→confirmed flow untestable without funded devnet wallet. |
| 8 | Reject flow (AGNT-07) | ✓ | Clean close, removed from queue |
| 9 | Agent status polling (AGNT-09) | ✓ | Returns correct status via curl |
| 10 | sign_message intent (AGNT-03, AGNT-04) | ✓ | Shows in queue with correct label |
| 11 | After idle lock (AGNT-05) | — | Not tested (manual lock flow) |

## Bugs Found and Fixed During Testing

1. **Rust Send trait errors** — MutexGuard/RwLockReadGuard held across .await in start_agent_server. Fixed by scoping guards.
2. **Dart type mismatches** — PendingIntent not imported in app_shell, BigInt vs int for createdAt, missing signMessage bridge function.
3. **Intent stream not connected** — sink.add() was commented out pending codegen. Enabled.
4. **Stream lost on hot restart** — mpsc channel (single consumer) replaced with broadcast channel for re-subscribable stream.
5. **Double-pop crash on reject** — Race between reject handler and rebuild both calling Navigator.pop(). Fixed with _popping guard.

## UX Improvements Made

- Removed useless copy button for masked API keys
- Updated key creation copy to "Keep it secret"
- Added 60-second auth cooldown to reduce password prompt fatigue

## Caveats

- Full approve→signing→submitting→confirmed flow requires a funded devnet wallet
- sign_message signing returns UnimplementedError (bridge function not yet implemented)
- Idle lock auto-popup suppression not manually verified
