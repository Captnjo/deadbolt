import 'send.dart' show TxStatus;

enum StakeStep { configure, review, confirming }

class LstPool {
  final String name;
  final String symbol;
  final String mint;

  const LstPool({
    required this.name,
    required this.symbol,
    required this.mint,
  });
}

/// Known LST pools supported by Sanctum.
class LstPools {
  LstPools._();

  static const jitoSOL = LstPool(
    name: 'Jito Staked SOL',
    symbol: 'jitoSOL',
    mint: 'J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn',
  );
  static const mSOL = LstPool(
    name: 'Marinade Staked SOL',
    symbol: 'mSOL',
    mint: 'mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So',
  );
  static const bSOL = LstPool(
    name: 'BlazeStake Staked SOL',
    symbol: 'bSOL',
    mint: 'bSo13r4TkiE4KumL71LsHTPpL2euBYLFx6h9HP3piy1',
  );
  static const bonkSOL = LstPool(
    name: 'Bonk Staked SOL',
    symbol: 'bonkSOL',
    mint: 'BonK1YhkXEGLZzwtcvRTip3gAL9nCeQD7ppZBLXhtTs',
  );

  static const all = [jitoSOL, mSOL, bSOL, bonkSOL];

  static final mintSet = {
    for (final p in all) p.mint,
  };
}

class SanctumQuote {
  final String inputAmount;
  final String outputAmount;
  final String lstMint;
  final Map<String, dynamic> raw;

  const SanctumQuote({
    required this.inputAmount,
    required this.outputAmount,
    required this.lstMint,
    required this.raw,
  });
}

class StakeState {
  final StakeStep step;
  final LstPool? selectedPool;
  final String amountText;
  final SanctumQuote? quote;
  final bool isQuoting;
  final String? quoteError;
  final TxStatus txStatus;
  final String? txSignature;
  final String? confirmationStatus;
  final String? errorMessage;
  final bool simulationSuccess;
  final String? simulationError;

  const StakeState({
    this.step = StakeStep.configure,
    this.selectedPool,
    this.amountText = '',
    this.quote,
    this.isQuoting = false,
    this.quoteError,
    this.txStatus = TxStatus.idle,
    this.txSignature,
    this.confirmationStatus,
    this.errorMessage,
    this.simulationSuccess = false,
    this.simulationError,
  });

  StakeState copyWith({
    StakeStep? step,
    LstPool? selectedPool,
    String? amountText,
    SanctumQuote? quote,
    bool? isQuoting,
    String? quoteError,
    TxStatus? txStatus,
    String? txSignature,
    String? confirmationStatus,
    String? errorMessage,
    bool? simulationSuccess,
    String? simulationError,
  }) {
    return StakeState(
      step: step ?? this.step,
      selectedPool: selectedPool ?? this.selectedPool,
      amountText: amountText ?? this.amountText,
      quote: quote ?? this.quote,
      isQuoting: isQuoting ?? this.isQuoting,
      quoteError: quoteError ?? this.quoteError,
      txStatus: txStatus ?? this.txStatus,
      txSignature: txSignature ?? this.txSignature,
      confirmationStatus: confirmationStatus ?? this.confirmationStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      simulationSuccess: simulationSuccess ?? this.simulationSuccess,
      simulationError: simulationError ?? this.simulationError,
    );
  }

  /// Parse amount text as lamports.
  BigInt? get lamports {
    if (amountText.isEmpty) return null;
    final parsed = double.tryParse(amountText);
    if (parsed == null || parsed <= 0) return null;
    return BigInt.from((parsed * 1e9).round());
  }
}
