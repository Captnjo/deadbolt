import 'dart:convert';

// --- Enums ---

enum IntentLifecycle { pending, signing, submitting, confirmed, failed, rejected }

enum SimulationPhase { idle, running, success, failed }

// --- Intent type hierarchy ---

sealed class AgentIntentType {
  const AgentIntentType();

  factory AgentIntentType.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'send_sol':
        return SendSolIntent(
          to: json['to'] as String,
          lamports: json['lamports'] as int,
        );
      case 'send_token':
        return SendTokenIntent(
          to: json['to'] as String,
          mint: json['mint'] as String,
          amount: json['amount'] as int,
        );
      case 'swap':
        return SwapIntent(
          inputMint: json['input_mint'] as String,
          outputMint: json['output_mint'] as String,
          amount: json['amount'] as int,
          slippageBps: json['slippage_bps'] as int?,
        );
      case 'stake':
        return StakeIntent(
          amountLamports: json['amount_lamports'] as int,
          lstMint: json['lst_mint'] as String,
        );
      case 'sign_message':
        return SignMessageIntent(
          message: json['message'] as String,
        );
      default:
        throw FormatException('Unknown intent type: $type');
    }
  }

  /// Human-readable summary for queue row display.
  String get summary;
}

class SendSolIntent extends AgentIntentType {
  final String to;
  final int lamports;
  const SendSolIntent({required this.to, required this.lamports});

  double get solAmount => lamports / 1e9;

  @override
  String get summary => 'Send ${solAmount.toStringAsFixed(4)} SOL';
}

class SendTokenIntent extends AgentIntentType {
  final String to;
  final String mint;
  final int amount;
  const SendTokenIntent({required this.to, required this.mint, required this.amount});

  @override
  String get summary => 'Send token';
}

class SwapIntent extends AgentIntentType {
  final String inputMint;
  final String outputMint;
  final int amount;
  final int? slippageBps;
  const SwapIntent({
    required this.inputMint,
    required this.outputMint,
    required this.amount,
    this.slippageBps,
  });

  @override
  String get summary => 'Swap';
}

class StakeIntent extends AgentIntentType {
  final int amountLamports;
  final String lstMint;
  const StakeIntent({required this.amountLamports, required this.lstMint});

  double get solAmount => amountLamports / 1e9;

  @override
  String get summary => 'Stake ${solAmount.toStringAsFixed(4)} SOL';
}

class SignMessageIntent extends AgentIntentType {
  final String message; // hex-encoded bytes
  const SignMessageIntent({required this.message});

  /// Attempt to decode as UTF-8; returns null if not valid UTF-8.
  String? get messageUtf8 {
    try {
      final bytes = _hexToBytes(message);
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  List<int> get messageBytes => _hexToBytes(message);

  @override
  String get summary => 'Sign message';
}

List<int> _hexToBytes(String hex) {
  final result = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return result;
}

// --- Swap quote preview (loaded asynchronously) ---

class SwapQuotePreview {
  final double expectedOutput;
  final String outputSymbol;
  final double exchangeRate;
  const SwapQuotePreview({
    required this.expectedOutput,
    required this.outputSymbol,
    required this.exchangeRate,
  });
}

// --- Pending intent model ---

class PendingIntent {
  final String id;
  final AgentIntentType type;
  final String agentTokenPrefix;
  final int createdAt;
  final SimulationPhase simulationPhase;
  final String? simulationError;
  final int? simulationUnitsConsumed;
  final IntentLifecycle lifecycle;
  final String? txSignature;
  final String? errorMessage;
  final SwapQuotePreview? swapQuote;

  const PendingIntent({
    required this.id,
    required this.type,
    required this.agentTokenPrefix,
    required this.createdAt,
    this.simulationPhase = SimulationPhase.idle,
    this.simulationError,
    this.simulationUnitsConsumed,
    this.lifecycle = IntentLifecycle.pending,
    this.txSignature,
    this.errorMessage,
    this.swapQuote,
  });

  factory PendingIntent.fromEvent(
    String id,
    String intentTypeJson,
    int createdAt,
    String apiTokenPrefix,
  ) {
    final json = jsonDecode(intentTypeJson) as Map<String, dynamic>;
    return PendingIntent(
      id: id,
      type: AgentIntentType.fromJson(json),
      agentTokenPrefix: apiTokenPrefix,
      createdAt: createdAt,
    );
  }

  PendingIntent copyWith({
    SimulationPhase? simulationPhase,
    String? simulationError,
    int? simulationUnitsConsumed,
    IntentLifecycle? lifecycle,
    String? txSignature,
    String? errorMessage,
    SwapQuotePreview? swapQuote,
  }) {
    return PendingIntent(
      id: id,
      type: type,
      agentTokenPrefix: agentTokenPrefix,
      createdAt: createdAt,
      simulationPhase: simulationPhase ?? this.simulationPhase,
      simulationError: simulationError ?? this.simulationError,
      simulationUnitsConsumed: simulationUnitsConsumed ?? this.simulationUnitsConsumed,
      lifecycle: lifecycle ?? this.lifecycle,
      txSignature: txSignature ?? this.txSignature,
      errorMessage: errorMessage ?? this.errorMessage,
      swapQuote: swapQuote ?? this.swapQuote,
    );
  }

  /// Time ago string for queue display.
  String get timeAgo {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - createdAt;
    if (diff < 60) return 'just now';
    if (diff < 3600) return '${diff ~/ 60} min ago';
    if (diff < 86400) return '${diff ~/ 3600} hr ago';
    return '${diff ~/ 86400} day ago';
  }

  /// Whether this is a stake intent (unsupported in v1).
  bool get isStake => type is StakeIntent;

  /// Whether this is a sign_message intent (special UI).
  bool get isSignMessage => type is SignMessageIntent;
}
