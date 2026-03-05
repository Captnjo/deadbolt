import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/onboarding_provider.dart';
import '../../theme/brand_theme.dart';
import 'steps/welcome_step.dart';
import 'steps/wallet_name_step.dart';
import 'steps/display_mnemonic_step.dart';
import 'steps/verify_backup_step.dart';
import 'steps/import_phrase_step.dart';
import 'steps/detect_device_step.dart';
import 'steps/connect_device_step.dart';
import 'steps/complete_step.dart';

class OnboardingShell extends ConsumerWidget {
  const OnboardingShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingStateProvider);
    final notifier = ref.read(onboardingStateProvider.notifier);
    final showBack = state.step != OnboardingStep.welcome;

    return CallbackShortcuts(
      bindings: {
        if (showBack)
          const SingleActivator(LogicalKeyboardKey.escape): notifier.back,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: BrandColors.background,
      body: Column(
        children: [
          // Progress bar
          if (state.path != null)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: state.progress),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: BrandColors.card,
                  valueColor: const AlwaysStoppedAnimation(BrandColors.primary),
                  minHeight: 3,
                );
              },
            ),

          // Top bar with back button
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: notifier.back,
                  tooltip: 'Back',
                ),
              ),
            ),

          // Content
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(state.step),
                    child: _buildStep(state.step),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }

  Widget _buildStep(OnboardingStep step) {
    return switch (step) {
      OnboardingStep.welcome => const WelcomeStep(),
      OnboardingStep.walletName => const WalletNameStep(),
      OnboardingStep.displayMnemonic => const DisplayMnemonicStep(),
      OnboardingStep.verifyBackup => const VerifyBackupStep(),
      OnboardingStep.importPhrase => const ImportPhraseStep(),
      OnboardingStep.detectDevice => const DetectDeviceStep(),
      OnboardingStep.connectDevice => const ConnectDeviceStep(),
      OnboardingStep.complete => const CompleteStep(),
    };
  }
}
