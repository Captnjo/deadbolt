import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/currency.dart';
import '../../models/stake.dart';
import '../../models/token.dart';
import '../../providers/api_keys_provider.dart';
import '../../providers/balance_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/nft_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../shared/formatters.dart';
import '../../src/rust/api/hardware.dart' as hw_bridge;
import '../../theme/brand_theme.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAddress = ref.watch(activeWalletProvider);
    if (activeAddress == null) return _noWallet(context);

    final wallets = ref.watch(walletListProvider);
    final walletName = wallets.whenOrNull(
      data: (list) {
        final w = list.where((w) => w.address == activeAddress).firstOrNull;
        return w?.name;
      },
    );

    final net = ref.watch(networkProvider);
    final balanceAsync = ref.watch(balanceProvider);
    final currency = ref.watch(
        apiKeysProvider.select((s) => s.displayCurrency));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: balanceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _errorView(context, ref, err),
          data: (portfolio) => _content(
            context,
            ref,
            activeAddress,
            walletName ?? 'Wallet',
            net,
            portfolio,
            currency,
          ),
        ),
      ),
    );
  }

  Widget _noWallet(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('No wallet selected',
              style: TextStyle(fontSize: 20, color: BrandColors.textSecondary)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/wallets'),
            child: const Text('Manage wallets'),
          ),
        ],
      ),
    );
  }

  Widget _errorView(BuildContext context, WidgetRef ref, Object err) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: BrandColors.error),
          const SizedBox(height: 12),
          Text('Failed to load balance',
              style: TextStyle(color: BrandColors.textSecondary)),
          const SizedBox(height: 4),
          Text('$err',
              style: const TextStyle(fontSize: 12, color: BrandColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref.read(balanceProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    String address,
    String walletName,
    NetworkState net,
    PortfolioState portfolio,
    DisplayCurrency currency,
  ) {
    // Check if active wallet is hardware
    final walletsList = ref.watch(walletListProvider).valueOrNull ?? [];
    final activeWallet =
        walletsList.where((w) => w.address == address).firstOrNull;
    final isHardwareWallet = activeWallet?.source == 'hardware';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Header with HW status
        _header(context, address, walletName, net, ref,
            showHwIndicator: isHardwareWallet,
            hwConnected: ref.watch(hwDetectedProvider).valueOrNull ?? false),
        const SizedBox(height: 24),
        // Balance card
        _balanceCard(portfolio, net.network, currency),
        const SizedBox(height: 24),
        // Quick actions
        _quickActions(context),
        const SizedBox(height: 24),
        // Token list
        _tokenList(portfolio, currency),
        // Staked LST section
        _stakedLstSection(portfolio, currency),
        // NFT gallery (mainnet only)
        if (net.network == SolanaNetwork.mainnet)
          _nftGallery(context, ref),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    String address,
    String walletName,
    NetworkState net,
    WidgetRef ref, {
    bool showHwIndicator = false,
    bool hwConnected = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(walletName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    Formatters.shortAddress(address),
                    style: const TextStyle(
                        fontSize: 13, color: BrandColors.textSecondary,
                        fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: address));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Address copied'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                    child: const Icon(Icons.copy, size: 14,
                        color: BrandColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showHwIndicator) ...[
          IconButton(
            onPressed: () => _reconnectHardware(context, ref),
            tooltip: hwConnected ? 'Hardware wallet connected' : 'Tap to connect hardware wallet',
            icon: Icon(Icons.usb, size: 18,
                color: hwConnected ? BrandColors.primary : BrandColors.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
        ],
        _networkBadge(net.network),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () {
            ref.read(balanceProvider.notifier).refresh();
            ref.invalidate(hwDetectedProvider);
          },
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Future<void> _reconnectHardware(BuildContext context, WidgetRef ref) async {
    try {
      final ports = await hw_bridge.scanHardwareWallets();
      if (ports.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No hardware wallet detected'),
                duration: Duration(seconds: 2)),
          );
        }
        return;
      }
      // Auto-connect to first detected port using existing wallet name
      final wallets = ref.read(walletListProvider).valueOrNull ?? [];
      final activeAddr = ref.read(activeWalletProvider);
      final hw = wallets.where((w) => w.address == activeAddr).firstOrNull;
      await hw_bridge.connectHardwareWallet(
        portPath: ports.first.path,
        name: hw?.name ?? 'Hardware Wallet',
      );
      ref.invalidate(walletListProvider);
      ref.invalidate(hwDetectedProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Hardware wallet connected'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Connection failed: $e'),
              duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Widget _networkBadge(SolanaNetwork network) {
    final Color color;
    switch (network) {
      case SolanaNetwork.mainnet:
        color = BrandColors.success;
      case SolanaNetwork.devnet:
        color = BrandColors.warning;
      case SolanaNetwork.testnet:
        color = BrandColors.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        network.displayName,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _balanceCard(
      PortfolioState portfolio, SolanaNetwork network, DisplayCurrency currency) {
    final isMainnet = network == SolanaNetwork.mainnet && portfolio.solPrice > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              isMainnet
                  ? Formatters.formatCurrency(
                      portfolio.totalPortfolioDisplay, currency)
                  : '${Formatters.formatSol(portfolio.solBalance)} SOL',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            if (isMainnet) ...[
              const SizedBox(height: 4),
              Text(
                '${Formatters.formatSol(portfolio.solBalance)} SOL',
                style: const TextStyle(
                    fontSize: 14, color: BrandColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _actionButton(context, Icons.arrow_upward, 'Send', '/send'),
        _actionButton(context, Icons.arrow_downward, 'Receive', '/receive'),
        _actionButton(context, Icons.swap_horiz, 'Swap', '/swap'),
        _actionButton(context, Icons.image, 'Send NFT', '/send-nft'),
      ],
    );
  }

  Widget _actionButton(
      BuildContext context, IconData icon, String label, String? route) {
    return InkWell(
      onTap: () {
        if (route != null) {
          context.push(route);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('$label coming soon'),
                duration: const Duration(seconds: 1)),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BrandColors.primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: BrandColors.primary),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: BrandColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _tokenList(PortfolioState portfolio, DisplayCurrency currency) {
    // Build a unified list with SOL + all SPL tokens, sorted by USD value
    final solToken = TokenBalance(
      definition: TokenDefinition.sol(),
      rawAmount: portfolio.solBalance.toString(),
      uiAmount: portfolio.solUiAmount,
      usdPrice: portfolio.solPrice > 0 ? portfolio.solPrice : null,
    );
    final allTokens = [solToken, ...portfolio.tokenBalances];
    allTokens.sort((a, b) => (b.usdValue ?? 0).compareTo(a.usdValue ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tokens',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BrandColors.textSecondary)),
        const SizedBox(height: 8),
        ...allTokens.map((tb) => _tokenRow(tb, portfolio.exchangeRate, currency)),
      ],
    );
  }

  Widget _tokenRow(
      TokenBalance tb, double exchangeRate, DisplayCurrency currency) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: BrandColors.primary.withAlpha(30),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              tb.definition.symbol.substring(0, 1),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: BrandColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tb.definition.symbol,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(tb.definition.name,
                    style: const TextStyle(
                        fontSize: 12, color: BrandColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Formatters.formatTokenAmount(tb.uiAmount),
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              if (tb.usdValue != null)
                Text(
                    Formatters.formatCurrency(
                        tb.usdValue! * exchangeRate, currency),
                    style: const TextStyle(
                        fontSize: 12, color: BrandColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Staked LST Section (1.5) ───

  Widget _stakedLstSection(PortfolioState portfolio, DisplayCurrency currency) {
    final lstBalances = portfolio.tokenBalances
        .where((tb) => LstPools.mintSet.contains(tb.definition.mint))
        .toList();

    if (lstBalances.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('Staked',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: BrandColors.textSecondary)),
        const SizedBox(height: 8),
        ...lstBalances.map((tb) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: BrandColors.success.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.layers,
                        color: BrandColors.success, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tb.definition.symbol,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text(tb.definition.name,
                            style: const TextStyle(
                                fontSize: 12, color: BrandColors.textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Formatters.formatTokenAmount(tb.uiAmount),
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      if (tb.usdValue != null)
                        Text(
                            Formatters.formatCurrency(
                                tb.usdValue! * portfolio.exchangeRate, currency),
                            style: const TextStyle(
                                fontSize: 12, color: BrandColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            )),
      ],
    );
  }

  // ─── NFT Gallery (1.6) ───

  Widget _nftGallery(BuildContext context, WidgetRef ref) {
    final nftState = ref.watch(nftProvider);

    if (nftState.isLoadingNfts) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (nftState.nfts.isEmpty) return const SizedBox.shrink();

    final displayNfts = nftState.nfts.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('NFTs',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BrandColors.textSecondary)),
            if (nftState.nfts.length > 4)
              TextButton(
                onPressed: () => context.push('/send-nft'),
                child: const Text('View All',
                    style: TextStyle(fontSize: 12, color: BrandColors.primary)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: displayNfts.length,
          itemBuilder: (ctx, i) {
            final nft = displayNfts[i];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: nft.imageUrl != null
                        ? Image.network(
                            nft.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, st) => Container(
                              color: BrandColors.card,
                              alignment: Alignment.center,
                              child: const Icon(Icons.image,
                                  color: BrandColors.textSecondary, size: 24),
                            ),
                          )
                        : Container(
                            color: BrandColors.card,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image,
                                color: BrandColors.textSecondary, size: 24),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      nft.name,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
