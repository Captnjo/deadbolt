import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/wallet_provider.dart';
import '../../shared/wallet_name_generator.dart';
import '../../shared/widgets/mnemonic_grid.dart';
import '../../theme/brand_theme.dart';

class CreateWalletScreen extends ConsumerStatefulWidget {
  const CreateWalletScreen({super.key});

  @override
  ConsumerState<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends ConsumerState<CreateWalletScreen> {
  final _nameController = TextEditingController(text: generateWalletName());
  List<String>? _mnemonic;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a wallet name');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final words = await ref
          .read(walletListProvider.notifier)
          .createWallet(name, 12);
      setState(() {
        _mnemonic = words;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/wallets'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: _mnemonic != null ? _buildMnemonicView() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Create a new wallet',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'A recovery phrase will be generated. Write it down and store it safely.',
            style: TextStyle(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Wallet Name',
              hintText: 'e.g. Main Wallet',
            ),
            autofocus: true,
            onSubmitted: (_) => _create(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: BrandColors.error)),
          ],
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _loading ? null : _create,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Generate Wallet'),
          ),
        ],
      ),
    );
  }

  Widget _buildMnemonicView() {
    final words = _mnemonic!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: BrandColors.success, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Wallet Created',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Write down your recovery phrase and store it in a safe place. '
            'Anyone with this phrase can access your funds.',
            style: TextStyle(color: BrandColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: BrandColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BrandColors.warning.withAlpha(80)),
            ),
            child: MnemonicGrid(words: words),
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Icon(Icons.warning_amber, color: BrandColors.warning, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Never share your recovery phrase with anyone',
                  style: TextStyle(color: BrandColors.warning, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: words.join(' ')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recovery phrase copied')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy to Clipboard'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.go('/wallets'),
            child: const Text("I've saved my recovery phrase"),
          ),
        ],
      ),
    );
  }
}
