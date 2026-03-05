import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../theme/brand_theme.dart';

class VerifyBackupStep extends ConsumerWidget {
  const VerifyBackupStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingStateProvider);
    final notifier = ref.read(onboardingStateProvider.notifier);

    return SingleChildScrollView(
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
          for (var i = 0; i < state.quizIndices.length; i++) ...[
            _QuizQuestion(
              wordNumber: state.quizIndices[i] + 1,
              options: state.quizOptions[i],
              selected: state.quizAnswers[i],
              onSelect: (answer) {
                final allCorrect = notifier.answerQuiz(i, answer);
                if (allCorrect) {
                  notifier.advanceFromVerify();
                }
              },
            ),
            if (i < state.quizIndices.length - 1) const SizedBox(height: 20),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BrandColors.error.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BrandColors.error.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: BrandColors.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: const TextStyle(color: BrandColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizQuestion extends StatelessWidget {
  final int wordNumber;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _QuizQuestion({
    required this.wordNumber,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
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
                color: isSelected ? BrandColors.primary : BrandColors.textPrimary,
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
}
