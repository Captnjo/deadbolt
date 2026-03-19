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

class DFlowQuote {
  final String inputMint;
  final String outputMint;
  final String inAmount;
  final String outAmount;
  final double priceImpactPct;
  final Map<String, dynamic> raw;

  const DFlowQuote({
    required this.inputMint,
    required this.outputMint,
    required this.inAmount,
    required this.outAmount,
    required this.priceImpactPct,
    required this.raw,
  });

  factory DFlowQuote.fromJson(Map<String, dynamic> json) {
    return DFlowQuote(
      inputMint: json['inputMint'] as String? ?? '',
      outputMint: json['outputMint'] as String? ?? '',
      inAmount: json['inAmount']?.toString() ?? '0',
      outAmount: json['outAmount']?.toString() ?? '0',
      priceImpactPct:
          double.tryParse(json['priceImpactPct']?.toString() ?? '0') ?? 0,
      raw: json,
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
  final DFlowQuote? dflowQuote;
  final bool isQuoting;
  final String? quoteError;
  final TxStatus txStatus;
  final String? txSignature;
  final String? confirmationStatus;
  final String? errorMessage;
  final bool simulationSuccess;
  final String? simulationError;
  final String? guardrailViolation;
  final bool guardrailBypassed;

  const SwapState({
    this.step = SwapStep.configure,
    this.aggregator = SwapAggregator.dflow,
    this.inputToken,
    this.outputToken,
    this.inputAmount = '',
    this.jupiterQuote,
    this.dflowQuote,
    this.isQuoting = false,
    this.quoteError,
    this.txStatus = TxStatus.idle,
    this.txSignature,
    this.confirmationStatus,
    this.errorMessage,
    this.simulationSuccess = false,
    this.simulationError,
    this.guardrailViolation,
    this.guardrailBypassed = false,
  });

  SwapState copyWith({
    SwapStep? step,
    SwapAggregator? aggregator,
    TokenBalance? inputToken,
    TokenBalance? outputToken,
    String? inputAmount,
    JupiterQuote? jupiterQuote,
    DFlowQuote? dflowQuote,
    bool? isQuoting,
    String? quoteError,
    TxStatus? txStatus,
    String? txSignature,
    String? confirmationStatus,
    String? errorMessage,
    bool? simulationSuccess,
    String? simulationError,
    String? guardrailViolation,
    bool? guardrailBypassed,
  }) {
    return SwapState(
      step: step ?? this.step,
      aggregator: aggregator ?? this.aggregator,
      inputToken: inputToken ?? this.inputToken,
      outputToken: outputToken ?? this.outputToken,
      inputAmount: inputAmount ?? this.inputAmount,
      jupiterQuote: jupiterQuote ?? this.jupiterQuote,
      dflowQuote: dflowQuote ?? this.dflowQuote,
      isQuoting: isQuoting ?? this.isQuoting,
      quoteError: quoteError ?? this.quoteError,
      txStatus: txStatus ?? this.txStatus,
      txSignature: txSignature ?? this.txSignature,
      confirmationStatus: confirmationStatus ?? this.confirmationStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      simulationSuccess: simulationSuccess ?? this.simulationSuccess,
      simulationError: simulationError ?? this.simulationError,
      guardrailViolation: guardrailViolation ?? this.guardrailViolation,
      guardrailBypassed: guardrailBypassed ?? this.guardrailBypassed,
    );
  }

  /// Get the output amount string from whichever aggregator is active.
  String? get outputAmount {
    if (aggregator == SwapAggregator.jupiter) {
      return jupiterQuote?.outAmount;
    }
    return dflowQuote?.outAmount;
  }

  /// Get the price impact from whichever aggregator is active.
  double? get priceImpact {
    if (aggregator == SwapAggregator.jupiter) {
      return jupiterQuote?.priceImpactPct;
    }
    return dflowQuote?.priceImpactPct;
  }

  /// The raw quote response for building a swap transaction (DFlow).
  Map<String, dynamic>? get dflowQuoteRaw => dflowQuote?.raw;
}
