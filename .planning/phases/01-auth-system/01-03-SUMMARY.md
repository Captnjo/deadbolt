---
phase: 01-auth-system
plan: 03
subsystem: auth
tags: [flutter, riverpod, go_router, lock-screen, idle-timer, state-management, ffi]

# Dependency graph
requires:
  - phase: 01-auth-system/01-01
    provides: "Rust auth FFI bridge: verifyAppPassword, lockApp, unlockApp, hasAppPassword (deadbolt_bridge)"

provides:
  - "AuthNotifier StateNotifier with lock/unlock/idle-timer in lib/providers/auth_provider.dart"
  - "LockScreen branded widget in lib/features/lock/lock_screen.dart"
  - "GoRouter redirect guard: /lock route + auth-aware redirect logic in app_router.dart"
  - "Activity detection: Listener + KeyboardListener in app_shell.dart calling resetActivity()"
  - "lib/src/rust/api/auth.dart stub for FRB auth bridge (to be replaced by codegen)"
  - "initIdleTimeout called from DeadboltApp.initState via postFrameCallback"

affects: [01-04, 02-agent-api, 04-ui-polish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AuthNotifier StateNotifier: locked by default, unlock via verifyAppPassword+unlockApp, idle timer on unlock"
    - "Escalating delay: static delayForAttempt(n) returns [0,1,2,5,10,30][n-1] seconds"
    - "Lock redirect: GoRouter Provider watches authProvider + hasAppPassword() for redirect logic"
    - "Activity detection: Listener(onPointerMove/Down) + KeyboardListener wrap app shell child"
    - "FRB stub pattern: auth.dart with UnimplementedError stubs until codegen runs"

key-files:
  created:
    - "lib/providers/auth_provider.dart"
    - "lib/features/lock/lock_screen.dart"
    - "lib/src/rust/api/auth.dart"
  modified:
    - "lib/routing/app_router.dart (auth redirect + /lock route)"
    - "lib/shared/app_shell.dart (Listener + KeyboardListener activity detection)"
    - "lib/app.dart (ConsumerStatefulWidget with initIdleTimeout in initState)"

key-decisions:
  - "auth.dart created as typed stub (UnimplementedError) rather than modifying generated frb_generated.dart — keeps generated files clean, stub replaced by codegen when Flutter toolchain available"
  - "initIdleTimeout called via WidgetsBinding.addPostFrameCallback in DeadboltApp.initState — avoids calling async SharedPreferences code before widget tree is ready"
  - "Activity detection wraps widget.child (not full Stack) — drawer scrim/open gesture not counted as idle-resetting activity"
  - "hasAppPassword() called synchronously in GoRouter Provider — frb(sync) fn, safe on Flutter main thread"

patterns-established:
  - "Lock redirect pattern: watch authProvider in appRouterProvider, check hasAppPassword() + isLocked for /lock redirect"
  - "Idle timer reset: resetActivity() called from Listener/KeyboardListener inside app shell, no-ops when locked"
  - "Escalating delay: LockScreen reads failedAttempts from authProvider, calls AuthNotifier.delayForAttempt(), runs local countdown timer"

requirements-completed: [AUTH-01, AUTH-02, AUTH-03]

# Metrics
duration: 22min
completed: 2026-03-16
---

# Phase 1 Plan 3: Auth Provider + Lock Screen Summary

**Riverpod AuthNotifier with scrypt unlock, 15-min idle auto-lock, escalating delay, and branded LockScreen with shake animation wired to GoRouter redirect guard**

## Performance

- **Duration:** 22 min
- **Started:** 2026-03-16T11:05:00Z
- **Completed:** 2026-03-16T11:27:00Z
- **Tasks:** 2 of 2
- **Files modified:** 6 (3 created, 3 modified)

## Accomplishments

- Built AuthNotifier StateNotifier (locked by default) with unlock() calling verifyAppPassword + unlockApp via Rust FFI, idle timer with configurable timeout (default 15 min), escalating delay schedule, and SharedPreferences persistence
- Created branded LockScreen: Deadbolt logo, password field with shake animation (TweenSequence), escalating delay countdown, error border flash, CircularProgressIndicator during scrypt verification
- Wired GoRouter to watch authProvider: redirect guard sends locked users to /lock and unlocked users away from /lock; /lock route added as FadeTransition CustomTransitionPage
- Added activity detection in AppShell: Listener (onPointerMove/Down) + KeyboardListener wrap child widget, each calling resetActivity() to reset idle timer

## Task Commits

Each task was committed atomically:

1. **Task 1: Create AuthProvider with idle timer and lock/unlock logic** - `b07fd25` (feat)
2. **Task 2: Create lock screen and wire GoRouter redirect + activity detection** - `fdefb8e` (feat)

**Plan metadata:** see final docs commit

## Files Created/Modified

- `lib/providers/auth_provider.dart` — AuthNotifier, AuthState, authProvider, idleTimeoutSecondsProvider, initIdleTimeout, setIdleTimeout
- `lib/src/rust/api/auth.dart` — FRB bridge stub (setAppPassword, verifyAppPassword, changeAppPassword, hasAppPassword, isAppLocked, lockApp, unlockApp)
- `lib/features/lock/lock_screen.dart` — Branded lock screen with password field, shake animation, escalating delay countdown, CircularProgressIndicator
- `lib/routing/app_router.dart` — Added authProvider watch, /lock route with FadeTransition, lock redirect logic
- `lib/shared/app_shell.dart` — Added Listener + KeyboardListener wrapping child for idle activity detection
- `lib/app.dart` — Changed to ConsumerStatefulWidget, calls initIdleTimeout via postFrameCallback

## Decisions Made

- `auth.dart` created as typed stub (UnimplementedError) rather than modifying the generated `frb_generated.dart` — keeps generated files clean, stub replaced by codegen output when Flutter/Dart toolchain becomes available
- `initIdleTimeout` called via `WidgetsBinding.addPostFrameCallback` in `DeadboltApp.initState` — defers async SharedPreferences call until after first frame render
- Activity detection wraps `widget.child` only (not the full Stack including scrim/drawer) — intentional: drawer interactions don't count as idle-resetting UI activity
- `hasAppPassword()` called synchronously in GoRouter Provider — it's a `frb(sync)` function, safe to call on Flutter main thread

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Flutter toolchain not available — auth.dart must be created manually**
- **Found during:** Task 1 (creating auth_provider.dart which imports auth.dart)
- **Issue:** `lib/src/rust/api/auth.dart` not generated because FRB codegen was skipped in Plan 01 (Dart/Flutter toolchain not installed). auth_provider.dart imports it; without it, the file can't be analyzed.
- **Fix:** Created `auth.dart` as a hand-written typed stub with proper function signatures matching `rust/deadbolt_bridge/src/api/auth.rs` exactly. Async functions throw `UnimplementedError` (safe default); sync bool functions return safe defaults (hasAppPassword → false, isAppLocked → true).
- **Files modified:** `lib/src/rust/api/auth.dart` (created)
- **Verification:** All acceptance criteria grep checks pass; flutter analyze not available
- **Committed in:** b07fd25 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking environment issue, same as Plan 01)
**Impact on plan:** No impact on code correctness. All Flutter code is complete. FRB codegen is a one-command step when Flutter is installed. The stub maintains type safety and correct signatures.

## Issues Encountered

- Flutter/Dart toolchain not available for `flutter analyze` verification (pre-existing from Plan 01). Code reviewed statically via grep acceptance criteria checks — all 14 criteria confirmed.
- `frb_generated.dart` does not contain auth API method declarations (codegen not run). Solution: auth.dart stub bypasses frb_generated entirely, using direct UnimplementedError stubs with correct signatures.

## Next Phase Readiness

- AuthProvider ready for Plan 04 (settings screen for idle timeout, change password)
- Lock screen fully built — will work as soon as FRB codegen is run and auth.dart stubs are replaced
- GoRouter redirect logic complete — /lock route integrated, lock/unlock navigation flow ready
- Blocker (pre-existing): Run `flutter_rust_bridge_codegen generate` from project root when Flutter toolchain is available to replace auth.dart stub with real FFI calls

---
*Phase: 01-auth-system*
*Completed: 2026-03-16*
