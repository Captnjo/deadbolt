import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/auth.dart' as auth_bridge;
import '../src/rust/api/wallet.dart' as bridge;
import '../src/rust/api/hardware.dart' as hw_bridge;
import '../src/rust/api/types.dart';
import '../src/rust/api/hardware.dart' show DetectedPortDto;
import 'wallet_provider.dart';

/// Whether the app should show onboarding.
final needsOnboardingProvider = Provider<bool>((ref) {
  return bridge.needsOnboarding();
});

/// Path the user chooses during onboarding.
enum OnboardingPath { create, import_, hardware }

/// Steps in the onboarding wizard.
enum OnboardingStep {
  welcome,
  setPassword,
  walletName,
  displayMnemonic,
  verifyBackup,
  importPhrase,
  detectDevice,
  connectDevice,
  complete,
}

/// State for the onboarding wizard.
class OnboardingState {
  final OnboardingStep step;
  final OnboardingPath? path;
  final String walletName;
  final List<String> mnemonic;
  final List<int> quizIndices;
  final Map<int, String?> quizAnswers;
  final List<List<String>> quizOptions;
  final String? error;
  final bool loading;
  final DetectedPortDto? detectedDevice;
  final WalletInfoDto? createdWallet;
  final String? password; // Held temporarily during onboarding, cleared on complete

  const OnboardingState({
    this.step = OnboardingStep.welcome,
    this.path,
    this.walletName = '',
    this.mnemonic = const [],
    this.quizIndices = const [],
    this.quizAnswers = const {},
    this.quizOptions = const [],
    this.error,
    this.loading = false,
    this.detectedDevice,
    this.createdWallet,
    this.password,
  });

  OnboardingState copyWith({
    OnboardingStep? step,
    OnboardingPath? path,
    String? walletName,
    List<String>? mnemonic,
    List<int>? quizIndices,
    Map<int, String?>? quizAnswers,
    List<List<String>>? quizOptions,
    String? error,
    bool? loading,
    DetectedPortDto? detectedDevice,
    WalletInfoDto? createdWallet,
    String? password,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      path: path ?? this.path,
      walletName: walletName ?? this.walletName,
      mnemonic: mnemonic ?? this.mnemonic,
      quizIndices: quizIndices ?? this.quizIndices,
      quizAnswers: quizAnswers ?? this.quizAnswers,
      quizOptions: quizOptions ?? this.quizOptions,
      error: error,
      loading: loading ?? this.loading,
      detectedDevice: detectedDevice ?? this.detectedDevice,
      createdWallet: createdWallet ?? this.createdWallet,
      // password uses same explicit-null pattern as error: passing null clears it.
      // Callers that want to preserve it must not pass the parameter.
      password: password,
    );
  }

  /// Progress through the onboarding (0.0–1.0).
  double get progress {
    if (path == null) return 0.0;
    final steps = _stepsForPath(path!);
    final idx = steps.indexOf(step);
    if (idx < 0) return 0.0;
    return (idx + 1) / steps.length;
  }

  static List<OnboardingStep> _stepsForPath(OnboardingPath path) {
    switch (path) {
      case OnboardingPath.create:
        return [
          OnboardingStep.welcome,
          OnboardingStep.setPassword,
          OnboardingStep.walletName,
          OnboardingStep.displayMnemonic,
          OnboardingStep.verifyBackup,
          OnboardingStep.complete,
        ];
      case OnboardingPath.import_:
        return [
          OnboardingStep.welcome,
          OnboardingStep.setPassword,
          OnboardingStep.walletName,
          OnboardingStep.importPhrase,
          OnboardingStep.complete,
        ];
      case OnboardingPath.hardware:
        return [
          OnboardingStep.welcome,
          OnboardingStep.setPassword,
          OnboardingStep.walletName,
          OnboardingStep.detectDevice,
          OnboardingStep.connectDevice,
          OnboardingStep.complete,
        ];
    }
  }
}

/// Notifier for the onboarding wizard.
class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void choosePath(OnboardingPath path) {
    state = state.copyWith(
      path: path,
      step: OnboardingStep.setPassword,
    );
  }

  void setWalletName(String name) {
    state = state.copyWith(walletName: name);
  }

  /// Store the app password via FFI then advance to the wallet name step.
  Future<void> advanceFromPassword(String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      await auth_bridge.setAppPassword(password: password);
      state = state.copyWith(
        step: OnboardingStep.walletName,
        password: password, // Held temporarily; cleared in completeOnboarding
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), loading: false);
    }
  }

  void advanceFromName() {
    if (state.walletName.trim().isEmpty) {
      state = state.copyWith(error: 'Please enter a wallet name');
      return;
    }
    state = state.copyWith(error: null);
    switch (state.path!) {
      case OnboardingPath.create:
        state = state.copyWith(step: OnboardingStep.displayMnemonic, loading: true);
        _generateWallet();
      case OnboardingPath.import_:
        state = state.copyWith(step: OnboardingStep.importPhrase);
      case OnboardingPath.hardware:
        state = state.copyWith(step: OnboardingStep.detectDevice);
    }
  }

  Future<void> _generateWallet() async {
    try {
      final result = await bridge.createWallet(
        name: state.walletName.trim(),
        wordCount: 12,
      );
      final mnemonic = result.mnemonicWords;

      // Pick 3 random indices for quiz
      final rng = Random.secure();
      final indices = <int>{};
      while (indices.length < 3) {
        indices.add(rng.nextInt(mnemonic.length));
      }
      final quizIndices = indices.toList()..sort();

      // Generate 4 options per quiz word (correct + 3 distractors)
      final quizOptions = <List<String>>[];
      for (final idx in quizIndices) {
        final correct = mnemonic[idx];
        var distractors = bridge.randomBip39Words(count: 6);
        distractors.removeWhere((w) => w == correct);
        distractors = distractors.take(3).toList();
        final options = [correct, ...distractors]..shuffle(rng);
        quizOptions.add(options);
      }

      state = state.copyWith(
        mnemonic: mnemonic,
        quizIndices: quizIndices,
        quizOptions: quizOptions,
        loading: false,
        createdWallet: result.wallet,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), loading: false);
    }
  }

  void advanceFromMnemonic() {
    state = state.copyWith(step: OnboardingStep.verifyBackup);
  }

  /// Answer a quiz question. Returns true if all 3 are answered correctly.
  bool answerQuiz(int quizIndex, String answer) {
    final newAnswers = Map<int, String?>.from(state.quizAnswers);
    newAnswers[quizIndex] = answer;
    state = state.copyWith(quizAnswers: newAnswers, error: null);

    // Check if all answered
    if (newAnswers.length == state.quizIndices.length) {
      for (var i = 0; i < state.quizIndices.length; i++) {
        if (newAnswers[i] != state.mnemonic[state.quizIndices[i]]) {
          state = state.copyWith(
            error: 'One or more answers are incorrect. Try again.',
            quizAnswers: {},
          );
          return false;
        }
      }
      return true;
    }
    return false;
  }

  void advanceFromVerify() {
    state = state.copyWith(step: OnboardingStep.complete);
  }

  Future<void> importWallet(List<String> words) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final wallet = await bridge.importWallet(
        name: state.walletName.trim(),
        words: words,
      );
      state = state.copyWith(
        loading: false,
        createdWallet: wallet,
        mnemonic: words,
        step: OnboardingStep.complete,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), loading: false);
    }
  }

  void selectDevice(DetectedPortDto device) {
    state = state.copyWith(detectedDevice: device);
  }

  void advanceFromDetect() {
    state = state.copyWith(step: OnboardingStep.connectDevice, loading: true);
    _connectDevice();
  }

  Future<void> _connectDevice() async {
    try {
      final device = state.detectedDevice!;
      final wallet = await hw_bridge.connectHardwareWallet(
        portPath: device.path,
        name: state.walletName.trim(),
      );
      state = state.copyWith(loading: false, createdWallet: wallet);
    } catch (e) {
      state = state.copyWith(error: e.toString(), loading: false);
    }
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(loading: true);
    try {
      await bridge.completeOnboarding();
      state = state.copyWith(password: null); // Clear password from Dart memory
      ref.invalidate(needsOnboardingProvider);
      ref.invalidate(walletListProvider);
    } catch (e) {
      state = state.copyWith(error: e.toString(), loading: false);
    }
  }

  void back() {
    final path = state.path;
    switch (state.step) {
      case OnboardingStep.welcome:
        return; // Can't go back
      case OnboardingStep.setPassword:
        state = state.copyWith(step: OnboardingStep.welcome);
      case OnboardingStep.walletName:
        state = state.copyWith(step: OnboardingStep.setPassword);
      case OnboardingStep.displayMnemonic:
        state = state.copyWith(step: OnboardingStep.walletName);
      case OnboardingStep.verifyBackup:
        state = state.copyWith(
          step: OnboardingStep.displayMnemonic,
          quizAnswers: {},
          error: null,
        );
      case OnboardingStep.importPhrase:
        state = state.copyWith(step: OnboardingStep.walletName);
      case OnboardingStep.detectDevice:
        state = state.copyWith(step: OnboardingStep.walletName);
      case OnboardingStep.connectDevice:
        state = state.copyWith(step: OnboardingStep.detectDevice);
      case OnboardingStep.complete:
        if (path == OnboardingPath.create) {
          state = state.copyWith(step: OnboardingStep.verifyBackup);
        } else if (path == OnboardingPath.import_) {
          state = state.copyWith(step: OnboardingStep.importPhrase);
        } else {
          state = state.copyWith(step: OnboardingStep.connectDevice);
        }
    }
  }
}

final onboardingStateProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
  OnboardingNotifier.new,
);
