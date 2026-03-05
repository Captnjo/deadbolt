import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token.dart';
import '../services/price_service.dart';
import '../services/solana_rpc.dart';
import '../services/token_registry.dart';
import 'network_provider.dart';
import 'wallet_provider.dart';

class PortfolioState {
  final int solBalance;
  final double solPrice;
  final List<TokenBalance> tokenBalances;

  const PortfolioState({
    this.solBalance = 0,
    this.solPrice = 0,
    this.tokenBalances = const [],
  });

  double get solUiAmount => solBalance / 1e9;
  double get solUsdValue => solUiAmount * solPrice;
  double get totalPortfolioUsd {
    var total = solUsdValue;
    for (final tb in tokenBalances) {
      total += tb.usdValue ?? 0;
    }
    return total;
  }
}

class BalanceNotifier extends AsyncNotifier<PortfolioState> {
  @override
  Future<PortfolioState> build() async {
    final address = ref.watch(activeWalletProvider);
    final net = ref.watch(networkProvider);
    if (address == null) return const PortfolioState();

    final rpc = SolanaRpcClient(net.rpcUrl);
    try {
      return await _fetch(rpc, address, net.network);
    } finally {
      rpc.dispose();
    }
  }

  Future<PortfolioState> _fetch(
    SolanaRpcClient rpc,
    String address,
    SolanaNetwork network,
  ) async {
    await TokenRegistry.instance.load();

    // Parallel fetch: SOL balance + token accounts + SOL price
    final futures = await Future.wait([
      rpc.getBalance(address),
      rpc.getTokenAccountsByOwner(address),
      _fetchSolPriceSafe(network),
    ]);

    final solBalance = futures[0] as int;
    final tokenAccounts = futures[1] as List<TokenAccountEntry>;
    final solPrice = futures[2] as double;

    // Build token balances with prices
    final balances = <TokenBalance>[];
    for (final account in tokenAccounts) {
      if (account.uiAmount == null || account.uiAmount == 0) continue;

      final def = TokenRegistry.instance.lookup(account.mint);
      if (def == null) continue;

      double? price;
      if (network == SolanaNetwork.mainnet) {
        price = await fetchTokenPrice(account.mint);
      }

      balances.add(TokenBalance(
        definition: def,
        rawAmount: account.amount,
        uiAmount: account.uiAmount!,
        usdPrice: price,
      ));
    }

    // Sort by USD value descending
    balances.sort((a, b) {
      final aVal = a.usdValue ?? 0;
      final bVal = b.usdValue ?? 0;
      return bVal.compareTo(aVal);
    });

    return PortfolioState(
      solBalance: solBalance,
      solPrice: solPrice,
      tokenBalances: balances,
    );
  }

  Future<double> _fetchSolPriceSafe(SolanaNetwork network) async {
    if (network != SolanaNetwork.mainnet) return 0;
    try {
      return await fetchSolPrice();
    } catch (_) {
      return 0;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final balanceProvider =
    AsyncNotifierProvider<BalanceNotifier, PortfolioState>(
  BalanceNotifier.new,
);
