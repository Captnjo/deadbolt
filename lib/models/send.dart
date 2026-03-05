import 'token.dart';

/// What asset to send: native SOL or an SPL token.
sealed class SendAsset {
  const SendAsset();
}

class SendSol extends SendAsset {
  final int lamportsBalance;
  const SendSol({required this.lamportsBalance});
  double get solBalance => lamportsBalance / 1e9;
}

class SendToken extends SendAsset {
  final TokenBalance tokenBalance;
  const SendToken({required this.tokenBalance});
}

enum SendStep { recipient, asset, amount, review, confirming }

enum TxStatus { idle, simulating, signing, submitting, polling, confirmed, failed }

class SendState {
  final SendStep step;
  final String recipient;
  final SendAsset? asset;
  final String amountText;
  final TxStatus txStatus;
  final String? txSignature;
  final String? confirmationStatus;
  final String? errorMessage;
  final bool simulationSuccess;
  final String? simulationError;
  final int? simulationUnitsConsumed;

  const SendState({
    this.step = SendStep.recipient,
    this.recipient = '',
    this.asset,
    this.amountText = '',
    this.txStatus = TxStatus.idle,
    this.txSignature,
    this.confirmationStatus,
    this.errorMessage,
    this.simulationSuccess = false,
    this.simulationError,
    this.simulationUnitsConsumed,
  });

  SendState copyWith({
    SendStep? step,
    String? recipient,
    SendAsset? asset,
    String? amountText,
    TxStatus? txStatus,
    String? txSignature,
    String? confirmationStatus,
    String? errorMessage,
    bool? simulationSuccess,
    String? simulationError,
    int? simulationUnitsConsumed,
  }) {
    return SendState(
      step: step ?? this.step,
      recipient: recipient ?? this.recipient,
      asset: asset ?? this.asset,
      amountText: amountText ?? this.amountText,
      txStatus: txStatus ?? this.txStatus,
      txSignature: txSignature ?? this.txSignature,
      confirmationStatus: confirmationStatus ?? this.confirmationStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      simulationSuccess: simulationSuccess ?? this.simulationSuccess,
      simulationError: simulationError ?? this.simulationError,
      simulationUnitsConsumed:
          simulationUnitsConsumed ?? this.simulationUnitsConsumed,
    );
  }

  /// The raw amount in smallest units (lamports or token base units).
  BigInt? get rawAmount {
    if (amountText.isEmpty) return null;
    final parsed = double.tryParse(amountText);
    if (parsed == null || parsed <= 0) return null;

    final asset = this.asset;
    if (asset is SendSol) {
      return BigInt.from((parsed * 1e9).round());
    } else if (asset is SendToken) {
      final decimals = asset.tokenBalance.definition.decimals;
      final factor = BigInt.from(10).pow(decimals);
      // Use string manipulation for precision
      return BigInt.from((parsed * factor.toDouble()).round());
    }
    return null;
  }

  /// Whether the entered amount exceeds available balance.
  bool get amountExceedsBalance {
    final raw = rawAmount;
    if (raw == null) return false;
    final asset = this.asset;
    if (asset is SendSol) {
      return raw.toInt() > asset.lamportsBalance;
    } else if (asset is SendToken) {
      final available = BigInt.parse(asset.tokenBalance.rawAmount);
      return raw > available;
    }
    return false;
  }
}
