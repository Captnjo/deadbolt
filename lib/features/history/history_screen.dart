import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/token.dart';
import '../../models/transaction_history.dart';
import '../../providers/history_provider.dart';
import '../../providers/network_provider.dart';
import '../../services/token_registry.dart';
import '../../theme/brand_theme.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _errorView(context, ref, err),
          data: (state) => _content(context, ref, state),
        ),
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
          const Text('Failed to load history',
              style: TextStyle(color: BrandColors.textSecondary)),
          const SizedBox(height: 4),
          Text('$err',
              style: const TextStyle(
                  fontSize: 12, color: BrandColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref.read(historyProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref, HistoryState state) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            children: [
              const Text('Transaction History',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    ref.read(historyProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Transaction list
        Expanded(
          child: state.entries.isEmpty
              ? _emptyState(true)
              : _transactionList(context, ref, state, state.entries),
        ),
      ],
    );
  }

  Widget _filterBar(WidgetRef ref, TransactionFilter activeFilter) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: TransactionFilter.values.map((filter) {
          final selected = filter == activeFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: selected,
              onSelected: (_) =>
                  ref.read(historyProvider.notifier).setFilter(filter),
              selectedColor: BrandColors.primary,
              labelStyle: TextStyle(
                color: selected ? Colors.white : BrandColors.textSecondary,
                fontSize: 12,
              ),
              side: BorderSide(
                color: selected ? BrandColors.primary : BrandColors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyState(bool noTransactions) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 48, color: BrandColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            noTransactions
                ? 'No transactions yet'
                : 'No transactions match filter',
            style: const TextStyle(color: BrandColors.textSecondary),
          ),
          if (noTransactions) ...[
            const SizedBox(height: 4),
            const Text(
              'Transactions will appear here once you\nsend, receive, or swap.',
              style: TextStyle(fontSize: 12, color: BrandColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _transactionList(
    BuildContext context,
    WidgetRef ref,
    HistoryState state,
    List<TransactionHistoryEntry> entries,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.extentAfter < 100 &&
            state.hasMore &&
            !state.isLoadingMore) {
          ref.read(historyProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: entries.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= entries.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final entry = entries[index];
          return _transactionRow(context, ref, entry);
        },
      ),
    );
  }

  Widget _transactionRow(BuildContext context, WidgetRef ref, TransactionHistoryEntry entry) {
    final network = ref.watch(networkProvider).network;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _typeIcon(entry.type, isReceive: entry.summary.startsWith('Received')),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryWithCheckmarks(entry),
                const SizedBox(height: 2),
                Text(
                  _relativeTime(entry.timestamp),
                  style: const TextStyle(
                      fontSize: 12, color: BrandColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _openExplorer(entry.signature, network),
            icon: const Icon(Icons.open_in_new,
                size: 16, color: BrandColors.textSecondary),
            tooltip: 'View on Explorer',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  /// Build summary text with inline checkmarks after verified token symbols.
  Widget _summaryWithCheckmarks(TransactionHistoryEntry entry) {
    final verifiedSymbols = _verifiedSymbolsInEntry(entry);
    if (verifiedSymbols.isEmpty) {
      return Text(
        entry.summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      );
    }

    // Insert checkmark icons after each verified token symbol in the text
    final spans = <InlineSpan>[];
    var remaining = entry.summary;
    const style = TextStyle(fontWeight: FontWeight.w500);
    const checkmark = WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsets.only(left: 2, right: 1),
        child: Icon(Icons.verified, size: 13, color: BrandColors.success),
      ),
    );

    while (remaining.isNotEmpty) {
      // Find the earliest verified symbol in the remaining text
      int earliestIdx = -1;
      String? earliestSymbol;
      for (final sym in verifiedSymbols) {
        final idx = remaining.indexOf(sym);
        if (idx != -1 && (earliestIdx == -1 || idx < earliestIdx)) {
          earliestIdx = idx;
          earliestSymbol = sym;
        }
      }

      if (earliestIdx == -1 || earliestSymbol == null) {
        spans.add(TextSpan(text: remaining, style: style));
        break;
      }

      // Text before the symbol
      if (earliestIdx > 0) {
        spans.add(TextSpan(text: remaining.substring(0, earliestIdx), style: style));
      }
      // The symbol itself + checkmark
      spans.add(TextSpan(text: earliestSymbol, style: style));
      spans.add(checkmark);
      remaining = remaining.substring(earliestIdx + earliestSymbol.length);
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Collect verified token symbols present in this entry.
  Set<String> _verifiedSymbolsInEntry(TransactionHistoryEntry entry) {
    final symbols = <String>{};
    // Check token transfers
    for (final t in entry.tokenTransfers) {
      final def = TokenRegistry.instance.lookup(t.mint);
      if (def != null) symbols.add(def.symbol);
    }
    // Check swap event tokens
    final swap = entry.swapEvent;
    if (swap != null) {
      for (final t in swap.tokenInputs) {
        if (t.isVerified) symbols.add(t.symbol);
      }
      for (final t in swap.tokenOutputs) {
        if (t.isVerified) symbols.add(t.symbol);
      }
    }
    // Native SOL is always verified
    if (entry.nativeTransfers.isNotEmpty ||
        entry.summary.contains(' SOL')) {
      symbols.add('SOL');
    }
    return symbols;
  }

  Widget _typeIcon(TransactionType type, {bool isReceive = false}) {
    final (IconData icon, Color color) = switch (type) {
      TransactionType.transfer => (
        isReceive ? Icons.arrow_downward : Icons.arrow_upward,
        Colors.blue,
      ),
      TransactionType.swap => (Icons.swap_horiz, Colors.orange),
      TransactionType.stake => (Icons.layers, Colors.purple),
      TransactionType.nftTransfer => (Icons.image, Colors.green),
      TransactionType.unknown => (Icons.help_outline, BrandColors.textSecondary),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  String _relativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final local = timestamp.toLocal();
    final diff = now.difference(local);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
    return '${local.month}/${local.day}/${local.year}';
  }

  Future<void> _openExplorer(String signature, SolanaNetwork network) async {
    final cluster = switch (network) {
      SolanaNetwork.devnet => '?cluster=devnet',
      SolanaNetwork.testnet => '?cluster=testnet',
      SolanaNetwork.mainnet => '',
    };
    final url = Uri.parse('https://orb.helius.dev/tx/$signature$cluster');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}
