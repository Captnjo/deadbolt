import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/wallet_emoji_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/brand_theme.dart';

class WalletDrawer extends ConsumerWidget {
  final VoidCallback onClose;

  const WalletDrawer({super.key, required this.onClose});

  String _shortAddress(String addr) {
    if (addr.length > 8) {
      return '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}';
    }
    return addr;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletsAsync = ref.watch(walletListProvider);
    final activeAddress = ref.watch(activeWalletProvider);
    final emojiMap = ref.watch(walletEmojiProvider).valueOrNull ?? {};

    return Container(
      width: 280,
      color: BrandColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 36), // title bar spacer
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                const Text(
                  'Wallets',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: walletsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (wallets) => ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: wallets.length,
                itemBuilder: (context, index) {
                  final w = wallets[index];
                  final isActive = w.address == activeAddress;
                  final emoji =
                      resolveWalletEmoji(emojiMap, w.address, w.source);

                  return _DrawerWalletTile(
                    name: w.name,
                    shortAddress: _shortAddress(w.address),
                    emoji: emoji,
                    isActive: isActive,
                    onTap: () {
                      ref
                          .read(walletListProvider.notifier)
                          .setActive(w.address);
                      onClose();
                    },
                  );
                },
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: () {
                onClose();
                context.go('/wallets');
              },
              child: const Text('Manage wallets'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerWalletTile extends StatelessWidget {
  final String name;
  final String shortAddress;
  final String emoji;
  final bool isActive;
  final VoidCallback onTap;

  const _DrawerWalletTile({
    required this.name,
    required this.shortAddress,
    required this.emoji,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: isActive
              ? const Border(
                  left: BorderSide(color: BrandColors.primary, width: 3),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? BrandColors.primary.withAlpha(30)
                    : BrandColors.card,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    shortAddress,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: BrandColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              const Icon(Icons.check, size: 16, color: BrandColors.primary),
          ],
        ),
      ),
    );
  }
}
