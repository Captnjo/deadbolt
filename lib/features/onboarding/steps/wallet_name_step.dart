import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../shared/wallet_name_generator.dart';
import '../../../theme/brand_theme.dart';

class WalletNameStep extends ConsumerStatefulWidget {
  const WalletNameStep({super.key});

  @override
  ConsumerState<WalletNameStep> createState() => _WalletNameStepState();
}

class _WalletNameStepState extends ConsumerState<WalletNameStep> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final existing = ref.read(onboardingStateProvider).walletName;
    _controller.text = existing.isEmpty ? generateWalletName() : existing;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final notifier = ref.read(onboardingStateProvider.notifier);
    notifier.setWalletName(_controller.text);
    notifier.advanceFromName();
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(onboardingStateProvider.select((s) => s.error));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Name Your Wallet',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a name to identify this wallet.',
            style: TextStyle(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Wallet Name',
              hintText: 'e.g. Main Wallet',
            ),
            autofocus: true,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _submit(),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error, style: const TextStyle(color: BrandColors.error)),
          ],
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _submit,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
