import 'send.dart' show TxStatus;
import 'token.dart';

enum SwapStep { configure, review, confirming }

enum SwapAggregator { jupiter, dflow }

class JupiterQuote {
  final String inputMint;
  final String outputMint;
  final String inAmount;
  final String outAmount;
  final double priceImpactPct;
  final List<dynamic> routePlan;
  final Map<String, dynamic> raw;

  const JupiterQuote({
    required this.inputMint,
    required this.outputMint,
    required this.inAmount,
    required this.outAmount,
    required this.priceImpactPct,
    required this.routePlan,
    required this.raw,
  });

  factory JupiterQuote.fromJson(Map<String, dynamic> json) {
    return JupiterQuote(
      inputMint: json['inputMint'] as String,
      outputMint: json['outputMint'] as String,
      inAmount: json['inAmount'] as String,
      outAmount: json['outAmount'] as String,
      priceImpactPct: double.tryParse(json['priceImpactPct']?.toString() ?? '0') ?? 0,
      routePlan: json['routePlan'] as List<dynamic>? ?? [],
      raw: json,
    );
  }
}

class DFlowOrder {
  final String transaction;
  final String expectedOutput;
  final double priceImpact;

  const DFlowOrder({
    required this.transaction,
    required this.expectedOutput,
    required this.priceImpact,
  });

  factory DFlowOrder.fromJson(Map<String, dynamic> json) {
    return DFlowOrder(
      transaction: json['transaction'] as String,
      expectedOutput: json['expectedOutput']?.toString() ?? '0',
      priceImpact: double.tryParse(json['priceImpact']?.toString() ?? '0') ?? 0,
    );
  }
}

class SwapState {
  final SwapStep step;
  final SwapAggregator aggregator;
  final TokenBalance? inputToken;
  final TokenBalance? outputToken;
  final String inputAmount;
  final JupiterQuote? jupiterQuote;
  final DFlowOrder? dflowOrder;
  final bool isQuoting;
  final String? quoteError;
  final TxStatus txStatus;
  final String? txSignature;
  final String? confirmationStatus;
  final String? errorMessage;
  final bool simulationSuccess;
  final String? simulationError;

  const SwapState({
    this.step = SwapStep.configure,
    this.aggregator = SwapAggregator.jupiter,
    this.inputToken,
    this.outputToken,
    this.inputAmount = '',
    this.jupiterQuote,
    this.dflowOrder,
    this.isQuoting = false,
    this.quoteError,
    this.txStatus = TxStatus.idle,
    this.txSignature,
    this.confirmationStatus,
    this.errorMessage,
    this.simulationSuccess = false,
    this.simulationError,
  });

  SwapState copyWith({
    SwapStep? step,
    SwapAggregator? aggregator,
    TokenBalance? inputToken,
    TokenBalance? outputToken,
    String? inputAmount,
    JupiterQuote? jupiterQuote,
    DFlowOrder? dflowOrder,
    bool? isQuoting,
    String? quoteError,
    TxStatus? txStatus,
    String? txSignature,
    String? confirmationStatus,
    String? errorMessage,
    bool? simulationSuccess,
    String? simulationError,
  }) {
    return SwapState(
      step: step ?? this.step,
      aggregator: aggregator ?? this.aggregator,
      inputToken: inputToken ?? this.inputToken,
      outputToken: outputToken ?? this.outputToken,
      inputAmount: inputAmount ?? this.inputAmount,
      jupiterQuote: jupiterQuote ?? this.jupiterQuote,
      dflowOrder: dflowOrder ?? this.dflowOrder,
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

  /// Get the output amount string from whichever aggregator is active.
  String? get outputAmount {
    if (aggregator == SwapAggregator.jupiter) {
      return jupiterQuote?.outAmount;
    }
    return dflowOrder?.expectedOutput;
  }

  /// Get the price impact from whichever aggregator is active.
  double? get priceImpact {
    if (aggregator == SwapAggregator.jupiter) {
      return jupiterQuote?.priceImpactPct;
    }
    return dflowOrder?.priceImpact;
  }

  /// The base64 transaction to sign (DFlow only — Jupiter comes from swap endpoint).
  String? get prebuiltTransaction => dflowOrder?.transaction;
}
