---
phase: 02-agent-api-bridge
plan: 03
subsystem: ui
tags: [flutter, riverpod, window_manager, agent-api, navigation-rail, go_router]

# Dependency graph
requires:
  - phase: 02-agent-api-bridge/02-02
    provides: "Rust FRB bridge functions for agent server lifecycle and API key management"
provides:
  - "AgentServerNotifier: Riverpod AsyncNotifier for agent server start/stop/auto-start with SharedPreferences persistence"
  - "AgentKeyNotifier: Riverpod Notifier for API key CRUD wrapping FRB bridge"
  - "lib/providers/agent_provider.dart: complete provider file with convenience providers"
  - "lib/src/rust/api/agent.dart: typed FRB stub for agent bridge functions"
  - "5th NavigationRail destination: Agent API with Icons.lan_outlined/Icons.lan"
  - "/agent-api GoRoute in ShellRoute pointing to AgentApiScreen placeholder"
  - "WindowListener in _AppShellState: onWindowClose() stops server then destroys window (INFR-08)"
  - "Wave 0 test scaffolds: agent_api_screen_test.dart and agent_provider_test.dart"
affects: [02-04-agent-api-ui, testing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AsyncNotifier<AgentServerState> for server lifecycle with auto-start gate on wallet availability"
    - "WindowListener mixin on ConsumerStatefulWidget for graceful shutdown hook"
    - "Typed stub pattern for FRB agent.dart (parallel to auth.dart stub)"

key-files:
  created:
    - lib/providers/agent_provider.dart
    - lib/src/rust/api/agent.dart
    - lib/features/agent/agent_api_screen.dart
    - test/agent_api_screen_test.dart
    - test/agent_provider_test.dart
  modified:
    - lib/shared/app_shell.dart
    - lib/routing/app_router.dart

key-decisions:
  - "AgentServerState uses const named constructors (.stopped(), .running(port), .error(msg)) for clean pattern-matching in UI"
  - "Auto-start in build() gates on BOTH agent_server_enabled pref AND activeWalletProvider != null (Pitfall 6 from RESEARCH.md)"
  - "WindowListener.onWindowClose calls forceStop() (no pref update) then windowManager.destroy() — preference unchanged so next launch restores auto-start"
  - "lib/src/rust/api/agent.dart created as typed stub (UnimplementedError) per established auth.dart pattern"

patterns-established:
  - "forceStop() vs toggleServer(false): forceStop is for process exit (no pref write), toggleServer is for user toggling (writes pref)"
  - "AgentKeyNotifier refreshes list synchronously after each mutation (createKey/revokeKey)"

requirements-completed: [AGNT-01, AGNT-14, AGNT-15, INFR-08]

# Metrics
duration: 3min
completed: 2026-03-17
---

# Phase 2 Plan 03: Agent API Flutter Providers and Navigation Summary

**Riverpod AsyncNotifier for agent server lifecycle + WindowListener shutdown hook + Agent API as 5th NavigationRail destination wired to GoRouter**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-17T05:45:06Z
- **Completed:** 2026-03-17T05:47:46Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- AgentServerNotifier wraps FRB bridge with auto-start guard (wallet + keys both required) and SharedPreferences persistence
- NavigationRail updated to 5 destinations with Agent API (lan icon) at index 3; Settings shifts to index 4
- WindowListener mixin on _AppShellState calls forceStop() then windowManager.destroy() on window close (INFR-08)
- Wave 0 test scaffolds created for AGNT-14 (widget) and AGNT-15 (provider state model tests)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create agent_provider.dart with server and key management state** - `b3d866a` (feat)
2. **Task 2: Add Agent API to NavigationRail, GoRouter, and window close lifecycle** - `c6ee185` (feat)
3. **Task 3: Create Wave 0 Flutter test scaffolds for AGNT-14 and AGNT-15** - `8c096ec` (test)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `lib/providers/agent_provider.dart` - AgentServerNotifier, AgentKeyNotifier, agentServerProvider, agentKeyProvider, hasApiKeysProvider, apiKeyCountProvider
- `lib/src/rust/api/agent.dart` - Typed stub with AgentStatusEvent, ApiKeyEntry, and all bridge functions throwing UnimplementedError
- `lib/features/agent/agent_api_screen.dart` - Placeholder ConsumerWidget (Plan 04 replaces with full UI)
- `lib/shared/app_shell.dart` - 5th nav destination (Agent API), WindowListener mixin, onWindowClose lifecycle
- `lib/routing/app_router.dart` - /agent-api GoRoute added to ShellRoute
- `test/agent_api_screen_test.dart` - Wave 0 widget smoke test for AGNT-14
- `test/agent_provider_test.dart` - Wave 0 provider state model tests for AGNT-15

## Decisions Made

- AgentServerState uses const named constructors (.stopped(), .running(port), .error(msg)) for clean pattern-matching
- Auto-start in build() gates on BOTH agent_server_enabled pref AND activeWalletProvider != null (Pitfall 6 from RESEARCH.md)
- WindowListener.onWindowClose calls forceStop() (no pref update) then windowManager.destroy() — preference unchanged so next launch restores auto-start
- lib/src/rust/api/agent.dart created as typed stub (UnimplementedError) per established auth.dart pattern

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Provider layer and navigation wiring complete; Plan 04 can build the full AgentApiScreen UI consuming agentServerProvider and agentKeyProvider
- AgentApiScreen placeholder resolves the GoRouter import immediately; Plan 04 replaces the placeholder with the full implementation
- Both test scaffolds include TODO markers for FRB codegen mocking after toolchain is available

## Self-Check: PASSED

All 7 created/modified files verified on disk. All 3 task commits verified in git log (b3d866a, c6ee185, 8c096ec).

---
*Phase: 02-agent-api-bridge*
*Completed: 2026-03-17*
