import 'package:flutter/material.dart';
import '../../../theme/brand_theme.dart';

enum PasswordStrength { weak, fair, strong }

/// Evaluates password strength based on length and character variety.
///
/// Rules:
/// - Length < 8 → weak
/// - Score = count of: hasUpper, hasLower, hasDigit, hasSpecial
/// - score >= 3 && length >= 12 → strong
/// - score >= 2 → fair
/// - otherwise → weak
PasswordStrength evaluateStrength(String password) {
  if (password.length < 8) return PasswordStrength.weak;

  final hasUpper = password.contains(RegExp(r'[A-Z]'));
  final hasLower = password.contains(RegExp(r'[a-z]'));
  final hasDigit = password.contains(RegExp(r'\d'));
  final hasSpecial = password.contains(RegExp(r'[^A-Za-z0-9]'));

  final score = [hasUpper, hasLower, hasDigit, hasSpecial]
      .where((b) => b)
      .length;

  if (score >= 3 && password.length >= 12) return PasswordStrength.strong;
  if (score >= 2) return PasswordStrength.fair;
  return PasswordStrength.weak;
}

/// Displays a horizontal strength bar (4px tall) with a label below.
///
/// Returns [SizedBox.shrink] when [password] is empty.
class PasswordStrengthMeter extends StatelessWidget {
  final String password;

  const PasswordStrengthMeter({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final strength = evaluateStrength(password);

    final double fillFraction;
    final Color barColor;
    final String label;
    final Color labelColor;

    switch (strength) {
      case PasswordStrength.weak:
        fillFraction = 0.33;
        barColor = BrandColors.warning;
        label = 'Weak';
        labelColor = BrandColors.warning;
      case PasswordStrength.fair:
        fillFraction = 0.66;
        barColor = BrandColors.success;
        label = 'Fair';
        labelColor = BrandColors.success;
      case PasswordStrength.strong:
        fillFraction = 1.0;
        barColor = BrandColors.primary;
        label = 'Strong';
        labelColor = BrandColors.primary;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 4,
            width: double.infinity,
            child: Stack(
              children: [
                // Grey background track
                Container(
                  color: BrandColors.border,
                ),
                // Colored foreground bar
                FractionallySizedBox(
                  widthFactor: fillFraction,
                  child: Container(color: barColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}
