---
phase: 05-esp32-firmware-rewrite
plan: 03
subsystem: ui
tags: [flutter, riverpod, go_router, navigation-rail, serial-usb, hardware-wallet, stream-provider]

# Dependency graph
requires:
  - phase: 05-esp32-firmware-rewrite plan 02
    provides: FRB bridge stub pattern for hardware functions (getHardwarePubkey et al)
  - phase: 05-esp32-firmware-rewrite
    provides: walletListProvider (WalletInfoDto with source field) for hardware wallet lookup
provides:
  - hardwareConnectionProvider — StreamProvider.autoDispose polling every 5s emitting HwConnectionInfo
  - HwConnState enum with 4 states (notPaired, disconnected, connected, pubkeyMismatch)
  - HwConnectionInfo immutable state class (state, deviceName, address, portPath)
  - Hardware Wallet NavigationRail destination (6th rail item) with 4-state icon rendering
  - Hardware Wallet permanent drawer entry with 3-state rendering
  - /hardware route in ShellRoute GoRouter
  - Disconnect snackbar listener in AppShell
  - hardware_wallet_screen.dart placeholder for Plan 04 to build on
  - hardware_stubs.dart with typed stubs: getHardwarePubkey, generateHardwareKeypair, factoryResetHardware, checkHardwareEntropy
affects:
  - 05-esp32-firmware-rewrite plan 04 (device dashboard and mnemonic screens build on this)
  - lib/shared/app_shell.dart (modified — any future NavigationRail changes)
  - lib/shared/widgets/wallet_drawer.dart (modified — any future drawer changes)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - StreamProvider.autoDispose with Stream.periodic for 5-second polling
    - hardware_stubs.dart pattern — separate file for pre-codegen stubs (keeps auto-generated hardware.dart clean)
    - _buildHwNavIcon() helper method for stateful icon rendering in NavigationRail
    - ref.listen for cross-provider state transition side effects (disconnect snackbar)

key-files:
  created:
    - lib/providers/hardware_connection_provider.dart
    - lib/src/rust/api/hardware_stubs.dart
    - lib/features/hardware/hardware_wallet_screen.dart
  modified:
    - lib/shared/app_shell.dart
    - lib/shared/widgets/wallet_drawer.dart
    - lib/routing/app_router.dart

key-decisions:
  - "hardware_stubs.dart created as separate file (not modifying hardware.dart) — hardware.dart is FRB auto-generated, following established auth.dart/agent.dart stub pattern"
  - "hardwareConnectionProvider replaces hwDetectedProvider in wallet_drawer.dart — richer state object vs boolean, no parallel providers"
  - "hw_stubs.getHardwarePubkey imported via hardware_stubs.dart alias — keeps stub import distinct from hw_bridge alias pointing to auto-generated hardware.dart"

patterns-established:
  - "hardware_stubs.dart pattern: separate hand-written stub file for pre-codegen bridge functions on auto-generated API files"
  - "StreamProvider.autoDispose + Stream.periodic pattern for 5-second USB polling without timer leaks"
  - "_buildHwNavIcon() helper: exhaustive switch on enum for NavigationRail icon state rendering"

requirements-completed: [HWLT-01, HWLT-02, HWLT-06]

# Metrics
duration: 3min
completed: 2026-03-20
---

# Phase 5 Plan 03: Hardware Connection Provider + Sidebar Infrastructure Summary

**Reactive hardware wallet connection polling via StreamProvider driving 3-state NavigationRail and drawer entries, with disconnect snackbar and /hardware route**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-20T08:29:20Z
- **Completed:** 2026-03-20T08:32:26Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Created `hardwareConnectionProvider` as `StreamProvider.autoDispose` polling every 5 seconds — emits `HwConnectionInfo` with 4 states (notPaired, disconnected, connected, pubkeyMismatch)
- Added permanent Hardware Wallet NavigationRail destination (index 4, before Settings) with 4-state icon rendering via `_buildHwNavIcon()` helper
- Added permanent Hardware Wallet drawer entry with 3-state rendering (Setup badge, gray USB, primary USB + green dot) navigating to `/hardware`
- Replaced `hwDetectedProvider` (boolean) in `wallet_drawer.dart` with richer `hardwareConnectionProvider`
- Disconnect snackbar fires via `ref.listen` when state transitions `connected → disconnected`
- Created `hardware_stubs.dart` with typed stubs for 4 new bridge functions (getHardwarePubkey, generateHardwareKeypair, factoryResetHardware, checkHardwareEntropy) — keeps auto-generated `hardware.dart` unmodified

## Task Commits

1. **Task 1: Create hardware connection polling provider** — `0a68eb5` (feat)
2. **Task 2: Add Hardware Wallet sidebar entry, /hardware route, disconnect snackbar** — `e8cade8` (feat)

## Files Created/Modified

- `lib/providers/hardware_connection_provider.dart` — HwConnState enum, HwConnectionInfo class, hardwareConnectionProvider StreamProvider
- `lib/src/rust/api/hardware_stubs.dart` — typed stubs for getHardwarePubkey, generateHardwareKeypair, factoryResetHardware, checkHardwareEntropy
- `lib/features/hardware/hardware_wallet_screen.dart` — placeholder ConsumerWidget for Plan 04
- `lib/shared/app_shell.dart` — added hardwareConnectionProvider watch, disconnect snackbar listener, _buildHwNavIcon(), Hardware Wallet NavigationRailDestination, updated _routes
- `lib/shared/widgets/wallet_drawer.dart` — replaced hwDetectedProvider with hardwareConnectionProvider, added permanent Hardware Wallet ListTile
- `lib/routing/app_router.dart` — added /hardware GoRoute in ShellRoute

## Decisions Made

- `hardware_stubs.dart` created as a separate file rather than modifying `hardware.dart` — `hardware.dart` is auto-generated by flutter_rust_bridge (contains `// This file is automatically generated`) and must not be hand-edited. Follows the established auth.dart/agent.dart stub pattern from Phases 01-02.
- `hwDetectedProvider` removed from `wallet_drawer.dart` — `hardwareConnectionProvider` provides a richer state object covering all connection states, making the simpler boolean provider redundant.
- `hw_stubs` import alias used for `hardware_stubs.dart` to distinguish from `hw_bridge` alias on auto-generated `hardware.dart`.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 04 can now build the full `HardwareWalletScreen` implementation on top of `hardwareConnectionProvider` and the `/hardware` route scaffold
- `hardware_stubs.dart` provides compile-time-safe stubs for all bridge functions Plan 04 will need (getHardwarePubkey, generateHardwareKeypair, factoryResetHardware, checkHardwareEntropy)
- NavigationRail has 6 destinations; `_routes` array updated to match — index integrity maintained

---
*Phase: 05-esp32-firmware-rewrite*
*Completed: 2026-03-20*
