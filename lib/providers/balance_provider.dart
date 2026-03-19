import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/currency.dart';
import '../models/token.dart';
import '../services/price_service.dart';
import '../services/solana_rpc.dart';
import '../services/token_registry.dart';
import 'api_keys_provider.dart';
import 'network_provider.dart';
import 'wallet_provider.dart';

class PortfolioState {
  final int solBalance;
  final double solPrice;
  final List<TokenBalance> tokenBalances;
  final double exchangeRate;

  const PortfolioState({
    this.solBalance = 0,
    this.solPrice = 0,
    this.tokenBalances = const [],
    this.exchangeRate = 1.0,
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

  double get totalPortfolioDisplay => totalPortfolioUsd * exchangeRate;
  double get solDisplayValue => solUsdValue * exchangeRate;
}

class BalanceNotifier extends AsyncNotifier<PortfolioState> {
  @override
  Future<PortfolioState> build() async {
    final address = ref.watch(activeWalletProvider);
    final net = ref.watch(networkProvider);
    final currency = ref.watch(
        apiKeysProvider.select((s) => s.displayCurrency));
    if (address == null) return const PortfolioState();

    final rpc = SolanaRpcClient(net.rpcUrl);
    try {
      return await _fetch(rpc, address, net.network, currency);
    } finally {
      rpc.dispose();
    }
  }

  Future<PortfolioState> _fetch(
    SolanaRpcClient rpc,
    String address,
    SolanaNetwork network,
    DisplayCurrency currency,
  ) async {
    await TokenRegistry.instance.load();

    // Parallel fetch: SOL balance + token accounts + SOL price
    final futures = await Future.wait([
      rpc.getBalance(address),
      rpc.getTokenAccountsByOwner(address),
      _fetchSolPriceSafe(network, currency),
    ]);

    final solBalance = futures[0] as int;
    final tokenAccounts = futures[1] as List<TokenAccountEntry>;
    final priceResult = futures[2] as ({double usd, double display});
    final solPrice = priceResult.usd;

    // Build token balances with prices
    final balances = <TokenBalance>[];
    for (final account in tokenAccounts) {
      if (account.uiAmount == null || account.uiAmount == 0) continue;

      final def = TokenRegistry.instance.lookup(account.mint) ??
          TokenDefinition(
            mint: account.mint,
            name: account.mint.length >= 8
                ? '${account.mint.substring(0, 4)}...${account.mint.substring(account.mint.length - 4)}'
                : account.mint,
            symbol: 'Unknown',
            decimals: account.decimals,
          );

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

    // Compute exchange rate from USD to display currency
    final double exchangeRate;
    if (currency == DisplayCurrency.sol) {
      exchangeRate = solPrice > 0 ? 1.0 / solPrice : 1.0;
    } else if (currency == DisplayCurrency.usd) {
      exchangeRate = 1.0;
    } else {
      exchangeRate = priceResult.usd > 0
          ? priceResult.display / priceResult.usd
          : 1.0;
    }

    return PortfolioState(
      solBalance: solBalance,
      solPrice: solPrice,
      tokenBalances: balances,
      exchangeRate: exchangeRate,
    );
  }

  Future<({double usd, double display})> _fetchSolPriceSafe(
    SolanaNetwork network,
    DisplayCurrency currency,
  ) async {
    if (network != SolanaNetwork.mainnet) {
      return (usd: 0.0, display: 0.0);
    }
    try {
      return await fetchSolPrice(displayCode: currency.code);
    } catch (_) {
      return (usd: 0.0, display: 0.0);
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
