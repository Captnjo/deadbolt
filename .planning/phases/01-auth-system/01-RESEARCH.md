# Phase 1: Auth System - Research

**Researched:** 2026-03-16
**Domain:** Flutter (Riverpod/GoRouter) + Rust (scrypt/zeroize/atomic) auth wiring; macOS Keychain password hash storage; constant-time comparison; idle timeout
**Confidence:** HIGH — based on direct codebase inspection + prior architecture/pitfalls research

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Scope:** Wire vault unlock and app password gate into Flutter UI with idle auto-lock. Rust crypto infrastructure is complete — this phase builds Flutter auth UI, password management, idle timeout, and FFI bridge calls. Also includes constant-time bearer token comparison (INFR-06) and zeroization audit (INFR-07).

**Lock Screen UX:**
- Full branded splash screen on both launch and idle timeout (same screen for both)
- Deadbolt logo + tagline + password field at bottom on dark background
- Brand only — no wallet info visible until unlocked
- Wrong password: shake animation + escalating delay between attempts (1s, 2s, 5s, 10s, 30s...)
- No attempt lockout — just increasingly long delays

**Password Setup Flow:**
- Password created during onboarding (new step added to existing wizard, before wallet creation)
- Minimum 8 characters with visual strength meter (weak/fair/strong) + confirmation field
- Password hash stored in platform Keychain (macOS Keychain via security-framework, same pattern as existing vault key storage)
- No recovery mechanism — if forgotten, user must reset app and re-import wallets from mnemonic
- User can change password from Settings (requires current password first)

**Auth Challenge Behavior:**
- Password is NOT required for transaction signing — user already clicks Approve in the send/swap flow
- Password IS required for: reveal mnemonic, create/delete API key
- Password IS required to override/bypass guardrails
- Auth challenge appears as inline dialog (small modal over current screen), not full lock screen
- No grace period — every sensitive operation requires fresh password entry

**Idle Timeout Mechanics:**
- Default timeout: 15 minutes
- Timeout configurable in Settings
- Activity that resets timer: any mouse movement or key press inside the Deadbolt window
- On lock: Rust zeroizes all seeds from memory (lock_all_wallets), full lock screen shown
- Agent API server stays running while locked — query endpoints respond normally
- Agent signing requests queue up while locked — user reviews queue after unlocking
- Pending queue survives lock/unlock cycle

**Password is App-Wide:**
- One password unlocks the entire application
- On successful unlock: Rust unlocks ALL wallets (not just active)
- There is no per-wallet password concept
- Hardware wallets don't need password unlock (device-level auth via physical button)

### Claude's Discretion

- Exact lock screen animation/transition
- Password field styling details (show/hide toggle, etc.)
- Strength meter algorithm (zxcvbn or simpler)
- Scrypt parameters for password hashing (can reuse existing vault KDF strength)
- Timer implementation details (WidgetsBindingObserver vs other approach)
- How to handle window focus loss (minimize, switch away) — doesn't reset or trigger lock

### Deferred Ideas (OUT OF SCOPE)

- Touch ID / biometric unlock — v2 (AUTH-V2-01)
- Per-wallet passwords — not planned, app-wide password is the design
- Password recovery via mnemonic — considered and rejected for v1
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUTH-01 | User must enter app password to unlock wallet on launch | Lock screen + GoRouter redirect guard + verify_app_password FFI |
| AUTH-02 | Wallet auto-locks after configurable idle timeout (default 15 min) | AuthProvider idle timer + lock_all_wallets FFI + AtomicBool in Rust |
| AUTH-03 | User can configure idle timeout duration in settings | SharedPreferences for timeout value + Settings UI slider/picker |
| AUTH-04 | App password required to reveal mnemonic phrase | Auth challenge modal gating get_mnemonic FFI call |
| AUTH-05 | App password required to override guardrail blocks | Auth challenge modal before guardrail bypass (Phase 4 uses this hook) |
| AUTH-06 | App password required to create or delete an API key | Auth challenge modal gating API key operations |
| AUTH-07 | User can set and change app password in settings | Password change UI in Settings + change_app_password FFI |
| AUTH-08 | Password hash stored securely (scrypt-derived, not plaintext) | New Rust functions: set_app_password/verify_app_password storing scrypt hash in Keychain |
| INFR-06 | Bearer token comparison uses constant-time equality | Replace == with constant_time_eq in agent/auth.rs; add subtle or constant_time_eq crate |
| INFR-07 | Zeroization audit: all key material on heap (Box/SecretVec), no stack copies | Audit vault.rs, session.rs, mnemonic.rs; confirm Vec<u8> key paths use zeroize; migrate if needed |
</phase_requirements>

---

## Summary

This phase wires the existing Rust vault infrastructure into a user-facing auth system. The heavy cryptographic lifting (ChaCha20-Poly1305 encryption, scrypt KDF, SessionManager with zeroize-on-lock, macOS Keychain storage) is already implemented and tested. What is missing is: (1) Rust-side app password storage/verification using the existing scrypt + Keychain pattern, (2) a global app-locked `AtomicBool` that gates in-flight signing calls, (3) Flutter auth UI — lock screen, onboarding password step, inline auth challenge modal, idle timer, and Settings controls.

The auth architecture uses a Rust session token pattern: the password is verified in Rust, never stored in Dart, and the session state is owned by Rust. The Flutter `AuthProvider` (Riverpod `StateNotifier`) holds the _observable_ locked/unlocked state for UI purposes, but the authoritative enforcement is in Rust. The GoRouter redirect in `app_router.dart` is extended with a lock check alongside the existing onboarding check.

The two security hardening items (INFR-06, INFR-07) are surgical fixes: a one-line swap in `agent/auth.rs` for constant-time comparison, and an audit/migration of key-material heap allocation in the vault path.

**Primary recommendation:** Build five work units in sequence — (1) Rust auth layer (password hash storage + AtomicBool lock gate), (2) FFI bridge exposure of new auth functions, (3) Flutter AuthProvider + GoRouter lock redirect, (4) Lock screen UI + onboarding password step, (5) Auth challenge modal + Settings security section. Do INFR-06/INFR-07 as a sixth, parallel unit since it touches different files.

---

## Standard Stack

### Core (already in project — no new dependencies needed for auth)

| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| flutter_rust_bridge | 2.11.1 | FFI between Dart and Rust | Already in pubspec + bridge crate |
| flutter_riverpod | ^2.5.1 | State management (AuthProvider) | Already in pubspec |
| go_router | ^14.2.0 | Navigation + redirect guard for lock screen | Already in pubspec |
| shared_preferences | ^2.2.0 | Persisting idle timeout duration (non-sensitive) | Already in pubspec |
| scrypt | 0.11 | KDF for password hash (reuse existing vault KDF) | Already in deadbolt_core Cargo.toml |
| zeroize | 1 | Zeroize secrets on lock/drop | Already in deadbolt_core Cargo.toml |
| security-framework | 3 | macOS Keychain storage for password hash | Already in deadbolt_core Cargo.toml |
| chacha20poly1305 | 0.10 | Vault encryption (existing; no change) | Already in deadbolt_core Cargo.toml |

### New Dependencies Required

| Library | Version | Purpose | Where |
|---------|---------|---------|-------|
| constant_time_eq | 0.3 | Constant-time byte comparison for INFR-06 | deadbolt_core Cargo.toml |

**Installation:**
```bash
# In rust/deadbolt_core/Cargo.toml [dependencies]:
constant_time_eq = "0.3"
```

No new Flutter dependencies are needed. The existing stack covers everything.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `constant_time_eq` crate | `subtle` crate's `ConstantTimeEq` | Both work; `constant_time_eq` is simpler API for raw byte slices; `subtle` is more feature-rich but overkill for this single use case |
| Storing password hash in Keychain | Storing in `~/.deadbolt/config.json` | Keychain is mandatory — config.json is readable by any process running as the user; password hash must be in Keychain consistent with existing vault key storage |
| `WidgetsBindingObserver` for idle timer | `window_manager` listener + `MouseRegion`/`KeyboardListener` | WidgetsBindingObserver only gives app lifecycle, not mouse/key activity; the CONTEXT.md requires mouse/key detection inside the window |

---

## Architecture Patterns

### Recommended Structure (new files only)

```
rust/deadbolt_core/src/
├── auth/                        # NEW module
│   ├── mod.rs                   # pub use; re-exports
│   ├── password.rs              # set_app_password, verify_app_password, change_app_password
│   └── lock_state.rs            # AtomicBool APP_LOCKED global + sign gate check

rust/deadbolt_bridge/src/api/
├── auth.rs                      # NEW: FRB-exposed auth functions

lib/
├── features/
│   ├── lock/
│   │   ├── lock_screen.dart     # NEW: branded lock screen widget
│   │   └── auth_challenge_dialog.dart  # NEW: inline modal for sensitive ops
│   └── settings/
│       └── security_settings_section.dart  # NEW: password change + timeout
├── providers/
│   └── auth_provider.dart       # NEW: AuthNotifier (session state + idle timer)
└── routing/
    └── app_router.dart          # MODIFY: add lock redirect
```

### Pattern 1: Rust-Side App Password Storage

**What:** App password is stored as a scrypt hash in the macOS Keychain, using the same `security-framework` API as vault keys but with a dedicated Keychain account key (`"app_password_hash"`). The hash format is the existing vault format: `[1B version][16B salt][12B nonce][ciphertext]` — reuse `vault::encrypt(hash_bytes, ...)` is wrong here; instead, the password hash is stored as `[16B salt][32B scrypt_output]` (48 bytes, no encryption layer needed — the hash IS the protection).

**When to use:** On first password creation (onboarding) and on password change (settings).

**Example:**
```rust
// In rust/deadbolt_core/src/auth/password.rs

use crate::crypto::vault::{derive_key, KdfStrength};
use crate::storage::KeychainStorage;
use crate::models::DeadboltError;
use zeroize::Zeroize;

const PASSWORD_HASH_ACCOUNT: &str = "app_password_hash";

/// Store app password: derive scrypt hash, store [salt || hash] in Keychain.
pub fn set_app_password(password: &[u8]) -> Result<(), DeadboltError> {
    let mut salt = [0u8; 16];
    getrandom::getrandom(&mut salt)
        .map_err(|e| DeadboltError::VaultError(format!("RNG: {e}")))?;

    let mut hash = derive_key(password, &salt, KdfStrength::Desktop)?;

    // Store 48 bytes: [16B salt || 32B hash]
    let mut stored = [0u8; 48];
    stored[..16].copy_from_slice(&salt);
    stored[16..].copy_from_slice(&hash);

    hash.zeroize();

    // Use security-framework directly — Keychain account key is fixed
    security_framework::passwords::set_generic_password(
        "com.deadbolt.wallet",
        PASSWORD_HASH_ACCOUNT,
        &stored,
    ).map_err(|e| DeadboltError::StorageError(e.to_string()))?;

    Ok(())
}

/// Verify password against stored hash. Returns Ok(()) on match, Err on mismatch.
pub fn verify_app_password(password: &[u8]) -> Result<(), DeadboltError> {
    let stored = security_framework::passwords::get_generic_password(
        "com.deadbolt.wallet",
        PASSWORD_HASH_ACCOUNT,
    ).map_err(|e| {
        if e.to_string().contains("-25300") {
            DeadboltError::StorageItemNotFound  // No password set yet
        } else {
            DeadboltError::StorageError(e.to_string())
        }
    })?;

    if stored.len() != 48 {
        return Err(DeadboltError::VaultError("Corrupt password hash".into()));
    }

    let salt = &stored[..16];
    let expected_hash = &stored[16..];

    let mut actual_hash = derive_key(password, salt, KdfStrength::Desktop)?;

    // Constant-time comparison (INFR-06 applies here too)
    let ok = constant_time_eq::constant_time_eq(&actual_hash, expected_hash);
    actual_hash.zeroize();

    if ok {
        Ok(())
    } else {
        Err(DeadboltError::VaultError("Invalid password".into()))
    }
}
```

### Pattern 2: AtomicBool Lock Gate in Rust (Pitfall 8 prevention)

**What:** A `static APP_LOCKED: AtomicBool` in the Rust auth module enforces lock state independently of Flutter UI state. Every signing call checks this flag before proceeding. Lock sets it `true`; successful unlock sets it `false`.

**When to use:** Must be checked in `get_active_signer()` and any other path that accesses seed material.

**Example:**
```rust
// In rust/deadbolt_core/src/auth/lock_state.rs

use std::sync::atomic::{AtomicBool, Ordering};

static APP_LOCKED: AtomicBool = AtomicBool::new(true);  // Locked at startup

pub fn set_locked(locked: bool) {
    APP_LOCKED.store(locked, Ordering::SeqCst);
}

pub fn is_app_locked() -> bool {
    APP_LOCKED.load(Ordering::SeqCst)
}

pub fn assert_unlocked() -> Result<(), crate::models::DeadboltError> {
    if APP_LOCKED.load(Ordering::SeqCst) {
        Err(crate::models::DeadboltError::WalletLocked)
    } else {
        Ok(())
    }
}
```

Then in `wallet_manager.rs`, `get_active_signer()` calls `auth::lock_state::assert_unlocked()?` before `self.session.get_signer(address)`.

### Pattern 3: AuthProvider (Flutter Riverpod)

**What:** `AuthNotifier extends StateNotifier<AuthState>` owns the idle timer and observable lock state. It calls Rust FFI on lock/unlock and manages the countdown timer using a `Timer.periodic` or `WidgetsBindingObserver`. The timer is reset on mouse/key activity via a `Listener` widget wrapping the app shell.

**When to use:** Wrap the root app shell. Every screen that needs to know if the user is locked reads `ref.watch(authProvider)`.

**Example:**
```dart
// lib/providers/auth_provider.dart

enum AuthStatus { locked, unlocked }

class AuthState {
  final AuthStatus status;
  final int failedAttempts;
  const AuthState({this.status = AuthStatus.locked, this.failedAttempts = 0});
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState());

  final Ref _ref;
  Timer? _idleTimer;

  int get _timeoutSeconds =>
      _ref.read(idleTimeoutSecondsProvider); // reads from SharedPreferences

  Future<void> unlock(String password) async {
    await auth.verifyAppPassword(password: password);  // throws on wrong pw
    await wallet.unlockAllWallets();                    // unlock all in Rust
    state = const AuthState(status: AuthStatus.unlocked, failedAttempts: 0);
    _resetIdleTimer();
  }

  void lock() {
    _idleTimer?.cancel();
    wallet.lockAllWallets();
    state = AuthState(status: AuthStatus.locked, failedAttempts: state.failedAttempts);
  }

  void recordFailedAttempt() {
    state = AuthState(status: AuthStatus.locked, failedAttempts: state.failedAttempts + 1);
  }

  void resetActivity() {
    if (state.status == AuthStatus.unlocked) _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(Duration(seconds: _timeoutSeconds), lock);
  }
}
```

### Pattern 4: GoRouter Lock Redirect

**What:** The existing `redirect` function in `app_router.dart` checks `needsOnboarding`. Extend it to also check `authStatus`. Lock screen lives at `/lock`.

**Example:**
```dart
// In app_router.dart redirect:
redirect: (context, state) {
  final onOnboarding = state.uri.path == '/onboarding';
  final onLock = state.uri.path == '/lock';

  if (needsOnboarding && !onOnboarding) return '/onboarding';
  if (!needsOnboarding && onOnboarding) return '/dashboard';

  if (!needsOnboarding && isLocked && !onLock) return '/lock';
  if (!needsOnboarding && !isLocked && onLock) return '/dashboard';

  return null;
},
```

Note: `appRouterProvider` must now also watch `authProvider` alongside `needsOnboardingProvider`.

### Pattern 5: Auth Challenge Modal

**What:** A reusable `showAuthChallengeDialog(context, ref, onSuccess)` function that shows a `showDialog` with a password field, verifies via Rust FFI, and calls `onSuccess()` on correct entry. Used for mnemonic reveal, API key operations, guardrail override.

**Example:**
```dart
Future<bool> showAuthChallengeDialog(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AuthChallengeDialog(),
  );
  return result ?? false;
}
```

### Pattern 6: Onboarding Password Step

**What:** Add `setPassword` step to `OnboardingStep` enum. It appears after `welcome` and before `walletName` (or between welcome and wallet path selection). The step collects password, shows strength meter, requires confirmation, calls `set_app_password` FFI on advance.

**Key change to `onboarding_provider.dart`:**
- Add `setPassword` to `OnboardingStep` enum
- Add `password` field to `OnboardingState`
- `_stepsForPath` adds `setPassword` as first step after `welcome` for all paths
- `advanceFromPassword()` method calls `setAppPassword(password)` FFI, then transitions to `walletName`

### Anti-Patterns to Avoid

- **Storing password in Dart state:** Never put the password in a Riverpod provider or `SharedPreferences`. The password must only exist in Dart memory for the duration of the FFI call, then go out of scope. (See Architecture research Pattern 3.)
- **Lock state only in Flutter:** The `AtomicBool` in Rust is mandatory. A lock that only lives in Flutter can be bypassed by any in-flight FFI call. (See PITFALLS.md Pitfall 8.)
- **Widget-based idle timer:** A `Timer` inside a widget class resets on hot reload and navigation. Use the `AuthNotifier` in Riverpod, which survives widget tree rebuilds. (See PITFALLS.md Integration Gotchas.)
- **`==` for token comparison:** The existing `agent/auth.rs` uses `valid_tokens.contains(&token.to_string())` which uses `==`. This must be replaced with `constant_time_eq` (INFR-06).
- **Unlocking only the active wallet:** On successful auth, call `lock_all_wallets` on lock and unlock ALL wallets on success. The app-wide password gates all wallets.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Password KDF | Custom hash | `derive_key()` from existing `vault.rs` with `KdfStrength::Desktop` | Already tuned scrypt params (log_n=17, Desktop); reusing avoids parameter drift |
| Keychain storage for password hash | Custom file storage | `security_framework::passwords::set_generic_password` (same crate already used) | Keychain provides OS-enforced access control; file storage is readable by any user process |
| Constant-time comparison | Manually XOR bytes | `constant_time_eq` crate | Hand-rolled constant-time is notoriously subtle to get right; crate is audited |
| Idle activity detection | Custom native plugin | `Listener` widget + `MouseRegion` on app shell | Flutter's `Listener` captures `onPointerMove`/`onPointerDown` which covers all mouse+touch activity |
| Lock screen routing | Custom Navigator manipulation | GoRouter redirect guard | Consistent with existing onboarding pattern; GoRouter handles edge cases like deep links |

**Key insight:** The entire cryptographic foundation for this phase exists. The work is integration (wiring FFI, adding UI) not implementation of new crypto primitives.

---

## Common Pitfalls

### Pitfall 1: AtomicBool Not Checked Before In-Flight Signing

**What goes wrong:** Idle timeout fires while a signing call is 5ms into execution. Flutter shows lock screen. Signing completes and submits transaction. From Pitfall 8 in PITFALLS.md — this is the most critical correctness issue in this phase.

**Why it happens:** Lock state lives in Flutter; signing lives in Rust. If the Rust signer does not consult an authoritative Rust-side lock flag, there is no enforcement boundary.

**How to avoid:** `AtomicBool APP_LOCKED` (static, initialized `true`). `get_active_signer()` calls `assert_unlocked()?` as its first line. The lock FFI function sets the flag before zeroizing seeds.

**Warning signs:** `get_active_signer()` in `wallet_manager.rs` does not reference any auth module. No `WalletLocked` variant in `DeadboltError`.

### Pitfall 2: Scrypt Running on Flutter Main Thread

**What goes wrong:** User enters password, app freezes for 400ms (Desktop scrypt params). On slower machines, this can be 800ms+. The UI appears hung.

**Why it happens:** FRB sync functions run on the calling Dart thread. `verify_app_password` with Desktop scrypt params is CPU-intensive.

**How to avoid:** Mark `verify_app_password` and `set_app_password` as `async fn` in the bridge (not `#[frb(sync)]`). FRB will run them on a worker thread. The Flutter side `await`s the result and shows a loading indicator on the lock screen button.

**Warning signs:** Bridge auth functions decorated with `#[frb(sync)]`.

### Pitfall 3: Timer Persists After Lock, Continues Firing

**What goes wrong:** `AuthNotifier.lock()` is called, but the idle `Timer` continues ticking. It fires again and calls `lock()` again (harmless, but signals broken cleanup). Worse: if the user unlocks and the old timer hasn't been cancelled, a stale timer fires mid-session and re-locks unexpectedly.

**How to avoid:** `lock()` calls `_idleTimer?.cancel()` before anything else. `unlock()` calls `_resetIdleTimer()` which always cancels the existing timer before starting a new one.

### Pitfall 4: Onboarding Password Step Added After Wallet Creation

**What goes wrong:** Password step added as the _last_ onboarding step (or after wallet creation). First-launch users create a wallet, then set the password. There's a window where the wallet exists but no password gate is enforced — `needs_onboarding()` returns false after wallet creation, so the router allows access to the app before a password is set.

**How to avoid:** Password step must be the FIRST step after welcome, before wallet creation. `needs_onboarding()` check should also check `has_app_password()` — if no password is set and there are wallets, redirect to a special password-setup route (for recovery from partially completed onboarding).

**Warning signs:** `onboarding_provider.dart` adds `setPassword` step anywhere after `displayMnemonic` or `complete`.

### Pitfall 5: Password Hash Stored in config.json Instead of Keychain

**What goes wrong:** Password hash stored in `~/.deadbolt/config.json` (which is already used for AppConfig). While the file has `0600` permissions, any process running as the user can read it. It also gets included in any config backup/export feature.

**How to avoid:** Use `security_framework::passwords::set_generic_password` with service `"com.deadbolt.wallet"` and account `"app_password_hash"`. Exact pattern as `KeychainStorage::store_vault_key`. The Keychain requires UI confirmation for third-party access.

### Pitfall 6: Idle Timer Fires Immediately on Lock (Timer Duration Bug)

**What goes wrong:** `Timer(Duration(seconds: _timeoutSeconds), lock)` — `_timeoutSeconds` is read from SharedPreferences but has not been initialized yet; returns 0 or null-coalesced to 0. Timer fires immediately on unlock.

**How to avoid:** Provide a hard-coded default (`const int kDefaultIdleTimeoutSeconds = 900`) as the fallback when SharedPreferences has no value. Always validate that timeout > 0 before creating timer.

---

## Code Examples

### INFR-06: Constant-Time Fix in agent/auth.rs

Current code (VULNERABLE — uses `==` via `Vec::contains`):
```rust
// Current (agent/auth.rs line 32-35):
let is_valid = {
    let valid_tokens = state.api_tokens.lock().unwrap();
    valid_tokens.contains(&token.to_string())  // uses == internally
};
```

Fixed code:
```rust
// Fixed (after adding constant_time_eq = "0.3" to Cargo.toml):
use constant_time_eq::constant_time_eq;

let is_valid = {
    let valid_tokens = state.api_tokens.lock().unwrap();
    valid_tokens.iter().any(|stored| {
        constant_time_eq(stored.as_bytes(), token.as_bytes())
    })
};
```

### INFR-07: Zeroization Audit Checklist

From direct inspection of `vault.rs`, `session.rs`, `wallet_manager.rs`:

**Confirmed safe (already zeroized):**
- `vault.rs` `derive_key()` returns `[u8; 32]` (stack) and is zeroized after use in `encrypt()`/`decrypt()` — `key.zeroize()` called
- `session.rs` `SessionManager` stores `[u8; 32]` seeds in `HashMap` — zeroized in `lock()`, `lock_all()`, and `Drop`
- `wallet_manager.rs` `create_wallet()` and `import_wallet()` zeroize `seed`, `vault_key`, `phrase` after use

**Needs audit (possible stack copy risk):**
- `session.rs` `unlock_with_key()` line 43: `seed.copy_from_slice(&plaintext)` — `plaintext` is a `Vec<u8>` from `vault::decrypt_with_key()`. When this `Vec` is dropped, `zeroize` is NOT called on it (it's a plain `Vec`, not a `SecretVec`). Fix: wrap `plaintext` in a `zeroize::Zeroizing<Vec<u8>>` wrapper.
- `vault.rs` `decrypt()` returns `Vec<u8>` plaintext — callers must zeroize. Audit all call sites.
- `mnemonic.rs` — not yet inspected; must verify seed derivation path.

**Fix pattern for plaintext Vec:**
```rust
// In vault.rs decrypt() — wrap return in Zeroizing:
use zeroize::Zeroizing;

pub fn decrypt(...) -> Result<Zeroizing<Vec<u8>>, DeadboltError> {
    // ... existing logic ...
    Ok(Zeroizing::new(plaintext))
}
```

This causes `Drop` to call `zeroize()` on the plaintext buffer automatically, even if the caller forgets.

### Idle Activity Detection (Flutter)

```dart
// In app.dart or around AppShell — detect mouse/keyboard activity:
Listener(
  onPointerMove: (_) => ref.read(authProvider.notifier).resetActivity(),
  onPointerDown: (_) => ref.read(authProvider.notifier).resetActivity(),
  child: KeyboardListener(
    focusNode: FocusNode(),
    onKeyEvent: (_) => ref.read(authProvider.notifier).resetActivity(),
    child: child,  // The routed content
  ),
)
```

### Password Strength Meter (simple, no zxcvbn)

Given Claude's Discretion on strength meter algorithm, a simple rule-based approach avoids an external dependency:

```dart
PasswordStrength evaluateStrength(String password) {
  if (password.length < 8) return PasswordStrength.weak;
  final hasUpper = password.contains(RegExp(r'[A-Z]'));
  final hasLower = password.contains(RegExp(r'[a-z]'));
  final hasDigit = password.contains(RegExp(r'\d'));
  final hasSpecial = password.contains(RegExp(r'[^A-Za-z0-9]'));
  final score = [hasUpper, hasLower, hasDigit, hasSpecial].where((b) => b).length;
  if (score >= 3 && password.length >= 12) return PasswordStrength.strong;
  if (score >= 2) return PasswordStrength.fair;
  return PasswordStrength.weak;
}
```

### Escalating Delay (Lock Screen)

```dart
// In lock_screen.dart:
static const _delays = [0, 1, 2, 5, 10, 30];

int _delayForAttempt(int attempts) {
  if (attempts <= 0) return 0;
  final idx = (attempts - 1).clamp(0, _delays.length - 1);
  return _delays[idx];
}

Future<void> _onSubmit() async {
  final delay = _delayForAttempt(ref.read(authProvider).failedAttempts);
  if (delay > 0) await Future.delayed(Duration(seconds: delay));
  // then call unlock...
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Flutter-only lock state | Rust `AtomicBool` + Flutter observable | Security enforcement survives all Flutter lifecycle events |
| Password stored in Dart state | Session token in Rust static; Dart holds nothing | No heap-dump exposure of password |
| `==` for token comparison | `constant_time_eq` | Timing attack on localhost prevented |
| `Vec<u8>` for key material | `Zeroizing<Vec<u8>>` wrappers | Plaintext cleared on drop even if caller forgets |

---

## Open Questions

1. **`mnemonic.rs` zeroization audit not yet performed**
   - What we know: `vault.rs`, `session.rs`, `wallet_manager.rs` are inspected and mostly correct
   - What's unclear: `mnemonic.rs` `derive_keypair()` return path — does it return seed by value (stack copy risk)?
   - Recommendation: Implementer reads `mnemonic.rs` before writing INFR-07 tasks; if seed is returned by value from `derive_keypair`, wrap in `Zeroizing<>` or pass by mutable reference

2. **`needs_onboarding()` check does not include password gate**
   - What we know: `AppConfig::needs_onboarding()` checks `!onboarding_completed && wallets.is_empty()`. After password step is added to onboarding, a user who crashes between password creation and wallet creation will have a password set but `onboarding_completed = false` and no wallets
   - What's unclear: Should `needs_onboarding()` be extended, or should the router handle this edge case separately?
   - Recommendation: Add `has_app_password()` FFI function; router checks: if wallets exist but no password set → route to password-setup screen; this covers interrupted onboarding

3. **Idle timer interaction with macOS window hide**
   - What we know: CONTEXT.md explicitly states window minimize/hide does NOT reset or trigger lock
   - What's unclear: `WidgetsBindingObserver.didChangeAppLifecycleState` fires on macOS when window is hidden — implementer must ensure this does not accidentally call `lock()`
   - Recommendation: Do not use `WidgetsBindingObserver` for lock triggering; only use the idle timer; ignore lifecycle events for this phase

4. **`DeadboltError::WalletLocked` variant does not exist yet**
   - What we know: Inspected `models/` — no `WalletLocked` variant in `DeadboltError`
   - What's unclear: Current error enum variants not fully listed (read `models/mod.rs` not read)
   - Recommendation: Add `WalletLocked` variant to `DeadboltError`; implement FFI bridge to return this as a distinct error string so Flutter can distinguish locked vs. other errors

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Rust built-in tests (`cargo test`) + Flutter widget tests (`flutter test`) |
| Rust config | No separate config — `#[cfg(test)]` blocks in each module, run via `cargo test -p deadbolt_core` |
| Flutter config | `pubspec.yaml` `dev_dependencies` includes `flutter_test`; no test dir exists yet |
| Quick Rust run | `cargo test -p deadbolt_core auth -- --test-threads=1` |
| Full Rust suite | `cargo test -p deadbolt_core` |
| Flutter unit tests | `flutter test test/` (dir needs Wave 0 creation) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTH-08 | `set_app_password` stores scrypt hash; `verify_app_password` accepts correct, rejects wrong | unit (Rust) | `cargo test -p deadbolt_core auth::password` | Wave 0 |
| AUTH-08 | Wrong password returns `Err`, not panic | unit (Rust) | `cargo test -p deadbolt_core auth::password::test_wrong_password` | Wave 0 |
| AUTH-01 | App starts locked; lock screen shows before dashboard | widget test | `flutter test test/lock_screen_test.dart` | Wave 0 |
| AUTH-02 | `AuthNotifier.lock()` calls `lock_all_wallets` and sets status locked | unit (Dart) | `flutter test test/auth_provider_test.dart` | Wave 0 |
| AUTH-03 | Idle timeout preference persists across provider re-init | unit (Dart) | `flutter test test/auth_provider_test.dart` | Wave 0 |
| INFR-06 | Constant-time eq used (no `==`); wrong token rejected | unit (Rust) | `cargo test -p deadbolt_core agent::auth` | Partial (auth.rs exists, test needed) |
| INFR-07 | `vault::decrypt` plaintext zeroed after use | unit (Rust) | `cargo test -p deadbolt_core crypto::vault::test_zeroize` | Wave 0 |
| AUTH-04/06 | Auth challenge modal rejects wrong password; accepts correct | widget test | `flutter test test/auth_challenge_dialog_test.dart` | Wave 0 |
| AUTH-07 | `change_app_password` requires correct current password | unit (Rust) | `cargo test -p deadbolt_core auth::password::test_change_password` | Wave 0 |
| Pitfall 8 | `get_active_signer()` returns `WalletLocked` when `APP_LOCKED=true` | unit (Rust) | `cargo test -p deadbolt_core auth::lock_state` | Wave 0 |

### Sampling Rate

- **Per task commit:** `cargo test -p deadbolt_core auth` (Rust tasks) or `flutter test test/` (Flutter tasks)
- **Per wave merge:** `cargo test -p deadbolt_core && flutter test test/`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `rust/deadbolt_core/src/auth/mod.rs` — new auth module
- [ ] `rust/deadbolt_core/src/auth/password.rs` — set/verify/change password + tests
- [ ] `rust/deadbolt_core/src/auth/lock_state.rs` — AtomicBool + tests
- [ ] `rust/deadbolt_bridge/src/api/auth.rs` — FRB-exposed auth functions
- [ ] `test/lock_screen_test.dart` — Flutter widget tests for lock screen
- [ ] `test/auth_provider_test.dart` — Flutter unit tests for AuthNotifier
- [ ] `test/auth_challenge_dialog_test.dart` — Flutter widget test for challenge modal
- [ ] `DeadboltError::WalletLocked` variant addition to `models/mod.rs`

---

## Sources

### Primary (HIGH confidence — direct codebase inspection)

- `/rust/deadbolt_core/src/crypto/vault.rs` — scrypt KDF (`derive_key`), ChaCha20-Poly1305, zeroize usage confirmed
- `/rust/deadbolt_core/src/storage/session.rs` — SessionManager lock/unlock/zeroize-on-drop confirmed
- `/rust/deadbolt_core/src/storage/keychain.rs` — `security_framework` Keychain pattern; service `"com.deadbolt.wallet"` confirmed
- `/rust/deadbolt_core/src/models/wallet_manager.rs` — `unlock()`, `lock_all()`, zeroize in create/import confirmed
- `/rust/deadbolt_bridge/src/api/wallet.rs` — FRB exposure pattern; `OnceLock<RwLock<WalletManager>>` singleton confirmed
- `/rust/deadbolt_core/src/agent/auth.rs` — `==` comparison confirmed (INFR-06 needed)
- `/lib/routing/app_router.dart` — redirect guard pattern confirmed; extension point identified
- `/lib/providers/onboarding_provider.dart` — step enum + state pattern confirmed
- `/lib/providers/wallet_provider.dart` — Riverpod `AsyncNotifier` pattern confirmed
- `/lib/main.dart` — `window_manager` usage confirmed; no auth init present
- `/lib/theme/brand_theme.dart` — `BrandColors.primary = #F87040`, `background = #000000` confirmed
- `/rust/deadbolt_core/Cargo.toml` — dependency inventory confirmed (no `constant_time_eq` present)
- `.planning/research/PITFALLS.md` — Pitfalls 3, 8, 10 directly apply to this phase
- `.planning/research/ARCHITECTURE.md` — Auth gate flow, Pattern 3 (app password in Rust) directly applies

### Secondary (MEDIUM confidence — prior research verified against code)

- `.planning/research/ARCHITECTURE.md` Pattern 3 — Rust session token, never store password in Dart — verified consistent with codebase structure
- `constant_time_eq` crate (crates.io, well-known) — standard solution for INFR-06

---

## Metadata

**Confidence breakdown:**
- Rust auth layer design: HIGH — inspected all relevant Rust files; patterns directly extend existing code
- FFI bridge pattern: HIGH — inspected `api/wallet.rs`; new `api/auth.rs` follows identical pattern
- Flutter AuthProvider/GoRouter: HIGH — inspected `app_router.dart` and `onboarding_provider.dart`; extension points clear
- INFR-06 fix: HIGH — confirmed `==` usage in `auth.rs` line 34; fix is one-liner + Cargo dependency
- INFR-07 audit: MEDIUM — inspected vault.rs/session.rs/wallet_manager.rs; `mnemonic.rs` not fully inspected
- Idle timer implementation: MEDIUM — `Listener` + `Timer` approach is standard Flutter; specific window_manager interaction not verified

**Research date:** 2026-03-16
**Valid until:** 2026-04-16 (stable stack; flutter_rust_bridge and go_router APIs are stable)
