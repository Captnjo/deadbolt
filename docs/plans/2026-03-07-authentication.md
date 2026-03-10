# Authentication & Wallet Locking — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add password-based wallet locking with auto-lock timeout, lock screen, and gated mnemonic reveal.

**Architecture:** Phantom-style — wallet locked at launch, password unlocks it, transactions need no further auth. Scrypt password hash stored in Rust AppConfig. Flutter manages lock state, inactivity timer, and UI. GoRouter redirect enforces lock screen.

**Tech Stack:** Rust (scrypt, zeroize, serde), Flutter (Riverpod, GoRouter, Listener widget), SharedPreferences (timeout pref)

---

### Task 1: Rust — Password hashing functions

**Files:**
- Modify: `rust/deadbolt_core/src/crypto/vault.rs`

**Step 1: Add `hash_password` and `verify_password` functions**

Append after the `generate_vault_key` function (after line 172) in `vault.rs`:

```rust
/// Hash a password for storage. Returns 48 bytes: [16-byte salt][32-byte derived key].
pub fn hash_password(password: &[u8]) -> Result<Vec<u8>, DeadboltError> {
    let mut salt = [0u8; 16];
    getrandom::getrandom(&mut salt)
        .map_err(|e| DeadboltError::VaultError(format!("RNG error: {e}")))?;

    let mut key = derive_key(password, &salt, KdfStrength::Desktop)?;

    let mut result = Vec::with_capacity(48);
    result.extend_from_slice(&salt);
    result.extend_from_slice(&key);

    key.zeroize();
    Ok(result)
}

/// Verify a password against a stored hash (48 bytes: salt + derived key).
pub fn verify_password(password: &[u8], stored_hash: &[u8]) -> Result<bool, DeadboltError> {
    if stored_hash.len() != 48 {
        return Err(DeadboltError::VaultError("Invalid password hash length".into()));
    }

    let salt = &stored_hash[..16];
    let expected_key = &stored_hash[16..48];

    let mut derived = derive_key(password, salt, KdfStrength::Desktop)?;
    let matches = derived == *expected_key;
    derived.zeroize();

    Ok(matches)
}
```

**Step 2: Add tests**

Append to the `mod tests` block in `vault.rs`:

```rust
#[test]
fn test_hash_and_verify_password() {
    let password = b"correct-horse-battery-staple";
    let hash = hash_password(password).unwrap();
    assert_eq!(hash.len(), 48);
    assert!(verify_password(password, &hash).unwrap());
    assert!(!verify_password(b"wrong-password", &hash).unwrap());
}

#[test]
fn test_hash_password_different_salts() {
    let password = b"same-password";
    let hash1 = hash_password(password).unwrap();
    let hash2 = hash_password(password).unwrap();
    // Different salts produce different hashes
    assert_ne!(hash1, hash2);
    // But both verify correctly
    assert!(verify_password(password, &hash1).unwrap());
    assert!(verify_password(password, &hash2).unwrap());
}

#[test]
fn test_verify_password_invalid_hash_length() {
    let result = verify_password(b"password", &[0u8; 10]);
    assert!(result.is_err());
}
```

**Step 3: Run Rust tests**

Run: `cd /Users/jo/Projects/deadbolt/rust/deadbolt_core && cargo test vault`
Expected: All tests pass

**Step 4: Commit**

```bash
git add rust/deadbolt_core/src/crypto/vault.rs
git commit -m "feat(rust): add password hashing and verification"
```

---

### Task 2: Rust — Password hash field in AppConfig

**Files:**
- Modify: `rust/deadbolt_core/src/models/config.rs`

**Step 1: Add `password_hash` field to AppConfig**

Add after `helius_api_key` field (line 39 in config.rs):

```rust
    /// Scrypt-derived password hash (base64-encoded, 48 bytes: salt + key).
    /// None = no password set (fresh install).
    #[serde(default)]
    pub password_hash: Option<String>,
```

Update `Default` impl (after line 102) to include:

```rust
    password_hash: None,
```

**Step 2: Add helper methods to AppConfig**

Append to the `impl AppConfig` block (before the closing `}` around line 172):

```rust
    /// Check whether the user has set a password.
    pub fn has_password(&self) -> bool {
        self.password_hash.is_some()
    }
```

**Step 3: Add test**

Add to `mod tests` in config.rs:

```rust
#[test]
fn test_password_hash_backwards_compat() {
    let json = r#"{"wallets":[],"network":"mainnet"}"#;
    let config: AppConfig = serde_json::from_str(json).unwrap();
    assert!(config.password_hash.is_none());
    assert!(!config.has_password());
}

#[test]
fn test_password_hash_roundtrip() {
    let mut config = AppConfig::default();
    config.password_hash = Some("dGVzdA==".to_string());
    let json = serde_json::to_string(&config).unwrap();
    assert!(json.contains("passwordHash"));
    let parsed: AppConfig = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed.password_hash, Some("dGVzdA==".to_string()));
}
```

**Step 4: Run tests**

Run: `cd /Users/jo/Projects/deadbolt/rust/deadbolt_core && cargo test config`
Expected: All tests pass

**Step 5: Commit**

```bash
git add rust/deadbolt_core/src/models/config.rs
git commit -m "feat(rust): add password_hash field to AppConfig"
```

---

### Task 3: Rust — Password bridge functions

**Files:**
- Modify: `rust/deadbolt_bridge/src/api/wallet.rs`

**Step 1: Add password bridge functions**

Add `use base64::Engine;` at the top of wallet.rs. Then append after `set_helius_api_key` (after line 176):

```rust
/// Check whether the user has set an app password.
#[flutter_rust_bridge::frb(sync)]
pub fn has_app_password() -> Result<bool, String> {
    let mgr = manager().read().map_err(|e| e.to_string())?;
    Ok(mgr.config().has_password())
}

/// Set the app password (first-time setup or overwrite).
pub fn set_app_password(password: String) -> Result<(), String> {
    use deadbolt_core::crypto::vault;

    let hash_bytes = vault::hash_password(password.as_bytes())
        .map_err(|e| e.to_string())?;
    let hash_b64 = base64::engine::general_purpose::STANDARD.encode(&hash_bytes);

    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    mgr.config_mut().password_hash = Some(hash_b64);
    mgr.config_mut().save().map_err(|e| e.to_string())
}

/// Verify the app password. Returns true if correct, false if wrong.
pub fn verify_app_password(password: String) -> Result<bool, String> {
    use deadbolt_core::crypto::vault;

    let mgr = manager().read().map_err(|e| e.to_string())?;
    let hash_b64 = mgr.config().password_hash.as_ref()
        .ok_or("No password set")?;

    let hash_bytes = base64::engine::general_purpose::STANDARD
        .decode(hash_b64)
        .map_err(|e| format!("Invalid stored hash: {e}"))?;

    vault::verify_password(password.as_bytes(), &hash_bytes)
        .map_err(|e| e.to_string())
}

/// Change the app password. Verifies current password first.
pub fn change_app_password(current: String, new_password: String) -> Result<(), String> {
    use deadbolt_core::crypto::vault;

    // Verify current password
    {
        let mgr = manager().read().map_err(|e| e.to_string())?;
        let hash_b64 = mgr.config().password_hash.as_ref()
            .ok_or("No password set")?;
        let hash_bytes = base64::engine::general_purpose::STANDARD
            .decode(hash_b64)
            .map_err(|e| format!("Invalid stored hash: {e}"))?;
        let valid = vault::verify_password(current.as_bytes(), &hash_bytes)
            .map_err(|e| e.to_string())?;
        if !valid {
            return Err("Current password is incorrect".into());
        }
    }

    // Set new password
    let new_hash = vault::hash_password(new_password.as_bytes())
        .map_err(|e| e.to_string())?;
    let hash_b64 = base64::engine::general_purpose::STANDARD.encode(&new_hash);

    let mut mgr = manager().write().map_err(|e| e.to_string())?;
    mgr.config_mut().password_hash = Some(hash_b64);
    mgr.config_mut().save().map_err(|e| e.to_string())
}
```

**Step 2: Run code generation**

Run: `cd /Users/jo/Projects/deadbolt && flutter_rust_bridge_codegen generate`
Expected: Bridge code regenerated in `lib/src/rust/api/wallet.dart`

**Step 3: Verify it compiles**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No new issues

**Step 4: Commit**

```bash
git add rust/deadbolt_bridge/src/api/wallet.rs lib/src/rust/
git commit -m "feat(rust): add password bridge functions"
```

---

### Task 4: Flutter — Onboarding password step

**Files:**
- Modify: `lib/providers/onboarding_provider.dart`
- Modify: `lib/features/onboarding/onboarding_shell.dart`
- Create: `lib/features/onboarding/steps/set_password_step.dart`

**Step 1: Add `setPassword` to OnboardingStep enum**

In `lib/providers/onboarding_provider.dart`, add `setPassword` to the enum (after `connectDevice`, before `complete` — line 28):

```dart
enum OnboardingStep {
  welcome,
  walletName,
  displayMnemonic,
  verifyBackup,
  importPhrase,
  detectDevice,
  connectDevice,
  setPassword,    // <-- add this
  complete,
}
```

**Step 2: Add `setPassword` to step paths**

In `_stepsForPath` (lines 96-122), insert `OnboardingStep.setPassword` before `OnboardingStep.complete` in all three paths:

```dart
static List<OnboardingStep> _stepsForPath(OnboardingPath path) {
    switch (path) {
      case OnboardingPath.create:
        return [
          OnboardingStep.welcome,
          OnboardingStep.walletName,
          OnboardingStep.displayMnemonic,
          OnboardingStep.verifyBackup,
          OnboardingStep.setPassword,
          OnboardingStep.complete,
        ];
      case OnboardingPath.import_:
        return [
          OnboardingStep.welcome,
          OnboardingStep.walletName,
          OnboardingStep.importPhrase,
          OnboardingStep.setPassword,
          OnboardingStep.complete,
        ];
      case OnboardingPath.hardware:
        return [
          OnboardingStep.welcome,
          OnboardingStep.walletName,
          OnboardingStep.detectDevice,
          OnboardingStep.connectDevice,
          OnboardingStep.setPassword,
          OnboardingStep.complete,
        ];
    }
  }
```

**Step 3: Add navigation to setPassword step**

In the `OnboardingNotifier` class, add `advanceToSetPassword` method:

```dart
void advanceToSetPassword() {
  state = state.copyWith(step: OnboardingStep.setPassword);
}
```

Update `advanceFromVerify` (line 223) to go to setPassword instead of complete:

```dart
void advanceFromVerify() {
  state = state.copyWith(step: OnboardingStep.setPassword);
}
```

Similarly, update `importWallet` (line 238) — change `step: OnboardingStep.complete` to `step: OnboardingStep.setPassword`.

Update `_connectDevice` (line 261) — change the success branch. After `state = state.copyWith(loading: false, createdWallet: wallet);` add navigation to setPassword:

```dart
state = state.copyWith(
  loading: false,
  createdWallet: wallet,
  step: OnboardingStep.setPassword,
);
```

Wait — `_connectDevice` already sets loading: false and createdWallet, and the ConnectDeviceStep widget likely advances. Check the connect_device_step.dart to see how it advances. If it calls a method that goes to `complete`, update that to go to `setPassword` instead. Actually, the simplest approach: just ensure the `back()` method handles setPassword → goes back to the right prior step based on path.

Update the `back()` method to handle `setPassword`:

```dart
case OnboardingStep.setPassword:
  if (path == OnboardingPath.create) {
    state = state.copyWith(step: OnboardingStep.verifyBackup);
  } else if (path == OnboardingPath.import_) {
    state = state.copyWith(step: OnboardingStep.importPhrase);
  } else {
    state = state.copyWith(step: OnboardingStep.connectDevice);
  }
```

And update the `complete` back case to go to `setPassword`:

```dart
case OnboardingStep.complete:
  state = state.copyWith(step: OnboardingStep.setPassword);
```

Add a method to set the password and advance:

```dart
Future<void> setPassword(String password) async {
  state = state.copyWith(loading: true, error: null);
  try {
    await bridge.setAppPassword(password: password);
    state = state.copyWith(
      loading: false,
      step: OnboardingStep.complete,
    );
  } catch (e) {
    state = state.copyWith(error: e.toString(), loading: false);
  }
}
```

**Step 4: Create the SetPasswordStep widget**

Create `lib/features/onboarding/steps/set_password_step.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../theme/brand_theme.dart';

class SetPasswordStep extends ConsumerStatefulWidget {
  const SetPasswordStep({super.key});

  @override
  ConsumerState<SetPasswordStep> createState() => _SetPasswordStepState();
}

class _SetPasswordStepState extends ConsumerState<SetPasswordStep> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _localError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingStateProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 48, color: BrandColors.primary),
          const SizedBox(height: 24),
          const Text(
            'Set a Password',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'This password protects your wallet. You\'ll need it to unlock the app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: BrandColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onChanged: (_) => setState(() => _localError = null),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() => _localError = null),
          ),
          const SizedBox(height: 8),
          if (_localError != null || state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _localError ?? state.error!,
                style: const TextStyle(color: BrandColors.error, fontSize: 13),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: state.loading ? null : _submit,
              child: state.loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Set Password'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 8) {
      setState(() => _localError = 'Password must be at least 8 characters');
      return;
    }
    if (password != confirm) {
      setState(() => _localError = 'Passwords do not match');
      return;
    }

    ref.read(onboardingStateProvider.notifier).setPassword(password);
  }
}
```

**Step 5: Wire into OnboardingShell**

In `lib/features/onboarding/onboarding_shell.dart`:

Add import (after line 13):
```dart
import 'steps/set_password_step.dart';
```

Add case to `_buildStep` (before the `complete` case, around line 108):
```dart
OnboardingStep.setPassword => const SetPasswordStep(),
```

**Step 6: Verify it compiles**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No new issues

**Step 7: Commit**

```bash
git add lib/providers/onboarding_provider.dart lib/features/onboarding/onboarding_shell.dart lib/features/onboarding/steps/set_password_step.dart
git commit -m "feat: add password setup step to onboarding"
```

---

### Task 5: Flutter — Auth/lock provider

**Files:**
- Create: `lib/providers/auth_provider.dart`

**Step 1: Create the auth provider**

Create `lib/providers/auth_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/rust/api/wallet.dart' as bridge;
import 'wallet_provider.dart';

/// Auto-lock timeout options.
enum AutoLockTimeout {
  fiveMin(Duration(minutes: 5), '5 minutes'),
  fifteenMin(Duration(minutes: 15), '15 minutes'),
  thirtyMin(Duration(minutes: 30), '30 minutes'),
  oneHour(Duration(hours: 1), '1 hour'),
  fourHours(Duration(hours: 4), '4 hours'),
  never(null, 'Never');

  const AutoLockTimeout(this.duration, this.label);
  final Duration? duration;
  final String label;

  static AutoLockTimeout fromName(String? name) {
    if (name == null) return AutoLockTimeout.fifteenMin;
    return AutoLockTimeout.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AutoLockTimeout.fifteenMin,
    );
  }
}

class AuthState {
  final bool isLocked;
  final AutoLockTimeout autoLockTimeout;

  const AuthState({
    this.isLocked = true,
    this.autoLockTimeout = AutoLockTimeout.fifteenMin,
  });

  AuthState copyWith({bool? isLocked, AutoLockTimeout? autoLockTimeout}) {
    return AuthState(
      isLocked: isLocked ?? this.isLocked,
      autoLockTimeout: autoLockTimeout ?? this.autoLockTimeout,
    );
  }
}

const _autoLockPref = 'auto_lock_timeout';

class AuthNotifier extends Notifier<AuthState> {
  Timer? _inactivityTimer;

  @override
  AuthState build() {
    // Start locked if password is set
    final hasPassword = bridge.hasAppPassword();
    _loadTimeout();
    return AuthState(isLocked: hasPassword);
  }

  Future<void> _loadTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_autoLockPref);
    final timeout = AutoLockTimeout.fromName(name);
    state = state.copyWith(autoLockTimeout: timeout);
    _resetInactivityTimer();
  }

  /// Called on every user interaction (click, keypress, scroll).
  void recordActivity() {
    if (state.isLocked) return;
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    final duration = state.autoLockTimeout.duration;
    if (duration == null || state.isLocked) return;
    _inactivityTimer = Timer(duration, lock);
  }

  /// Lock the wallet. Zeroizes seeds and navigates to lock screen.
  void lock() {
    _inactivityTimer?.cancel();
    bridge.lockAllWallets();
    state = state.copyWith(isLocked: true);
  }

  /// Attempt to unlock with password. Returns null on success, error message on failure.
  Future<String?> unlock(String password) async {
    try {
      final valid = await bridge.verifyAppPassword(password: password);
      if (!valid) return 'Incorrect password';

      // Unlock the active wallet's session
      final address = ref.read(activeWalletProvider);
      if (address != null) {
        await bridge.unlockWallet(address: address);
      }

      state = state.copyWith(isLocked: false);
      _resetInactivityTimer();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> setAutoLockTimeout(AutoLockTimeout timeout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_autoLockPref, timeout.name);
    state = state.copyWith(autoLockTimeout: timeout);
    _resetInactivityTimer();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
```

**Step 2: Verify it compiles**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No new issues

**Step 3: Commit**

```bash
git add lib/providers/auth_provider.dart
git commit -m "feat: add auth provider with lock state and inactivity timer"
```

---

### Task 6: Flutter — Lock screen

**Files:**
- Create: `lib/features/lock/lock_screen.dart`

**Step 1: Create the lock screen**

Create `lib/features/lock/lock_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../theme/brand_theme.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _passwordController = TextEditingController();
  bool _showPasswordField = false;
  bool _obscure = true;
  bool _unlocking = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (_showPasswordField)
          const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: BrandColors.background,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo mark + name (matches title bar style but larger)
                  Image.asset(
                    'assets/deadbolt_logomark.png',
                    height: 64,
                    width: 64,
                    color: Colors.white,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'DEADBOLT',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 48),

                  if (!_showPasswordField) ...[
                    ElevatedButton(
                      onPressed: () =>
                          setState(() => _showPasswordField = true),
                      child: const Text('Unlock Wallet'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _unlock(),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: BrandColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _unlocking ? null : _cancel,
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _unlocking ? null : _unlock,
                            child: _unlocking
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Unlock'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _cancel() {
    setState(() {
      _showPasswordField = false;
      _passwordController.clear();
      _error = null;
    });
  }

  Future<void> _unlock() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }

    setState(() {
      _unlocking = true;
      _error = null;
    });

    final error = await ref.read(authProvider.notifier).unlock(password);

    if (mounted) {
      setState(() {
        _unlocking = false;
        _error = error;
        if (error != null) {
          _passwordController.clear();
        }
      });
    }
  }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No new issues

**Step 3: Commit**

```bash
git add lib/features/lock/lock_screen.dart
git commit -m "feat: add lock screen with password unlock"
```

---

### Task 7: Flutter — Router integration + inactivity detection

**Files:**
- Modify: `lib/routing/app_router.dart`
- Modify: `lib/app.dart`

**Step 1: Add lock route and redirect logic**

In `lib/routing/app_router.dart`:

Add imports at the top:
```dart
import '../features/lock/lock_screen.dart';
import '../providers/auth_provider.dart';
```

Modify the `appRouterProvider` (line 24-117):

```dart
final appRouterProvider = Provider<GoRouter>((ref) {
  final needsOnboarding = ref.watch(needsOnboardingProvider);
  final isLocked = ref.watch(authProvider.select((s) => s.isLocked));

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: needsOnboarding
        ? '/onboarding'
        : isLocked
            ? '/lock'
            : '/dashboard',
    redirect: (context, state) {
      final path = state.uri.path;

      // Onboarding takes priority (new user, no wallet yet)
      if (needsOnboarding && path != '/onboarding') return '/onboarding';
      if (!needsOnboarding && path == '/onboarding') {
        return isLocked ? '/lock' : '/dashboard';
      }

      // Lock screen gate
      if (isLocked && path != '/lock' && path != '/onboarding') return '/lock';
      if (!isLocked && path == '/lock') return '/dashboard';

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingShell(),
      ),
      GoRoute(
        path: '/lock',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LockScreen(),
      ),
      // ... rest of routes unchanged
```

**Step 2: Add inactivity listener in app.dart**

In `lib/app.dart`, wrap the app content in a `Listener` to detect user interaction:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'routing/app_router.dart';
import 'shared/widgets/title_bar.dart';
import 'theme/brand_theme.dart';

class DeadboltApp extends ConsumerWidget {
  const DeadboltApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Deadbolt',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(),
      routerConfig: router,
      builder: (context, child) {
        return Listener(
          onPointerDown: (_) => ref.read(authProvider.notifier).recordActivity(),
          onPointerSignal: (_) => ref.read(authProvider.notifier).recordActivity(),
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (_) => ref.read(authProvider.notifier).recordActivity(),
            child: Column(
              children: [
                const TitleBar(),
                Expanded(child: child!),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

**Step 3: Verify it compiles**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No new issues

**Step 4: Manual test**

Run: `cd /Users/jo/Projects/deadbolt && flutter run -d macos`

Test flow:
1. If no password set yet → app goes straight to dashboard (no lock screen)
2. Go through onboarding on a fresh wallet → password step appears after backup verify
3. Set password → complete onboarding → dashboard
4. Quit and relaunch → lock screen shown
5. Enter wrong password → error message
6. Enter correct password → unlock → dashboard

**Step 5: Commit**

```bash
git add lib/routing/app_router.dart lib/app.dart
git commit -m "feat: integrate lock screen into router with inactivity detection"
```

---

### Task 8: Flutter — Settings auth section

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

**Step 1: Add auth imports and auto-lock dropdown**

Add imports at top of `settings_screen.dart`:
```dart
import '../../providers/auth_provider.dart';
```

In the `build` method, after the Display Currency row and Jito toggle, add:

```dart
const SizedBox(height: 8),
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    const Text('Auto-Lock', style: TextStyle(fontSize: 14)),
    DropdownButton<AutoLockTimeout>(
      value: ref.watch(authProvider).autoLockTimeout,
      underline: const SizedBox.shrink(),
      items: AutoLockTimeout.values
          .map((t) => DropdownMenuItem(
                value: t,
                child: Text(t.label,
                    style: const TextStyle(fontSize: 14)),
              ))
          .toList(),
      onChanged: (value) {
        if (value != null) {
          ref.read(authProvider.notifier).setAutoLockTimeout(value);
        }
      },
    ),
  ],
),
const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: () => _changePassword(context),
  icon: const Icon(Icons.key, size: 18),
  label: const Text('Change Password'),
),
```

**Step 2: Add `_changePassword` method**

Add to `_SettingsScreenState`:

```dart
Future<void> _changePassword(BuildContext context) async {
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        String? error;
        bool loading = false;

        return AlertDialog(
          title: const Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current Password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'New Password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Confirm New Password'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final current = currentController.text;
                final newPw = newController.text;
                final confirm = confirmController.text;

                if (newPw.length < 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('New password must be at least 8 characters')),
                  );
                  return;
                }
                if (newPw != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('New passwords do not match')),
                  );
                  return;
                }

                try {
                  await bridge.changeAppPassword(
                    current: current,
                    newPassword: newPw,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Change'),
            ),
          ],
        );
      },
    ),
  );

  if (result == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Password changed'),
          duration: Duration(seconds: 1)),
    );
  }

  currentController.dispose();
  newController.dispose();
  confirmController.dispose();
}
```

Add the bridge import at the top if not already present:
```dart
import '../../src/rust/api/wallet.dart' as bridge;
```

**Step 3: Verify it compiles**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No new issues

**Step 4: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "feat: add auto-lock timeout and change password to settings"
```

---

### Task 9: Flutter — Gate mnemonic reveal

**Files:**
- Find the file that shows the mnemonic (likely in wallet details). Search for `get_mnemonic` or `getMnemonic` usage.

**Step 1: Find and modify mnemonic reveal**

Search the codebase for `getMnemonic` or `get_mnemonic` usage in Flutter code. Wrap the call with a password verification dialog:

```dart
Future<bool> _verifyPassword(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enter Password'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Password'),
        onSubmitted: (_) async {
          try {
            final valid = await bridge.verifyAppPassword(
              password: controller.text,
            );
            if (ctx.mounted) Navigator.pop(ctx, valid);
          } catch (_) {
            if (ctx.mounted) Navigator.pop(ctx, false);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            try {
              final valid = await bridge.verifyAppPassword(
                password: controller.text,
              );
              if (ctx.mounted) Navigator.pop(ctx, valid);
            } catch (_) {
              if (ctx.mounted) Navigator.pop(ctx, false);
            }
          },
          child: const Text('Verify'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result == true;
}
```

Insert this check before the existing `get_mnemonic` call:
```dart
final verified = await _verifyPassword(context);
if (!verified) return;
// ... existing get_mnemonic call
```

**Step 2: Verify it compiles**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No new issues

**Step 3: Commit**

```bash
git add <modified files>
git commit -m "feat: require password to reveal mnemonic"
```

---

### Task 10: Full verification and final commit

**Step 1: Run flutter analyze**

Run: `cd /Users/jo/Projects/deadbolt && flutter analyze`
Expected: No issues

**Step 2: Run Rust tests**

Run: `cd /Users/jo/Projects/deadbolt/rust/deadbolt_core && cargo test`
Expected: All tests pass

**Step 3: Manual test checklist**

Run: `cd /Users/jo/Projects/deadbolt && flutter run -d macos`

- [ ] Fresh install: onboarding → password step appears → set password → complete → dashboard
- [ ] Quit and relaunch → lock screen with logo + "Unlock Wallet"
- [ ] Click Unlock → password field + Cancel/Unlock buttons
- [ ] Wrong password → error message, field clears
- [ ] Correct password → dashboard
- [ ] Wait for auto-lock timeout → returns to lock screen
- [ ] Click/keypress/scroll resets timeout (mouse move does not)
- [ ] Settings → auto-lock dropdown works
- [ ] Settings → Change Password works
- [ ] Reveal mnemonic → password re-entry required
- [ ] Sign a swap → no password prompt needed

**Step 4: Commit any remaining fixes**

```bash
git add -A
git commit -m "feat: wallet authentication with lock screen and auto-lock"
```
