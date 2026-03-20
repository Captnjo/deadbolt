---
phase: 05-esp32-firmware-rewrite
plan: 04
subsystem: ui
tags: [flutter, riverpod, go_router, hardware-wallet, mnemonic, no_screenshot]

requires:
  - phase: 05-03
    provides: hardwareConnectionProvider with 4-state HwConnectionInfo, hardware_stubs.dart
  - phase: 05-02
    provides: Rust bridge stubs for generateHardwareKeypair, factoryResetHardware, getHardwarePubkey
provides:
  - HardwareWalletScreen (device dashboard) with notPaired/disconnected/connected/pubkeyMismatch sub-states
  - MnemonicDisplayScreen (one-shot 12-word display with screenshot prevention)
  - MnemonicQuizScreen (3-question ChoiceChip verification quiz with auto-advance)
  - /hardware/mnemonic and /hardware/quiz routes in app_router.dart
affects: [05-05, Phase 06, hardware signing flow]

tech-stack:
  added: [no_screenshot ^1.0.0]
  patterns:
    - hw_stubs import pattern: import hardware.dart for scan/connect, hardware_stubs.dart for generate/reset/pubkey
    - context.go() enforced throughout hardware flow (no context.pop()) to prevent back-navigation to mnemonic
    - Screenshot prevention: NoScreenshot.instance.screenshotOff() in initState, screenshotOn() in dispose

key-files:
  created:
    - lib/features/hardware/mnemonic_display_screen.dart
    - lib/features/hardware/mnemonic_quiz_screen.dart
  modified:
    - lib/features/hardware/hardware_wallet_screen.dart
    - lib/routing/app_router.dart
    - pubspec.yaml

key-decisions:
  - "hw_stubs imported separately in hardware_wallet_screen — hardware.dart (FRB-generated) has scan/connect only; generate/reset/pubkey are in hardware_stubs.dart"
  - "getHardwarePubkey called in _handleReregister to confirm device responds before de-registering old address (not to store the value — just side-effect confirmation)"
  - "MnemonicQuizScreen distractors sourced from other mnemonic words — no BIP39 wordlist available in Dart pre-codegen; simpler and functionally equivalent"

patterns-established:
  - "One-shot mnemonic flow: screenshotOff in initState + no back button + context.go to /hardware on completion"
  - "Quiz auto-advance: _handleAnswer checks all answers answered then verifies all correct before calling _onQuizPassed"
  - "Hardware wallet dashboard switch pattern: _buildContent(hwConn) switch returns List<Widget> per HwConnState"

requirements-completed: [HWLT-03, HWLT-04, HWLT-05, HWLT-06]

duration: 18min
completed: 2026-03-20
---

# Phase 05 Plan 04: Hardware Wallet Flutter UI Summary

**Device dashboard with 4 connection sub-states, one-shot screenshot-blocked mnemonic display, and 3-position ChoiceChip verification quiz completing the hardware wallet Flutter UI**

## Performance

- **Duration:** 18 min
- **Started:** 2026-03-20T09:00:00Z
- **Completed:** 2026-03-20T09:18:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Hardware wallet dashboard (`hardware_wallet_screen.dart`) handles all 4 `HwConnState` values with correct action buttons per state: Connect Device, Reconnect/Factory Reset, Generate/Disconnect/Factory Reset, Re-register/Disconnect
- Factory reset goes through the full security chain: auth challenge dialog → AlertDialog confirmation with "permanently erase the device's private key" copy → bridge call → wallet list removal → provider invalidation
- Pubkey mismatch shows persistent warning banner with `BrandColors.error.withAlpha(15)` fill blocking re-use until resolved
- Mnemonic display (`mnemonic_display_screen.dart`) enables screenshot prevention via `no_screenshot` package, shows 12 words in MnemonicGrid with warning border, omits clipboard button per hardware wallet security design
- Mnemonic quiz (`mnemonic_quiz_screen.dart`) generates 3 random positions, 4 ChoiceChip options each; auto-advances on all correct, resets answers on any incorrect with error container
- All navigation uses `context.go()` — prevents user navigating back to see mnemonic words after proceeding

## Task Commits

Each task was committed atomically:

1. **Task 1: Hardware Wallet device dashboard screen with 4 sub-states** - `0a68fac` (feat)
2. **Task 2: Mnemonic display and quiz screens** - `1fe510d` (feat)

## Files Created/Modified

- `lib/features/hardware/hardware_wallet_screen.dart` - Full ConsumerStatefulWidget replacing placeholder; 4-state dashboard with all action handlers
- `lib/features/hardware/mnemonic_display_screen.dart` - One-shot mnemonic display with screenshot prevention; no clipboard button
- `lib/features/hardware/mnemonic_quiz_screen.dart` - 3-question ChoiceChip quiz with auto-advance and wallet registration on pass
- `lib/routing/app_router.dart` - Added /hardware/mnemonic and /hardware/quiz sub-routes with parentNavigatorKey: _rootNavigatorKey
- `pubspec.yaml` - Added no_screenshot: ^1.0.0 dependency

## Decisions Made

- **hw_stubs imported separately**: `hardware.dart` (FRB-generated) only has `scanHardwareWallets` and `connectHardwareWallet`. Functions added in Phase 02 (`generateHardwareKeypair`, `factoryResetHardware`, `getHardwarePubkey`) live in `hardware_stubs.dart`. Both files are imported in `hardware_wallet_screen.dart`.
- **getHardwarePubkey in _handleReregister**: Called to confirm device responds before de-registering the old wallet address. The returned value is discarded — the side-effect (device communication confirmation) is the goal.
- **Quiz distractors from mnemonic words**: BIP39 wordlist not available in Dart pre-codegen. Using other words from the same mnemonic as distractors is simpler and functionally equivalent for verifying the user recorded the correct phrase.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] hw_stubs.dart import added alongside hardware.dart**
- **Found during:** Task 1 (hardware_wallet_screen.dart implementation)
- **Issue:** Plan's import block only listed `hardware.dart as hw_bridge`, but that file only has `scanHardwareWallets` and `connectHardwareWallet`. The plan's action code calls `hw_bridge.generateHardwareKeypair`, `hw_bridge.factoryResetHardware`, `hw_bridge.getHardwarePubkey` — these live in `hardware_stubs.dart`.
- **Fix:** Added `import '../../src/rust/api/hardware_stubs.dart' as hw_stubs;` and used `hw_stubs.*` for those three calls (matching the pattern in `hardware_connection_provider.dart`)
- **Files modified:** lib/features/hardware/hardware_wallet_screen.dart
- **Verification:** All function calls resolve to correct stub file
- **Committed in:** 0a68fac (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug in plan's import spec vs actual FRB-generated file contents)
**Impact on plan:** Required to resolve; no scope change.

## Issues Encountered

None beyond the import fix above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All three hardware wallet Flutter screens are complete and routed
- `/hardware`, `/hardware/mnemonic`, and `/hardware/quiz` routes are live
- `no_screenshot` package added to pubspec.yaml — requires `flutter pub get` before next build
- Hardware wallet UI is ready for Phase 05-05 (integration wiring / signing flow) once FRB codegen runs to replace stubs

## Self-Check: PASSED

- FOUND: lib/features/hardware/hardware_wallet_screen.dart
- FOUND: lib/features/hardware/mnemonic_display_screen.dart
- FOUND: lib/features/hardware/mnemonic_quiz_screen.dart
- FOUND: .planning/phases/05-esp32-firmware-rewrite/05-04-SUMMARY.md
- FOUND commit: 0a68fac (Task 1 - hardware wallet dashboard)
- FOUND commit: 1fe510d (Task 2 - mnemonic display + quiz)

---
*Phase: 05-esp32-firmware-rewrite*
*Completed: 2026-03-20*
