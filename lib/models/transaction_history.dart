import '../services/token_registry.dart';

// -- Transaction type classification --

enum TransactionType {
  transfer,
  swap,
  stake,
  nftTransfer,
  unknown;

  factory TransactionType.fromHelius(String heliusType) {
    switch (heliusType.toUpperCase()) {
      case 'TRANSFER':
        return TransactionType.transfer;
      case 'SWAP':
        return TransactionType.swap;
      case 'STAKE':
      case 'UNSTAKE':
        return TransactionType.stake;
      case 'NFT_TRANSFER':
      case 'NFT_SALE':
      case 'NFT_LISTING':
      case 'NFT_MINT':
      case 'NFT_BID':
      case 'NFT_CANCEL_LISTING':
      case 'NFT_BID_CANCELLED':
      case 'COMPRESSED_NFT_TRANSFER':
      case 'COMPRESSED_NFT_MINT':
        return TransactionType.nftTransfer;
      default:
        return TransactionType.unknown;
    }
  }

  String get label {
    switch (this) {
      case TransactionType.transfer:
        return 'Transfer';
      case TransactionType.swap:
        return 'Swap';
      case TransactionType.stake:
        return 'Stake';
      case TransactionType.nftTransfer:
        return 'NFT';
      case TransactionType.unknown:
        return 'Unknown';
    }
  }
}

// -- Filter enum --

enum TransactionFilter {
  all('All'),
  transfers('Transfers'),
  swaps('Swaps'),
  staking('Staking'),
  nfts('NFTs');

  final String label;
  const TransactionFilter(this.label);
}

// -- Helius API response types --

class HeliusNativeTransfer {
  final String fromUserAccount;
  final String toUserAccount;
  final int amount;

  const HeliusNativeTransfer({
    required this.fromUserAccount,
    required this.toUserAccount,
    required this.amount,
  });

  factory HeliusNativeTransfer.fromJson(Map<String, dynamic> json) {
    return HeliusNativeTransfer(
      fromUserAccount: json['fromUserAccount'] as String? ?? '',
      toUserAccount: json['toUserAccount'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }
}

class HeliusTokenTransfer {
  final String? fromUserAccount;
  final String? toUserAccount;
  final String? fromTokenAccount;
  final String? toTokenAccount;
  final double tokenAmount;
  final String mint;

  const HeliusTokenTransfer({
    this.fromUserAccount,
    this.toUserAccount,
    this.fromTokenAccount,
    this.toTokenAccount,
    required this.tokenAmount,
    required this.mint,
  });

  factory HeliusTokenTransfer.fromJson(Map<String, dynamic> json) {
    return HeliusTokenTransfer(
      fromUserAccount: json['fromUserAccount'] as String?,
      toUserAccount: json['toUserAccount'] as String?,
      fromTokenAccount: json['fromTokenAccount'] as String?,
      toTokenAccount: json['toTokenAccount'] as String?,
      tokenAmount: (json['tokenAmount'] as num?)?.toDouble() ?? 0,
      mint: json['mint'] as String? ?? '',
    );
  }
}

/// Token amount with mint from a swap event.
class SwapTokenAmount {
  final String mint;
  final double amount;

  const SwapTokenAmount({required this.mint, required this.amount});

  factory SwapTokenAmount.fromJson(Map<String, dynamic> json) {
    double amount = 0;
    if (json['rawTokenAmount'] is Map<String, dynamic>) {
      amount = _parseRawAmount(json['rawTokenAmount'] as Map<String, dynamic>);
    } else {
      final ta = json['tokenAmount'];
      if (ta is num) {
        amount = ta.toDouble();
      } else if (ta is String) {
        amount = double.tryParse(ta) ?? 0;
      }
    }
    return SwapTokenAmount(
      mint: json['mint'] as String? ?? json['userAccount'] as String? ?? '',
      amount: amount,
    );
  }

  String get symbol {
    final def = TokenRegistry.instance.lookup(mint);
    return def?.symbol ?? _shortMint(mint);
  }

  bool get isVerified => TokenRegistry.instance.lookup(mint) != null;

  static double _parseRawAmount(Map<String, dynamic> raw) {
    final amount = double.tryParse(raw['tokenAmount']?.toString() ?? '0') ?? 0;
    final decimals = (raw['decimals'] as num?)?.toInt() ?? 0;
    if (decimals == 0) return amount;
    return amount / _pow10(decimals);
  }

  static double _pow10(int n) {
    double result = 1;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }

  static String _shortMint(String mint) {
    if (mint.length <= 8) return mint;
    return '${mint.substring(0, 4)}...${mint.substring(mint.length - 4)}';
  }
}

/// Parsed swap event from Helius `events.swap`.
class HeliusSwapEvent {
  final List<SwapTokenAmount> tokenInputs;
  final List<SwapTokenAmount> tokenOutputs;
  final int? nativeInputAmount;
  final int? nativeOutputAmount;
  final List<SwapInnerSwap> innerSwaps;

  const HeliusSwapEvent({
    this.tokenInputs = const [],
    this.tokenOutputs = const [],
    this.nativeInputAmount,
    this.nativeOutputAmount,
    this.innerSwaps = const [],
  });

  factory HeliusSwapEvent.fromJson(Map<String, dynamic> json) {
    int? parseNativeAmount(Map<String, dynamic>? native) {
      if (native == null) return null;
      final amount = native['amount'];
      if (amount is int) return amount;
      if (amount is num) return amount.toInt();
      if (amount is String) return int.tryParse(amount);
      return null;
    }

    return HeliusSwapEvent(
      tokenInputs: (json['tokenInputs'] as List<dynamic>?)
              ?.map((e) => SwapTokenAmount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tokenOutputs: (json['tokenOutputs'] as List<dynamic>?)
              ?.map((e) => SwapTokenAmount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nativeInputAmount: parseNativeAmount(json['nativeInput'] as Map<String, dynamic>?),
      nativeOutputAmount: parseNativeAmount(json['nativeOutput'] as Map<String, dynamic>?),
      innerSwaps: (json['innerSwaps'] as List<dynamic>?)
              ?.map((e) => SwapInnerSwap.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// An inner swap hop (e.g., USDC → SOL → JitoSOL).
class SwapInnerSwap {
  final List<SwapTokenAmount> tokenInputs;
  final List<SwapTokenAmount> tokenOutputs;
  final String programId;

  const SwapInnerSwap({
    this.tokenInputs = const [],
    this.tokenOutputs = const [],
    this.programId = '',
  });

  factory SwapInnerSwap.fromJson(Map<String, dynamic> json) {
    return SwapInnerSwap(
      tokenInputs: (json['tokenInputs'] as List<dynamic>?)
              ?.map((e) => SwapTokenAmount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tokenOutputs: (json['tokenOutputs'] as List<dynamic>?)
              ?.map((e) => SwapTokenAmount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      programId: json['programId'] as String? ?? '',
    );
  }
}

class HeliusEnhancedTransaction {
  final String description;
  final String type;
  final String source;
  final int fee;
  final String feePayer;
  final String signature;
  final int slot;
  final int timestamp;
  final List<HeliusNativeTransfer> nativeTransfers;
  final List<HeliusTokenTransfer> tokenTransfers;
  final HeliusSwapEvent? swapEvent;

  const HeliusEnhancedTransaction({
    required this.description,
    required this.type,
    required this.source,
    required this.fee,
    required this.feePayer,
    required this.signature,
    required this.slot,
    required this.timestamp,
    required this.nativeTransfers,
    required this.tokenTransfers,
    this.swapEvent,
  });

  factory HeliusEnhancedTransaction.fromJson(Map<String, dynamic> json) {
    final events = json['events'] as Map<String, dynamic>?;
    HeliusSwapEvent? swapEvent;
    if (events != null && events['swap'] != null) {
      swapEvent = HeliusSwapEvent.fromJson(events['swap'] as Map<String, dynamic>);
    }

    return HeliusEnhancedTransaction(
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'UNKNOWN',
      source: json['source'] as String? ?? '',
      fee: (json['fee'] as num?)?.toInt() ?? 0,
      feePayer: json['feePayer'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
      slot: (json['slot'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      nativeTransfers: (json['nativeTransfers'] as List<dynamic>?)
              ?.map((e) =>
                  HeliusNativeTransfer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tokenTransfers: (json['tokenTransfers'] as List<dynamic>?)
              ?.map((e) =>
                  HeliusTokenTransfer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      swapEvent: swapEvent,
    );
  }
}

// -- Display-ready history entry --

class TransactionHistoryEntry {
  final String signature;
  final TransactionType type;
  /// Human-readable action summary, e.g. "Swap 2.30 USDC for 0.025 SOL"
  final String summary;
  final DateTime timestamp;
  final int fee;
  final String source;
  final List<HeliusNativeTransfer> nativeTransfers;
  final List<HeliusTokenTransfer> tokenTransfers;
  final HeliusSwapEvent? swapEvent;

  const TransactionHistoryEntry({
    required this.signature,
    required this.type,
    required this.summary,
    required this.timestamp,
    this.fee = 0,
    this.source = '',
    this.nativeTransfers = const [],
    this.tokenTransfers = const [],
    this.swapEvent,
  });

  factory TransactionHistoryEntry.fromHelius(HeliusEnhancedTransaction tx) {
    final txType = TransactionType.fromHelius(tx.type);
    final nativeTransfers = tx.nativeTransfers;
    final tokenTransfers = tx.tokenTransfers;

    return TransactionHistoryEntry(
      signature: tx.signature,
      type: txType,
      summary: _buildSummary(
        txType, tx.source, tx.feePayer,
        nativeTransfers, tokenTransfers, tx.swapEvent,
      ),
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(tx.timestamp * 1000, isUtc: true),
      fee: tx.fee,
      source: tx.source,
      nativeTransfers: nativeTransfers,
      tokenTransfers: tokenTransfers,
      swapEvent: tx.swapEvent,
    );
  }

  /// Fallback entry from RPC signature info only (no Helius key).
  factory TransactionHistoryEntry.fromSignature({
    required String signature,
    required int? blockTime,
    required bool hasError,
  }) {
    return TransactionHistoryEntry(
      signature: signature,
      type: TransactionType.unknown,
      summary: hasError ? 'Failed transaction' : 'Transaction',
      timestamp: blockTime != null
          ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000, isUtc: true)
          : DateTime.now(),
    );
  }

  // -- Summary builders --

  static String _buildSummary(
    TransactionType type,
    String source,
    String feePayer,
    List<HeliusNativeTransfer> nativeTransfers,
    List<HeliusTokenTransfer> tokenTransfers,
    HeliusSwapEvent? swapEvent,
  ) {
    switch (type) {
      case TransactionType.swap:
        return _swapSummary(source, swapEvent, tokenTransfers);
      case TransactionType.transfer:
        return _transferSummary(feePayer, nativeTransfers, tokenTransfers);
      case TransactionType.stake:
        return _stakeSummary(nativeTransfers);
      case TransactionType.nftTransfer:
        return 'NFT transfer';
      case TransactionType.unknown:
        return 'Transaction';
    }
  }

  static String _swapSummary(
    String source,
    HeliusSwapEvent? swap,
    List<HeliusTokenTransfer> tokenTransfers,
  ) {
    String? inputLabel;
    String? outputLabel;

    if (swap != null) {
      // Sum all token inputs by mint to get the total input amount
      if (swap.tokenInputs.isNotEmpty) {
        final totals = _sumByMint(swap.tokenInputs);
        final entry = totals.entries.first;
        inputLabel = '${_formatAmount(entry.value)} ${_symbolForMint(entry.key)}';
      } else if (swap.nativeInputAmount != null) {
        inputLabel = '${_formatAmount(swap.nativeInputAmount! / 1e9)} SOL';
      }
      // Sum all token outputs by mint to get the total output amount
      if (swap.tokenOutputs.isNotEmpty) {
        final totals = _sumByMint(swap.tokenOutputs);
        final entry = totals.entries.first;
        outputLabel = '${_formatAmount(entry.value)} ${_symbolForMint(entry.key)}';
      } else if (swap.nativeOutputAmount != null) {
        outputLabel = '${_formatAmount(swap.nativeOutputAmount! / 1e9)} SOL';
      }
    }

    // Fallback to token transfers if swap event missing
    if (inputLabel == null && tokenTransfers.length >= 2) {
      final first = tokenTransfers.first;
      final last = tokenTransfers.last;
      inputLabel = '${_formatAmount(first.tokenAmount)} ${_symbolForMint(first.mint)}';
      outputLabel = '${_formatAmount(last.tokenAmount)} ${_symbolForMint(last.mint)}';
    }

    if (inputLabel != null && outputLabel != null) {
      return 'Swap $inputLabel for $outputLabel';
    }
    return 'Swap';
  }

  /// Sum amounts grouped by mint across a list of swap token amounts.
  static Map<String, double> _sumByMint(List<SwapTokenAmount> tokens) {
    final totals = <String, double>{};
    for (final t in tokens) {
      totals[t.mint] = (totals[t.mint] ?? 0) + t.amount;
    }
    return totals;
  }

  static String _transferSummary(
    String feePayer,
    List<HeliusNativeTransfer> nativeTransfers,
    List<HeliusTokenTransfer> tokenTransfers,
  ) {
    // Token transfer
    if (tokenTransfers.isNotEmpty) {
      final t = tokenTransfers.first;
      final amt = '${_formatAmount(t.tokenAmount)} ${_symbolForMint(t.mint)}';
      final isSender = t.fromUserAccount == feePayer;
      if (isSender && t.toUserAccount != null) {
        return 'Sent $amt to ${_shortAddr(t.toUserAccount!)}';
      } else if (t.fromUserAccount != null) {
        return 'Received $amt from ${_shortAddr(t.fromUserAccount!)}';
      }
      return 'Transfer $amt';
    }

    // Native SOL transfer
    final nonDust = nativeTransfers.where((t) => t.amount > 5000);
    if (nonDust.isNotEmpty) {
      final t = nonDust.first;
      final amt = '${_formatAmount(t.amount / 1e9)} SOL';
      final isSender = t.fromUserAccount == feePayer;
      if (isSender) {
        return 'Sent $amt to ${_shortAddr(t.toUserAccount)}';
      } else {
        return 'Received $amt from ${_shortAddr(t.fromUserAccount)}';
      }
    }

    return 'Transfer';
  }

  static String _stakeSummary(List<HeliusNativeTransfer> nativeTransfers) {
    final nonDust = nativeTransfers.where((t) => t.amount > 5000);
    if (nonDust.isNotEmpty) {
      final amt = _formatAmount(nonDust.first.amount / 1e9);
      return 'Staked $amt SOL';
    }
    return 'Stake';
  }

  // -- Helpers --

  static String _symbolForMint(String mint) {
    final def = TokenRegistry.instance.lookup(mint);
    return def?.symbol ?? _shortMint(mint);
  }

  static String _formatAmount(double amount) {
    if (amount >= 1000000) return amount.toStringAsFixed(0);
    if (amount >= 1) return amount.toStringAsFixed(2);
    if (amount >= 0.001) return amount.toStringAsFixed(4);
    return amount.toStringAsFixed(6);
  }

  static String _shortMint(String mint) {
    if (mint.length <= 8) return mint;
    return '${mint.substring(0, 4)}...${mint.substring(mint.length - 4)}';
  }

  static String _shortAddr(String address) {
    if (address.length <= 8) return address;
    return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
  }
}
