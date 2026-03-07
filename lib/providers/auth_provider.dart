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
