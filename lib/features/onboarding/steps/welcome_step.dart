import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../theme/brand_theme.dart';

class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingStateProvider.notifier);
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/deadbolt_logo.png',
            height: 80,
            color: Colors.white,
            colorBlendMode: BlendMode.srcIn,
            errorBuilder: (_, e, s) =>
                const Icon(Icons.lock, size: 64, color: BrandColors.primary),
          ),
          const SizedBox(height: 24),
          const Text(
            'Welcome to Deadbolt',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your self-custodial Solana wallet',
            style: TextStyle(color: BrandColors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 48),
          _PathCard(
            icon: Icons.add_circle_outline,
            title: 'Create New Wallet',
            subtitle: 'Generate a new seed phrase',
            onTap: () => notifier.choosePath(OnboardingPath.create),
          ),
          const SizedBox(height: 12),
          _PathCard(
            icon: Icons.download_outlined,
            title: 'Import Existing Wallet',
            subtitle: 'Enter your recovery phrase',
            onTap: () => notifier.choosePath(OnboardingPath.import_),
          ),
          if (isMacOS) ...[
            const SizedBox(height: 12),
            _PathCard(
              icon: Icons.usb_outlined,
              title: 'Connect Hardware Wallet',
              subtitle: 'Use an Unruggable signer via USB',
              onTap: () => notifier.choosePath(OnboardingPath.hardware),
            ),
          ],
        ],
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: BrandColors.primary, size: 28),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: BrandColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right, color: BrandColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
