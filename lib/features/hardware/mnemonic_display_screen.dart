import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:no_screenshot/no_screenshot.dart';

import '../../shared/widgets/mnemonic_grid.dart';
import '../../features/onboarding/widgets/security_tip.dart';
import '../../theme/brand_theme.dart';

class MnemonicDisplayScreen extends ConsumerStatefulWidget {
  final List<String> words;

  const MnemonicDisplayScreen({super.key, required this.words});

  @override
  ConsumerState<MnemonicDisplayScreen> createState() =>
      _MnemonicDisplayScreenState();
}

class _MnemonicDisplayScreenState
    extends ConsumerState<MnemonicDisplayScreen> {
  @override
  void initState() {
    super.initState();
    NoScreenshot.instance.screenshotOff();
  }

  @override
  void dispose() {
    NoScreenshot.instance.screenshotOn();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Recovery Phrase'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
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
              'Write down these 12 words in order. You\'ll verify them on the next screen.',
              style: TextStyle(color: BrandColors.textSecondary),
            ),
            const SizedBox(height: 24),
            const SecurityTip(
              text: 'Screenshot blocked \u2014 write down your words.',
              level: SecurityTipLevel.critical,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BrandColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BrandColors.warning.withAlpha(80)),
              ),
              child: MnemonicGrid(words: widget.words),
            ),
            const SizedBox(height: 20),
            const SecurityTip(
              text: 'Write this down on paper. Do not store it digitally '
                  '(no screenshots, no notes apps, no cloud storage).',
              level: SecurityTipLevel.critical,
            ),
            const SizedBox(height: 12),
            const SecurityTip(
              text:
                  'Anyone with this phrase can access your funds. Deadbolt will not show it again.',
              level: SecurityTipLevel.warning,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () =>
                  context.go('/hardware/quiz', extra: widget.words),
              child: const Text("I've Written It Down"),
            ),
          ],
        ),
      ),
    );
  }
}
