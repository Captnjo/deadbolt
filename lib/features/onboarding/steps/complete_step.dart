import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../theme/brand_theme.dart';

class CompleteStep extends ConsumerWidget {
  const CompleteStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingStateProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle,
            color: BrandColors.success,
            size: 72,
          ),
          const SizedBox(height: 24),
          const Text(
            "You're All Set!",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (state.createdWallet != null) ...[
            Text(
              state.createdWallet!.name,
              style: const TextStyle(fontSize: 18, color: BrandColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              _shortAddress(state.createdWallet!.address),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: BrandColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 32),
          const Text(
            'Your wallet is ready. Tap the avatar in the sidebar to switch wallets.',
            textAlign: TextAlign.center,
            style: TextStyle(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: state.loading
                ? null
                : () async {
                    await ref
                        .read(onboardingStateProvider.notifier)
                        .completeOnboarding();
                    if (context.mounted) {
                      context.go('/dashboard');
                    }
                  },
            child: state.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Get Started'),
          ),
        ],
      ),
    );
  }

  String _shortAddress(String addr) {
    if (addr.length > 12) {
      return '${addr.substring(0, 6)}...${addr.substring(addr.length - 6)}';
    }
    return addr;
  }
}
