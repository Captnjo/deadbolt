import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token.dart';
import '../models/transaction_history.dart';
import '../services/helius_service.dart';
import '../services/solana_rpc.dart';
import '../services/token_registry.dart';
import 'network_provider.dart';
import 'wallet_provider.dart';

class HistoryState {
  final List<TransactionHistoryEntry> entries;
  final TransactionFilter filter;
  final bool hasMore;
  final bool isLoadingMore;

  const HistoryState({
    this.entries = const [],
    this.filter = TransactionFilter.all,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  List<TransactionHistoryEntry> get filteredEntries {
    if (filter == TransactionFilter.all) return entries;
    return entries.where((e) {
      switch (filter) {
        case TransactionFilter.all:
          return true;
        case TransactionFilter.transfers:
          return e.type == TransactionType.transfer;
        case TransactionFilter.swaps:
          return e.type == TransactionType.swap;
        case TransactionFilter.staking:
          return e.type == TransactionType.stake;
        case TransactionFilter.nfts:
          return e.type == TransactionType.nftTransfer;
      }
    }).toList();
  }

  HistoryState copyWith({
    List<TransactionHistoryEntry>? entries,
    TransactionFilter? filter,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return HistoryState(
      entries: entries ?? this.entries,
      filter: filter ?? this.filter,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class HistoryNotifier extends AsyncNotifier<HistoryState> {
  static const _pageSize = 20;

  @override
  Future<HistoryState> build() async {
    final address = ref.watch(activeWalletProvider);
    ref.watch(networkProvider);
    if (address == null) return const HistoryState();
    return _fetchPage(address, null);
  }

  Future<HistoryState> _fetchPage(String address, String? before) async {
    final net = ref.read(networkProvider);
    final entries = await _fetchEntries(address, net, before);

    return HistoryState(
      entries: entries,
      hasMore: entries.length >= _pageSize,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    if (current.entries.isEmpty) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final address = ref.read(activeWalletProvider);
    if (address == null) return;

    final lastSig = current.entries.last.signature;
    final net = ref.read(networkProvider);

    try {
      final newEntries = await _fetchEntries(address, net, lastSig);

      state = AsyncData(current.copyWith(
        entries: [...current.entries, ...newEntries],
        hasMore: newEntries.length >= _pageSize,
        isLoadingMore: false,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      rethrow;
    }
  }

  /// Step 1: Get signatures from RPC.
  /// Step 2: If Helius key available, enrich via Enhanced Transactions API.
  /// Falls back to basic RPC-only entries on Helius failure.
  Future<List<TransactionHistoryEntry>> _fetchEntries(
    String address,
    NetworkState net,
    String? before,
  ) async {
    await TokenRegistry.instance.load();
    final rpc = SolanaRpcClient(net.rpcUrl);
    try {
      final sigInfos = await rpc.getSignaturesForAddress(
        address,
        limit: _pageSize,
        before: before,
      );
      debugPrint('[History] RPC returned ${sigInfos.length} signatures');

      if (sigInfos.isEmpty) return [];

      // Try Helius enrichment (mainnet only — Helius doesn't index devnet/testnet)
      if (net.heliusApiKey.isNotEmpty &&
          net.network == SolanaNetwork.mainnet) {
        final signatures = sigInfos.map((s) => s.signature).toList();
        final helius = HeliusService(net.heliusApiKey);
        try {
          final enhanced =
              await helius.getEnhancedTransactions(signatures);
          debugPrint('[History] Helius enriched ${enhanced.length} txs, '
              'first type=${enhanced.isNotEmpty ? enhanced.first.type : "n/a"}');
          if (enhanced.isNotEmpty) {
            return enhanced
                .map((tx) => TransactionHistoryEntry.fromHelius(tx))
                .toList();
          }
        } catch (e) {
          debugPrint('[History] Helius enrichment failed: $e');
        } finally {
          helius.dispose();
        }
      }

      // Fallback: basic entries from RPC signatures
      return sigInfos
          .map((s) => TransactionHistoryEntry.fromSignature(
                signature: s.signature,
                blockTime: s.blockTime,
                hasError: !s.success,
              ))
          .toList();
    } finally {
      rpc.dispose();
    }
  }

  void setFilter(TransactionFilter filter) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(filter: filter));
  }
}

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, HistoryState>(
  HistoryNotifier.new,
);
