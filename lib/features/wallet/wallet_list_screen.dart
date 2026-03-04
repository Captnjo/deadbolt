import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/wallet_emoji_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../shared/widgets/emoji_picker_dialog.dart';
import '../../shared/widgets/mnemonic_grid.dart';
import '../../src/rust/api/types.dart';
import '../../src/rust/api/wallet.dart' as bridge;
import '../../theme/brand_theme.dart';

class WalletListScreen extends ConsumerWidget {
  const WalletListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletsAsync = ref.watch(walletListProvider);
    final activeAddress = ref.watch(activeWalletProvider);
    final emojiMap = ref.watch(walletEmojiProvider).valueOrNull ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage wallets'),
        actions: [
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.add),
                onPressed: () => context.go('/wallets/create'),
                child: const Text('Create New Wallet'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.download),
                onPressed: () => context.go('/wallets/import'),
                child: const Text('Import Seed Phrase'),
              ),
              if (defaultTargetPlatform == TargetPlatform.macOS)
                MenuItemButton(
                  leadingIcon: const Icon(Icons.usb),
                  onPressed: () => context.go('/wallets/hardware'),
                  child: const Text('Connect Hardware'),
                ),
            ],
            builder: (context, controller, _) => ElevatedButton.icon(
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Wallet'),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: walletsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (wallets) {
          if (wallets.isEmpty) {
            return _EmptyState();
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: wallets.length,
            itemBuilder: (context, index) {
              final w = wallets[index];
              final isActive = w.address == activeAddress;
              final emoji =
                  resolveWalletEmoji(emojiMap, w.address, w.source);
              return _WalletTile(
                wallet: w,
                emoji: emoji,
                isActive: isActive,
                onTap: () => ref
                    .read(walletListProvider.notifier)
                    .setActive(w.address),
                onDelete: () => _confirmDelete(context, ref, w),
                onShowMnemonic: () => _showMnemonic(context, w.address),
                onChangeEmoji: () => _changeEmoji(context, ref, w.address, emoji),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _changeEmoji(
    BuildContext context,
    WidgetRef ref,
    String address,
    String currentEmoji,
  ) async {
    final picked = await showEmojiPickerDialog(
      context,
      currentEmoji: currentEmoji,
    );
    if (picked != null) {
      await ref.read(walletEmojiProvider.notifier).setEmoji(address, picked);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WalletInfoDto wallet,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete wallet?'),
        content: Text(
          'This will permanently remove "${wallet.name}" and its vault files. '
          'Make sure you have backed up the recovery phrase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: BrandColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(walletEmojiProvider.notifier).removeEmoji(wallet.address);
      await ref.read(walletListProvider.notifier).removeWallet(wallet.address);
    }
  }

  Future<void> _showMnemonic(BuildContext context, String address) async {
    try {
      final words = await bridge.getMnemonic(address: address);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recovery Phrase'),
          content: SizedBox(
            width: 400,
            child: MnemonicGrid(words: words),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: words.join(' ')));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Recovery phrase copied')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to retrieve mnemonic: $e')),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: Colors.white12,
          ),
          const SizedBox(height: 24),
          const Text('No wallets yet', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          const Text(
            'Create a new wallet or import an existing one',
            style: TextStyle(color: Colors.white38),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.go('/wallets/import'),
                icon: const Icon(Icons.download),
                label: const Text('Import Wallet'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => context.go('/wallets/create'),
                icon: const Icon(Icons.add),
                label: const Text('Create Wallet'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletTile extends StatelessWidget {
  final WalletInfoDto wallet;
  final String emoji;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onShowMnemonic;
  final VoidCallback onChangeEmoji;

  const _WalletTile({
    required this.wallet,
    required this.emoji,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
    required this.onShowMnemonic,
    required this.onChangeEmoji,
  });

  String _shortAddress(String addr) {
    if (addr.length > 8) {
      return '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}';
    }
    return addr;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: isActive
              ? BrandColors.primary.withAlpha(40)
              : BrandColors.card,
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(wallet.name),
        subtitle: Row(
          children: [
            Text(
              _shortAddress(wallet.address),
              style: const TextStyle(
                fontFamily: 'monospace',
                color: BrandColors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: BrandColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                wallet.source,
                style: const TextStyle(fontSize: 10, color: BrandColors.textSecondary),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BrandColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'active',
                  style: TextStyle(fontSize: 10, color: BrandColors.primary),
                ),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18, color: BrandColors.textSecondary),
              tooltip: 'Copy Address',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: wallet.address));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Address copied')),
                );
              },
            ),
            PopupMenuButton<String>(
              onSelected: (action) {
                switch (action) {
                  case 'emoji':
                    onChangeEmoji();
                  case 'mnemonic':
                    onShowMnemonic();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'emoji',
                  child: Text('Change emoji'),
                ),
                const PopupMenuItem(
                  value: 'mnemonic',
                  child: Text('Show Recovery Phrase'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: BrandColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
