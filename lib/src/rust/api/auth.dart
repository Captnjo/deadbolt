// Dart FFI bridge for the Rust auth module.
//
// This file provides typed stubs for the auth API until flutter_rust_bridge
// codegen can be run in a Flutter environment. At that point, run:
//   flutter_rust_bridge_codegen generate
// and the generated output will replace these stubs with real FFI calls.
//
// The function signatures below match rust/deadbolt_bridge/src/api/auth.rs exactly.

// ignore_for_file: unused_import

/// Set the app password (during onboarding). Async because scrypt is CPU-intensive.
Future<void> setAppPassword({required String password}) async {
  throw UnimplementedError(
    'setAppPassword: FRB codegen not yet run. '
    'Run flutter_rust_bridge_codegen generate to generate the real FFI bridge.',
  );
}

/// Verify the app password (for unlock). Async because scrypt is CPU-intensive.
/// Throws on wrong password.
Future<void> verifyAppPassword({required String password}) async {
  throw UnimplementedError(
    'verifyAppPassword: FRB codegen not yet run. '
    'Run flutter_rust_bridge_codegen generate to generate the real FFI bridge.',
  );
}

/// Change the app password. Requires current password verification first.
Future<void> changeAppPassword({
  required String current,
  required String newPassword,
}) async {
  throw UnimplementedError(
    'changeAppPassword: FRB codegen not yet run. '
    'Run flutter_rust_bridge_codegen generate to generate the real FFI bridge.',
  );
}

/// Check if an app password has been set.
bool hasAppPassword() {
  return false; // safe default: treats as no password set
}

/// Check if the app is currently locked.
bool isAppLocked() {
  return true; // safe default: app is locked until proven otherwise
}

/// Lock the app: set AtomicBool to true, then zeroize all wallet seeds.
Future<void> lockApp() async {
  throw UnimplementedError(
    'lockApp: FRB codegen not yet run. '
    'Run flutter_rust_bridge_codegen generate to generate the real FFI bridge.',
  );
}

/// Unlock the app after password verification.
/// Caller must call verifyAppPassword first, then call this.
/// Loads all Keychain wallets into session and sets AtomicBool to false.
Future<void> unlockApp() async {
  throw UnimplementedError(
    'unlockApp: FRB codegen not yet run. '
    'Run flutter_rust_bridge_codegen generate to generate the real FFI bridge.',
  );
}
