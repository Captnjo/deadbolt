import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../theme/brand_theme.dart';

class ConnectDeviceStep extends ConsumerWidget {
  const ConnectDeviceStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingStateProvider);
    final notifier = ref.read(onboardingStateProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connecting Device',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          if (state.loading) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            const Text(
              'Communicating with device...',
              textAlign: TextAlign.center,
              style: TextStyle(color: BrandColors.textSecondary),
            ),
          ] else if (state.error != null) ...[
            const Icon(Icons.error_outline, color: BrandColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: BrandColors.error),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: notifier.back,
              child: const Text('Try Again'),
            ),
          ] else if (state.createdWallet != null) ...[
            const Icon(Icons.check_circle, color: BrandColors.success, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Device Connected',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              state.createdWallet!.address,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: BrandColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                // Advance to complete step
                notifier.advanceFromVerify();
              },
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}
