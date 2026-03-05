import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../shared/widgets/mnemonic_grid.dart';
import '../../../theme/brand_theme.dart';
import '../widgets/security_tip.dart';

class DisplayMnemonicStep extends ConsumerWidget {
  const DisplayMnemonicStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingStateProvider);
    final notifier = ref.read(onboardingStateProvider.notifier);

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.error!, style: const TextStyle(color: BrandColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: notifier.back,
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your Recovery Phrase',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Write down these words in order and store them somewhere safe.',
            style: TextStyle(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BrandColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BrandColors.warning.withAlpha(80)),
            ),
            child: MnemonicGrid(words: state.mnemonic),
          ),
          const SizedBox(height: 20),
          const SecurityTip(
            text: 'Write this down on paper. Do not store it digitally '
                '(no screenshots, no notes apps, no cloud storage).',
            level: SecurityTipLevel.critical,
          ),
          const SizedBox(height: 12),
          const SecurityTip(
            text: 'Anyone with this phrase can access your funds. '
                'Deadbolt will never ask for it again after setup.',
            level: SecurityTipLevel.warning,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: state.mnemonic.join(' ')),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recovery phrase copied')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy to Clipboard'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: notifier.advanceFromMnemonic,
            child: const Text("I've Written It Down"),
          ),
        ],
      ),
    );
  }
}
