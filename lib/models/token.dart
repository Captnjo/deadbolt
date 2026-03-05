enum SolanaNetwork {
  mainnet,
  devnet,
  testnet;

  factory SolanaNetwork.fromString(String s) {
    switch (s) {
      case 'mainnet':
        return SolanaNetwork.mainnet;
      case 'devnet':
        return SolanaNetwork.devnet;
      case 'testnet':
        return SolanaNetwork.testnet;
      default:
        return SolanaNetwork.mainnet;
    }
  }

  String toConfigString() => name;

  String get displayName {
    switch (this) {
      case SolanaNetwork.mainnet:
        return 'Mainnet';
      case SolanaNetwork.devnet:
        return 'Devnet';
      case SolanaNetwork.testnet:
        return 'Testnet';
    }
  }
}

class TokenDefinition {
  final String mint;
  final String name;
  final String symbol;
  final int decimals;

  const TokenDefinition({
    required this.mint,
    required this.name,
    required this.symbol,
    required this.decimals,
  });

  factory TokenDefinition.fromJson(Map<String, dynamic> json) {
    return TokenDefinition(
      mint: json['mint'] as String,
      name: json['name'] as String,
      symbol: json['symbol'] as String,
      decimals: json['decimals'] as int,
    );
  }
}

class TokenBalance {
  final TokenDefinition definition;
  final String rawAmount;
  final double uiAmount;
  final double? usdPrice;

  const TokenBalance({
    required this.definition,
    required this.rawAmount,
    required this.uiAmount,
    this.usdPrice,
  });

  double? get usdValue => usdPrice != null ? uiAmount * usdPrice! : null;
}
