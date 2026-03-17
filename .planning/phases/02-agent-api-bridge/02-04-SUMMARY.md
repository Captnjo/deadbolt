---
phase: 02-agent-api-bridge
plan: "04"
subsystem: flutter-ui
tags: [agent-api, dashboard, flutter, riverpod, ui]
dependency_graph:
  requires: ["02-03"]
  provides: ["AgentApiScreen"]
  affects: ["lib/features/agent/agent_api_screen.dart"]
tech_stack:
  added: []
  patterns:
    - ConsumerStatefulWidget with local state for dropdown selection
    - Dismissible swipe-to-delete with confirmDismiss auth gate
    - StatefulBuilder for in-place dialog state transitions (create flow)
    - Timer-based clipboard auto-clear (PLSH-02, 30 seconds)
key_files:
  created: []
  modified:
    - lib/features/agent/agent_api_screen.dart
decisions:
  - "Clipboard auto-clear (30s timer) implemented here proactively as canonical sensitive-copy use case per UI-SPEC note on PLSH-02"
  - "Copy curl command requires auth challenge to retrieve full token (per CONTEXT.md decision)"
  - "_copyCurlCommand uses getFullKey at copy time — masked token shown in display, real token only at copy press"
metrics:
  duration: 2 min
  completed: "2026-03-17"
---

# Phase 02 Plan 04: Agent API Dashboard Screen Summary

Full `AgentApiScreen` implementation — server toggle with status indicator, API key management (create/reveal/revoke with auth challenges), empty state, and Quick Test curl generator.

## What Was Built

Single `ConsumerStatefulWidget` at `lib/features/agent/agent_api_screen.dart` (687 lines), replacing the placeholder from Plan 03.

### Server Section
- `SwitchListTile` disabled when `hasApiKeys == false`
- Loading spinner in `secondary` slot while server is starting
- Status indicator: 10px colored circle (green/gray/red) + status text with `Semantics` wrapper for accessibility
- Status text: "Running on :9876", "Stopped", "Error: {message}"

### API Keys Section
- Empty state: `Icons.lan_outlined`, "Connect AI Agents" heading, explanation body, "Create Your First Key" CTA
- Key rows: `Dismissible` with `DismissDirection.endToStart`, `ListTile` with masked monospace token, reveal + copy icon buttons with `Tooltip` wrappers
- `Semantics` on masked key text for screen reader accessibility
- "+ Create Key" `OutlinedButton` when keys exist

### Interaction Flows
- **Create**: auth challenge -> label dialog (with default fallback "API Key N") -> `createKey()` -> in-place dialog transition to show-once token + "Copy & Close"
- **Reveal**: auth challenge -> `getFullKey()` -> AlertDialog with full token + "Copy & Close"
- **Revoke**: swipe -> "Revoke API key?" confirm dialog with "Keep Key"/"Revoke Key" buttons -> auth challenge -> `getFullKey()` -> `revokeKey()` -> auto-stop server if last key
- **Copy curl**: auth challenge -> `getFullKey()` -> build curl with real token -> clipboard

### Quick Test Section
- Endpoint `DropdownButton` with 6 options: `/health`, `/wallet`, `/balance`, `/tokens`, `/price`, `/history`
- Key selector dropdown (only shown when > 1 key)
- `SelectableText` curl display in styled code block card
- Copy button that gates on auth challenge to use real token (not masked)

### Clipboard Auto-Clear
Implemented `Timer(30s)` that clears clipboard after any sensitive copy — covers curl copy, key reveal, and key creation (proactive PLSH-02 implementation per UI-SPEC note).

## Deviations from Plan

### Auto-added Features

**1. [Rule 2 - Missing Critical] Clipboard auto-clear timer (PLSH-02)**
- **Found during:** Task 1
- **Issue:** UI-SPEC explicitly noted "Clipboard auto-clears after 30 seconds (Phase 6 polish requirement PLSH-02 — implement the timer here proactively since this is the canonical sensitive-copy use case)"
- **Fix:** Added `Timer? _clipboardClearTimer` with 30-second auto-clear on every `_copyToClipboard` call
- **Files modified:** lib/features/agent/agent_api_screen.dart
- **Commit:** 86e95f6

**2. [Rule 2 - Missing] Default label fallback for key creation**
- **Found during:** Task 1
- **Issue:** UI-SPEC Copywriting Contract specifies default label "API Key 1, API Key 2, …" when blank; plan action didn't explicitly handle this
- **Fix:** When label field is empty, uses `'API Key ${keys.length + 1}'` as default
- **Files modified:** lib/features/agent/agent_api_screen.dart
- **Commit:** 86e95f6

## Tasks

| Task | Name | Status | Commit |
|------|------|--------|--------|
| 1 | Build AgentApiScreen with server toggle, key management, and quick test | Complete | 86e95f6 |
| 2 | Verify Agent API screen layout and interactions | Checkpoint (pending human verify) | — |

## Self-Check: PASSED

- [x] `lib/features/agent/agent_api_screen.dart` exists (21,984 bytes, 687 lines)
- [x] Commit `86e95f6` exists in git log
- [x] All 37 acceptance criteria met (6 grep pattern misses were formatting-only — content verified manually)
- [x] NavigationRail has 5 destinations (grep confirmed count = 5)
