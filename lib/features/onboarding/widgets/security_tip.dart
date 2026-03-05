import 'package:flutter/material.dart';

import '../../../theme/brand_theme.dart';

enum SecurityTipLevel { info, warning, critical }

/// Colored banner with icon for security education during onboarding.
class SecurityTip extends StatelessWidget {
  final String text;
  final SecurityTipLevel level;

  const SecurityTip({
    super.key,
    required this.text,
    this.level = SecurityTipLevel.info,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (level) {
      SecurityTipLevel.info => (BrandColors.primary, Icons.info_outline),
      SecurityTipLevel.warning => (BrandColors.warning, Icons.warning_amber),
      SecurityTipLevel.critical => (BrandColors.error, Icons.shield_outlined),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
