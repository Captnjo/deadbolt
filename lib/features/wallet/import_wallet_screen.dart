import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/wallet_provider.dart';
import '../../shared/wallet_name_generator.dart';
import '../../theme/brand_theme.dart';

class ImportWalletScreen extends ConsumerStatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  ConsumerState<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends ConsumerState<ImportWalletScreen> {
  final _nameController = TextEditingController(text: generateWalletName());
  final _mnemonicController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _mnemonicController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a wallet name');
      return;
    }

    final phrase = _mnemonicController.text.trim();
    final words = phrase.split(RegExp(r'\s+'));
    if (words.length != 12 && words.length != 24) {
      setState(
        () => _error = 'Recovery phrase must be 12 or 24 words (got ${words.length})',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(walletListProvider.notifier).importWallet(name, words);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wallet imported successfully'),
            backgroundColor: BrandColors.success,
          ),
        );
        context.go('/wallets');
      }
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
        title: const Text('Import Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/wallets'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Import existing wallet',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your 12 or 24 word recovery phrase to restore a wallet.',
                  style: TextStyle(color: BrandColors.textSecondary),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Name',
                    hintText: 'e.g. Imported Wallet',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _mnemonicController,
                  decoration: const InputDecoration(
                    labelText: 'Recovery Phrase',
                    hintText: 'Enter your 12 or 24 word recovery phrase',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: BrandColors.error)),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _loading ? null : _import,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Import Wallet'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
