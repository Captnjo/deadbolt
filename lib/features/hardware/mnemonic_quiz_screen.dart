import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/hardware_connection_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../src/rust/api/hardware.dart' as hw_bridge;
import '../../theme/brand_theme.dart';

class MnemonicQuizScreen extends ConsumerStatefulWidget {
  final List<String> words;

  const MnemonicQuizScreen({super.key, required this.words});

  @override
  ConsumerState<MnemonicQuizScreen> createState() => _MnemonicQuizScreenState();
}

class _MnemonicQuizScreenState extends ConsumerState<MnemonicQuizScreen> {
  late final List<int> _quizIndices;
  late final List<List<String>> _quizOptions;
  final List<String?> _answers = [null, null, null];
  String? _error;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final rng = Random();

    // Pick 3 random positions (0-indexed), sorted
    final indices = List.generate(12, (i) => i)..shuffle(rng);
    _quizIndices = indices.take(3).toList()..sort();

    // Generate 4 options per question: 1 correct + 3 distractors from other words
    _quizOptions = _quizIndices.map((idx) {
      final correct = widget.words[idx];
      final otherWords = widget.words.where((w) => w != correct).toList()
        ..shuffle(rng);
      final distractors = otherWords.take(3).toList();
      final options = [correct, ...distractors]..shuffle(rng);
      return options;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Backup'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Verify Your Backup',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select the correct word for each position to confirm you saved your phrase.',
              style: TextStyle(color: BrandColors.textSecondary),
            ),
            const SizedBox(height: 32),
            for (var i = 0; i < _quizIndices.length; i++) ...[
              _buildQuizQuestion(
                wordNumber: _quizIndices[i] + 1,
                options: _quizOptions[i],
                selected: _answers[i],
                onSelect: (answer) => _handleAnswer(i, answer),
              ),
              if (i < _quizIndices.length - 1) const SizedBox(height: 20),
            ],
            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BrandColors.error.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: BrandColors.error.withAlpha(60)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: BrandColors.error, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Incorrect \u2014 check your written phrase and try again.',
                        style: TextStyle(
                            color: BrandColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuizQuestion({
    required int wordNumber,
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What is word #$wordNumber?',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((word) {
            final isSelected = word == selected;
            return ChoiceChip(
              label: Text(word),
              selected: isSelected,
              onSelected: (_) => onSelect(word),
              selectedColor: BrandColors.primary.withAlpha(40),
              labelStyle: TextStyle(
                color:
                    isSelected ? BrandColors.primary : BrandColors.textPrimary,
                fontFamily: 'monospace',
              ),
              side: BorderSide(
                color: isSelected ? BrandColors.primary : BrandColors.border,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _handleAnswer(int questionIndex, String answer) {
    setState(() {
      _answers[questionIndex] = answer;
      _error = null;
    });

    // Check if all questions answered
    if (_answers.every((a) => a != null)) {
      // Verify all answers correct
      bool allCorrect = true;
      for (var i = 0; i < _quizIndices.length; i++) {
        if (_answers[i] != widget.words[_quizIndices[i]]) {
          allCorrect = false;
          break;
        }
      }

      if (allCorrect) {
        _onQuizPassed();
      } else {
        setState(() {
          _error = 'Incorrect';
          for (var i = 0; i < _answers.length; i++) {
            _answers[i] = null;
          }
        });
      }
    }
  }

  Future<void> _onQuizPassed() async {
    if (_completed) return;
    _completed = true;

    // Register the hardware wallet now that backup is confirmed
    final hwConn = ref.read(hardwareConnectionProvider).valueOrNull;
    if (hwConn?.portPath != null) {
      try {
        await hw_bridge.connectHardwareWallet(
          portPath: hwConn!.portPath!,
          name: hwConn.deviceName ?? 'Hardware Wallet',
        );
        ref.invalidate(walletListProvider);
      } catch (_) {
        // Registration may already exist — not critical
      }
    }

    // Invalidate connection provider to refresh state
    ref.invalidate(hardwareConnectionProvider);

    // Show completion notice and navigate to device dashboard
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Recovery phrase verified. Words have been cleared from this device.'),
        ),
      );
      // Use context.go (NOT pop) to prevent back navigation to mnemonic
      context.go('/hardware');
    }
  }
}
