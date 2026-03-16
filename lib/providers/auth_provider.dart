import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/rust/api/auth.dart' as auth_bridge;

enum AuthStatus { locked, unlocked }

class AuthState {
  final AuthStatus status;
  final int failedAttempts;

  const AuthState({
    this.status = AuthStatus.locked,
    this.failedAttempts = 0,
  });

  AuthState copyWith({AuthStatus? status, int? failedAttempts}) {
    return AuthState(
      status: status ?? this.status,
      failedAttempts: failedAttempts ?? this.failedAttempts,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthNotifier(this._ref)
      : super(const AuthState(
          status: AuthStatus.locked,
          failedAttempts: 0,
        ));

  Timer? _idleTimer;

  /// Default idle timeout: 15 minutes.
  static const int kDefaultIdleTimeoutSeconds = 900;

  /// Escalating delay schedule (in seconds) for consecutive wrong attempts.
  /// Index 0 = first failure delay, index 5 = 6th+ failure delay.
  static const List<int> _delays = [0, 1, 2, 5, 10, 30];

  /// Read the current idle timeout from the provider (set from SharedPreferences).
  int get _timeoutSeconds =>
      _ref.read(idleTimeoutSecondsProvider);

  /// Returns the delay in seconds for the given number of failed attempts.
  /// 0 attempts (first try) → 0s delay. Subsequent failures use escalating table.
  static int delayForAttempt(int attempts) {
    if (attempts <= 0) return 0;
    return _delays[(attempts - 1).clamp(0, _delays.length - 1)];
  }

  /// Verify [password] against the stored hash and unlock the app.
  ///
  /// On success: sets state to unlocked and starts the idle timer.
  /// On failure: throws, caller should call [recordFailedAttempt].
  Future<void> unlock(String password) async {
    // Step 1: verify password via Rust scrypt (throws on wrong password)
    await auth_bridge.verifyAppPassword(password: password);

    // Step 2: load wallets from Keychain into session, clear APP_LOCKED flag
    await auth_bridge.unlockApp();

    // Step 3: update state and start idle timer
    state = const AuthState(
      status: AuthStatus.unlocked,
      failedAttempts: 0,
    );
    _resetIdleTimer();
  }

  /// Record a failed unlock attempt and increment the counter.
  void recordFailedAttempt() {
    state = state.copyWith(failedAttempts: state.failedAttempts + 1);
  }

  /// Lock the app: cancel idle timer, zeroize wallet seeds via Rust, update state.
  Future<void> lock() async {
    _idleTimer?.cancel();
    await auth_bridge.lockApp();
    state = AuthState(
      status: AuthStatus.locked,
      failedAttempts: state.failedAttempts,
    );
  }

  /// Reset the idle timer on user activity. No-op when locked.
  void resetActivity() {
    if (state.status == AuthStatus.unlocked) {
      _resetIdleTimer();
    }
  }

  /// Cancel any existing timer and start a fresh one.
  /// If timeout is 0 (Never), the timer is not started.
  void _resetIdleTimer() {
    _idleTimer?.cancel();
    final timeout = _timeoutSeconds;
    if (timeout <= 0) return; // "Never" auto-lock
    _idleTimer = Timer(Duration(seconds: timeout), () {
      lock();
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}

/// Auth state provider. Starts locked on every app launch.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

/// Idle timeout in seconds, loaded from SharedPreferences at startup.
/// 0 means "Never" — no auto-lock.
final idleTimeoutSecondsProvider = StateProvider<int>((ref) {
  return AuthNotifier.kDefaultIdleTimeoutSeconds;
});

/// Load idle timeout from SharedPreferences and populate [idleTimeoutSecondsProvider].
/// Call once at app startup inside a WidgetRef context.
Future<void> initIdleTimeout(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final seconds =
      prefs.getInt('idle_timeout_seconds') ?? AuthNotifier.kDefaultIdleTimeoutSeconds;
  ref.read(idleTimeoutSecondsProvider.notifier).state = seconds;
}

/// Persist a new idle timeout value to SharedPreferences and update the provider.
Future<void> setIdleTimeout(WidgetRef ref, int seconds) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('idle_timeout_seconds', seconds);
  ref.read(idleTimeoutSecondsProvider.notifier).state = seconds;
}
