import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/swap.dart';
import '../../models/token.dart';
import '../../providers/api_keys_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../src/rust/api/wallet.dart' as bridge;
import '../../theme/brand_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _heliusController;
  late TextEditingController _jupiterController;
  late TextEditingController _dflowController;
  bool _heliusObscured = true;
  bool _jupiterObscured = true;
  bool _dflowObscured = true;

  @override
  void initState() {
    super.initState();
    final net = ref.read(networkProvider);
    _heliusController = TextEditingController(text: net.heliusApiKey);
    final apiKeys = ref.read(apiKeysProvider);
    _jupiterController = TextEditingController(text: apiKeys.jupiterKey);
    _dflowController = TextEditingController(text: apiKeys.dflowKey);
  }

  @override
  void dispose() {
    _heliusController.dispose();
    _jupiterController.dispose();
    _dflowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final net = ref.watch(networkProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),

        // Network section
        const Text('Network',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BrandColors.textSecondary)),
        const SizedBox(height: 12),
        SegmentedButton<SolanaNetwork>(
          segments: const [
            ButtonSegment(
                value: SolanaNetwork.mainnet, label: Text('Mainnet')),
            ButtonSegment(
                value: SolanaNetwork.devnet, label: Text('Devnet')),
            ButtonSegment(
                value: SolanaNetwork.testnet, label: Text('Testnet')),
          ],
          selected: {net.network},
          onSelectionChanged: (selected) {
            ref.read(networkProvider.notifier).setNetwork(selected.first);
          },
        ),
        const SizedBox(height: 16),

        // Helius API key
        TextField(
          controller: _heliusController,
          obscureText: _heliusObscured,
          decoration: InputDecoration(
            labelText: 'Helius API Key',
            hintText: 'Optional — enables faster RPC',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_heliusObscured
                      ? Icons.visibility_off
                      : Icons.visibility, size: 20),
                  onPressed: () =>
                      setState(() => _heliusObscured = !_heliusObscured),
                ),
                IconButton(
                  icon: const Icon(Icons.save, size: 20),
                  onPressed: _saveHeliusKey,
                  tooltip: 'Save',
                ),
              ],
            ),
          ),
          onSubmitted: (_) => _saveHeliusKey(),
        ),
        const SizedBox(height: 12),

        // Current RPC URL
        Text(
          'RPC: ${net.rpcUrl}',
          style: const TextStyle(
            fontSize: 11,
            color: BrandColors.textSecondary,
            fontFamily: 'monospace',
          ),
        ),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),

        // Swap section (14.3)
        const Text('Swap',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BrandColors.textSecondary)),
        const SizedBox(height: 12),
        SegmentedButton<SwapAggregator>(
          segments: const [
            ButtonSegment(
                value: SwapAggregator.jupiter, label: Text('Jupiter')),
            ButtonSegment(
                value: SwapAggregator.dflow, label: Text('DFlow')),
          ],
          selected: {ref.watch(apiKeysProvider).defaultAggregator},
          onSelectionChanged: (selected) {
            ref
                .read(apiKeysProvider.notifier)
                .setDefaultAggregator(selected.first);
          },
        ),
        const SizedBox(height: 16),
        // Jupiter API key
        TextField(
          controller: _jupiterController,
          obscureText: _jupiterObscured,
          decoration: InputDecoration(
            labelText: 'Jupiter API Key',
            hintText: 'Optional — for higher rate limits',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_jupiterObscured
                      ? Icons.visibility_off
                      : Icons.visibility, size: 20),
                  onPressed: () =>
                      setState(() => _jupiterObscured = !_jupiterObscured),
                ),
                IconButton(
                  icon: const Icon(Icons.save, size: 20),
                  onPressed: _saveJupiterKey,
                  tooltip: 'Save',
                ),
              ],
            ),
          ),
          onSubmitted: (_) => _saveJupiterKey(),
        ),
        const SizedBox(height: 12),
        // DFlow API key
        TextField(
          controller: _dflowController,
          obscureText: _dflowObscured,
          decoration: InputDecoration(
            labelText: 'DFlow API Key',
            hintText: 'Optional — for DFlow aggregator',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_dflowObscured
                      ? Icons.visibility_off
                      : Icons.visibility, size: 20),
                  onPressed: () =>
                      setState(() => _dflowObscured = !_dflowObscured),
                ),
                IconButton(
                  icon: const Icon(Icons.save, size: 20),
                  onPressed: _saveDflowKey,
                  tooltip: 'Save',
                ),
              ],
            ),
          ),
          onSubmitted: (_) => _saveDflowKey(),
        ),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),

        // Preferences section (14.4)
        const Text('Preferences',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BrandColors.textSecondary)),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Jito MEV Protection'),
          subtitle: const Text('Route transactions through Jito bundles (mainnet only)',
              style: TextStyle(fontSize: 12, color: BrandColors.textSecondary)),
          value: ref.watch(apiKeysProvider).jitoMevProtection,
          activeThumbColor: BrandColors.primary,
          onChanged: (value) {
            ref.read(apiKeysProvider.notifier).setJitoMevProtection(value);
          },
        ),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text('Debug',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BrandColors.textSecondary)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _resetOnboarding(context),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Reset Onboarding'),
          style: OutlinedButton.styleFrom(
            foregroundColor: BrandColors.warning,
            side: const BorderSide(color: BrandColors.warning),
          ),
        ),
      ],
    );
  }

  void _saveJupiterKey() {
    final key = _jupiterController.text.trim();
    ref.read(apiKeysProvider.notifier).setJupiterKey(key);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Jupiter API key saved'),
          duration: Duration(seconds: 1)),
    );
  }

  void _saveDflowKey() {
    final key = _dflowController.text.trim();
    ref.read(apiKeysProvider.notifier).setDflowKey(key);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('DFlow API key saved'),
          duration: Duration(seconds: 1)),
    );
  }

  void _saveHeliusKey() {
    final key = _heliusController.text.trim();
    ref.read(networkProvider.notifier).setHeliusApiKey(key);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Helius API key saved'),
          duration: Duration(seconds: 1)),
    );
  }

  Future<void> _resetOnboarding(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset onboarding?'),
        content: const Text(
          'This will show the onboarding wizard again on next launch. '
          'Your wallets will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await bridge.resetOnboarding();
      ref.invalidate(needsOnboardingProvider);
      if (context.mounted) {
        context.go('/onboarding');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reset: $e')),
        );
      }
    }
  }
}
