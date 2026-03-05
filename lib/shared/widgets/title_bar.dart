import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/brand_theme.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  static const double height = 28;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: height,
        color: BrandColors.surface,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/deadbolt_logomark.png',
              height: 14,
              width: 14,
              color: Colors.white,
              colorBlendMode: BlendMode.srcIn,
            ),
            const SizedBox(width: 1),
            const Text(
              'eadbolt',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
