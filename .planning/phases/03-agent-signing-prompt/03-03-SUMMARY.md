---
phase: 03-agent-signing-prompt
plan: 03
subsystem: ui
tags: [flutter, riverpod, bottom-sheet, material3, badge, signing-prompt]

# Dependency graph
requires:
  - phase: 03-02
    provides: intentProvider, pendingIntentCountProvider, firstPendingIntentProvider, PendingIntent model, IntentNotifier with approve/reject/retry

provides:
  - SigningPromptSheet widget (DraggableScrollableSheet bottom sheet with full intent preview and lifecycle progress)
  - showSigningPrompt() top-level helper for displaying the sheet from any context
  - NavigationRail Badge on Agent API icon showing pending count
  - Pending Requests queue section in AgentApiScreen
  - Global auto-show listener in AppShell triggering signing prompt on new intents
  - IntentNotifier resubscribe wired to agentServerProvider start events

affects:
  - phase: 03-04
  - app_shell
  - agent_api_screen
  - signing_prompt_sheet

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dynamic NavigationRailDestination list built in build() for badge support (no static const list)"
    - "ref.listen in AppShell build() for cross-screen side effects (auto-show, resubscribe)"
    - "DraggableScrollableSheet for resizable bottom sheet with drag handle"
    - "_advanceToNext() pattern: after action, find next pending or pop sheet"
    - "Timer-based auto-dismiss (3s) on confirmed lifecycle state"

key-files:
  created:
    - lib/features/agent/signing_prompt_sheet.dart
  modified:
    - lib/shared/app_shell.dart
    - lib/features/agent/agent_api_screen.dart

key-decisions:
  - "Dynamic destinations list in build() rather than static const — required for Badge widget which needs runtime pendingCount"
  - "Signing progress view replaces preview content in same sheet instance (no sheet dismiss/reopen on approve)"
  - "_autoDismissScheduled flag in _SigningProgressViewState prevents duplicate timer scheduling on rebuilds"
  - "Stake intent preview shows unsupported banner with disabled Approve; auto-rejected via IntentNotifier on arrival"

patterns-established:
  - "showSigningPrompt(context, intentId) top-level helper pattern — consistent call site from AgentApiScreen queue rows and AppShell auto-show"
  - "_truncateAddress() helper: first 6 + ... + last 4 chars for wallet address display"

requirements-completed: [AGNT-04, AGNT-05]

# Metrics
duration: 4min
completed: 2026-03-18
---

# Phase 3 Plan 03: Agent Signing Prompt UI Summary

**DraggableScrollableSheet signing prompt with intent preview, simulation status, lifecycle progress view, NavigationRail badge, and global auto-show listener wired to AppShell**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-18T07:02:30Z
- **Completed:** 2026-03-18T07:06:16Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- Built SigningPromptSheet with full preview content for all 5 intent types (SendSol, SendToken, Swap, SignMessage, Stake), SimulationStatusRow (running/passed/failed), and SigningProgressView (signing/submitting/confirmed/failed lifecycles)
- Wired NavigationRail Agent API icon with Material 3 Badge showing pending intent count, replacing static _destinations with dynamic build-time list
- Added global auto-show listener in AppShell and Pending Requests queue section in AgentApiScreen

## Task Commits

1. **Task 1: Build signing prompt bottom sheet widget** - `0003f21` (feat)
2. **Task 2: NavigationRail badge + Pending Requests + global auto-show** - `0841cc3` (feat)

## Files Created/Modified

- `lib/features/agent/signing_prompt_sheet.dart` — New file: SigningPromptSheet widget, showSigningPrompt() helper, all preview types, SimulationStatusRow, SigningProgressView
- `lib/shared/app_shell.dart` — Badge on Agent API icon, auto-show ref.listen, resubscribe ref.listen, dynamic destinations
- `lib/features/agent/agent_api_screen.dart` — Pending Requests queue section above Server section, pendingIntents watch

## Decisions Made

- Dynamic destinations list in build() rather than static const — required because Badge widget needs runtime pendingCount which is only available via ref.watch
- Signing progress view replaces preview content within same sheet instance; no sheet dismiss/reopen on approve — keeps sheet lifecycle continuous
- _autoDismissScheduled boolean flag prevents duplicate Timer creation on subsequent rebuilds during confirmed lifecycle state
- Stake intent shows unsupported warning banner with disabled Approve button; auto-rejection is handled by IntentNotifier on arrival (Plan 02)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Signing prompt UI is fully built and wired to intentProvider
- Auto-show, badge, and queue section complete
- Phase 3 plan 04 can proceed (guardrails settings screen or additional intent lifecycle work)
- FRB codegen still needed for StreamSink live streaming; current behavior uses stub that will activate post-codegen

---
*Phase: 03-agent-signing-prompt*
*Completed: 2026-03-18*
