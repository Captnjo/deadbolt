---
phase: 01-auth-system
plan: 04
subsystem: auth
tags: [flutter, riverpod, password, onboarding, strength-meter, widget, ffi]

# Dependency graph
requires:
  - phase: 01-auth-system/01-01
    provides: "Rust auth module with setAppPassword FFI + auth.dart stub"
provides:
  - "PasswordStrengthMeter widget: reusable 4px bar with Weak/Fair/Strong labels in brand colors"
  - "SetPasswordStep: ConsumerStatefulWidget in onboarding wizard with validation and FFI call"
  - "OnboardingStep.setPassword: inserted after welcome, before walletName for all three paths"
  - "advanceFromPassword: calls auth_bridge.setAppPassword then advances to walletName"
  - "Password stored in OnboardingState temporarily, cleared on completeOnboarding"
affects: [04-ui]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Nullable field with explicit-null semantics (same pattern as 'error'): password cleared on any copyWith without it"
    - "Opacity 0.5 on ElevatedButton when disabled (can't pass null onPressed to themed button cleanly)"
    - "Semantics(label:) wrapper on visibility-toggle IconButton for accessibility"

key-files:
  created:
    - "lib/features/lock/widgets/password_strength_meter.dart"
    - "lib/features/onboarding/steps/set_password_step.dart"
  modified:
    - "lib/providers/onboarding_provider.dart (setPassword step, advanceFromPassword, password field)"
    - "lib/features/onboarding/onboarding_shell.dart (added SetPasswordStep case)"

key-decisions:
  - "password field in OnboardingState uses explicit-null pattern (no ??): clears on any copyWith without it — more secure, matches error field convention"
  - "Opacity(0.5) wrapper for disabled Continue button: theme's ElevatedButton disables tap but theme color overrides onPressed: null styling"
  - "PasswordStrengthMeter returns SizedBox.shrink() for empty string: no meter shown until user starts typing"

patterns-established:
  - "Strength meter: 4px ClipRRect bar with Stack[grey background + FractionallySizedBox foreground]"
  - "SetPasswordStep: local _loading state + notifier async call with catch; notifier also has its own error for provider-level errors"

requirements-completed: [AUTH-07, AUTH-08]

# Metrics
duration: 9min
completed: 2026-03-16
---

# Phase 1 Plan 4: Password Creation Step — Onboarding Wizard Summary

**Password creation step injected into all three onboarding paths (create/import/hardware) with PasswordStrengthMeter widget, blocking Continue until 8+ chars + match, and setAppPassword FFI call before wallet creation**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-03-16T10:52:10Z
- **Completed:** 2026-03-16T11:01:16Z
- **Tasks:** 2 of 2
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments

- Built `PasswordStrengthMeter`: reusable 4px horizontal bar using Stack + FractionallySizedBox; evaluateStrength() scores hasUpper/hasLower/hasDigit/hasSpecial; colors #E2A93B/Weak, #2ECC71/Fair, #F87040/Strong
- Created `SetPasswordStep`: full UI with password + confirm fields, visibility toggles, inline strength meter, inline error (only shown post-submit attempt), disabled Continue button at opacity 0.5 until >=8 chars + match
- Updated `OnboardingNotifier`: `setPassword` enum value, `advanceFromPassword` async method calling `auth_bridge.setAppPassword`, `choosePath` routing to `setPassword` first, `back()` navigation updated, `password` field cleared in `completeOnboarding`
- Pitfall 4 prevented: `setPassword` is in ALL three path lists BEFORE `walletName`/`displayMnemonic`/`detectDevice` — no wallet can be created before password is set

## Task Commits

Each task was committed atomically:

1. **Task 1: Create PasswordStrengthMeter widget** - `571c598` (feat)
2. **Task 2: Create SetPasswordStep and update OnboardingNotifier** - `d2a55f7` (feat)

**Plan metadata:** see final docs commit

## Files Created/Modified

- `lib/features/lock/widgets/password_strength_meter.dart` - PasswordStrength enum, evaluateStrength(), PasswordStrengthMeter widget
- `lib/features/onboarding/steps/set_password_step.dart` - SetPasswordStep ConsumerStatefulWidget with full validation UI
- `lib/providers/onboarding_provider.dart` - Added setPassword step, password field, advanceFromPassword, updated choosePath/back/completeOnboarding
- `lib/features/onboarding/onboarding_shell.dart` - Added SetPasswordStep import and switch case

## Decisions Made

- `password` field in `OnboardingState` uses the same explicit-null copyWith pattern as `error`: any `copyWith` call that omits `password` will set it to null. This is more secure (password doesn't linger across state updates) and matches the existing error field convention.
- `Opacity(0.5)` wrapper for the disabled Continue button instead of relying on `onPressed: null` alone — the theme's ElevatedButton disables pointer events on `null` but the visual styling can be inconsistent with Material 3; explicit opacity is unambiguous.
- `PasswordStrengthMeter` returns `SizedBox.shrink()` when password is empty: no meter shown until the user starts typing, avoiding a jarring "Weak" label on an empty field.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Flutter/Dart toolchain not in execution environment (same as plan 01-01). `flutter analyze` could not be run. Code correctness verified manually against all acceptance criteria. `lib/src/rust/api/auth.dart` stub was already present from a prior plan — used as-is.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Password creation step fully wired into onboarding wizard for all three paths
- `PasswordStrengthMeter` is a standalone reusable widget available at `lib/features/lock/widgets/password_strength_meter.dart`
- Blocker from 01-01 still applies: run `flutter_rust_bridge_codegen generate` in Flutter environment to activate real FFI — until then, the Continue button in SetPasswordStep will display the UnimplementedError from the stub
- Phase 01-05 (lock screen) can reuse `PasswordStrengthMeter` if needed for password change flow

---

## Self-Check: PASSED

Files verified on disk:
- FOUND: lib/features/lock/widgets/password_strength_meter.dart
- FOUND: lib/features/onboarding/steps/set_password_step.dart
- FOUND: .planning/phases/01-auth-system/01-04-SUMMARY.md

Commits verified in git log:
- FOUND: 571c598 - feat(01-04): create PasswordStrengthMeter widget
- FOUND: d2a55f7 - feat(01-04): add SetPasswordStep to onboarding and update OnboardingNotifier

---
*Phase: 01-auth-system*
*Completed: 2026-03-16*
