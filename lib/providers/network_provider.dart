import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/token.dart';
import '../src/rust/api/wallet.dart' as bridge;

class NetworkState {
  final SolanaNetwork network;
  final String heliusApiKey;

  const NetworkState({
    this.network = SolanaNetwork.mainnet,
    this.heliusApiKey = '',
  });

  String get rpcUrl {
    if (heliusApiKey.isNotEmpty) {
      switch (network) {
        case SolanaNetwork.mainnet:
          return 'https://mainnet.helius-rpc.com/?api-key=$heliusApiKey';
        case SolanaNetwork.devnet:
          return 'https://devnet.helius-rpc.com/?api-key=$heliusApiKey';
        case SolanaNetwork.testnet:
          return 'https://api.testnet.solana.com'; // Helius doesn't support testnet
      }
    }
    switch (network) {
      case SolanaNetwork.mainnet:
        return 'https://api.mainnet-beta.solana.com';
      case SolanaNetwork.devnet:
        return 'https://api.devnet.solana.com';
      case SolanaNetwork.testnet:
        return 'https://api.testnet.solana.com';
    }
  }

  NetworkState copyWith({SolanaNetwork? network, String? heliusApiKey}) {
    return NetworkState(
      network: network ?? this.network,
      heliusApiKey: heliusApiKey ?? this.heliusApiKey,
    );
  }
}

class NetworkNotifier extends Notifier<NetworkState> {
  @override
  NetworkState build() {
    final networkStr = bridge.getNetwork();
    final apiKey = bridge.getHeliusApiKey();
    return NetworkState(
      network: SolanaNetwork.fromString(networkStr),
      heliusApiKey: apiKey,
    );
  }

  Future<void> setNetwork(SolanaNetwork n) async {
    await bridge.setNetwork(network: n.toConfigString());
    state = state.copyWith(network: n);
  }

  Future<void> setHeliusApiKey(String key) async {
    await bridge.setHeliusApiKey(key: key);
    state = state.copyWith(heliusApiKey: key);
  }
}

final networkProvider = NotifierProvider<NetworkNotifier, NetworkState>(
  NetworkNotifier.new,
);
