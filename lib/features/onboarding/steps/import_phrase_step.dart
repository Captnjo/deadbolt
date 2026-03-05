import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../src/rust/api/wallet.dart' as bridge;
import '../../../theme/brand_theme.dart';
import '../widgets/security_tip.dart';

class ImportPhraseStep extends ConsumerStatefulWidget {
  const ImportPhraseStep({super.key});

  @override
  ConsumerState<ImportPhraseStep> createState() => _ImportPhraseStepState();
}

class _ImportPhraseStepState extends ConsumerState<ImportPhraseStep> {
  final _controller = TextEditingController();
  bool _isValid = false;
  int _wordCount = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final words = _parseWords();
    final valid = words.length >= 12 && bridge.validateMnemonic(words: words);
    setState(() {
      _wordCount = words.length;
      _isValid = valid;
    });
  }

  List<String> _parseWords() {
    return _controller.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  void _submit() {
    final words = _parseWords();
    ref.read(onboardingStateProvider.notifier).importWallet(words);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingStateProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Import Recovery Phrase',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your 12 or 24-word recovery phrase separated by spaces.',
            style: TextStyle(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'word1 word2 word3 ...',
              counterText: '$_wordCount words',
              counterStyle: TextStyle(
                color: _isValid ? BrandColors.success : BrandColors.textSecondary,
              ),
            ),
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Text(state.error!, style: const TextStyle(color: BrandColors.error)),
          ],
          const SizedBox(height: 20),
          const SecurityTip(
            text: 'Make sure no one can see your screen while entering your phrase.',
            level: SecurityTipLevel.warning,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isValid && !state.loading ? _submit : null,
            child: state.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Import Wallet'),
          ),
        ],
      ),
    );
  }
}
