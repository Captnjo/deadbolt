import 'package:flutter/material.dart';

import '../../providers/wallet_emoji_provider.dart';
import '../../theme/brand_theme.dart';

Future<String?> showEmojiPickerDialog(
  BuildContext context, {
  String? currentEmoji,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _EmojiPickerDialog(currentEmoji: currentEmoji),
  );
}

class _EmojiPickerDialog extends StatelessWidget {
  final String? currentEmoji;

  const _EmojiPickerDialog({this.currentEmoji});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose emoji'),
      content: SizedBox(
        width: 300,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: walletEmojiOptions.map((emoji) {
            final selected = emoji == currentEmoji;
            return InkWell(
              onTap: () => Navigator.pop(context, emoji),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: selected
                      ? Border.all(color: BrandColors.primary, width: 2)
                      : Border.all(color: BrandColors.border),
                  color: selected
                      ? BrandColors.primary.withAlpha(20)
                      : BrandColors.card,
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
