import 'package:flutter/material.dart';

import '../../theme/brand_theme.dart';

/// Reusable numbered grid for displaying mnemonic words.
class MnemonicGrid extends StatelessWidget {
  final List<String> words;
  final Set<int>? highlightIndices;
  final bool obscured;

  const MnemonicGrid({
    super.key,
    required this.words,
    this.highlightIndices,
    this.obscured = false,
  });

  @override
  Widget build(BuildContext context) {
    final columns = words.length <= 12 ? 3 : 4;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(words.length, (i) {
        final highlighted = highlightIndices?.contains(i) ?? false;
        return SizedBox(
          width: columns == 3 ? 120.0 : 90.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: highlighted
                  ? BrandColors.primary.withAlpha(20)
                  : BrandColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: highlighted ? BrandColors.primary : BrandColors.border,
              ),
            ),
            child: Row(
              children: [
                Text(
                  '${i + 1}.',
                  style: const TextStyle(
                    color: BrandColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    obscured ? '\u2022\u2022\u2022\u2022' : words[i],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
