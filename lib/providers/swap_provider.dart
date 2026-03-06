import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/send.dart' show TxStatus;
import '../models/swap.dart';
import '../models/token.dart';
import '../services/dflow_service.dart';
import '../services/jupiter_service.dart';
import '../services/solana_rpc.dart';
import '../src/rust/api/sign.dart' as sign_bridge;
import '../src/rust/api/wallet.dart' as wallet_bridge;
import '../src/rust/api/hardware.dart' as hw_bridge;
import 'api_keys_provider.dart';
import 'network_provider.dart';
import 'wallet_provider.dart';

const _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

Uint8List base58Decode(String input) {
  final bytes = <int>[];
  for (final c in input.codeUnits) {
    final carry = _base58Alphabet.indexOf(String.fromCharCode(c));
    if (carry < 0) throw FormatException('Invalid base58 character: $c');
    int j = bytes.length;
    int acc = carry;
    while (j > 0 || acc > 0) {
      j--;
      if (j >= 0) acc += bytes[j] * 58;
      if (j >= 0) {
        bytes[j] = acc & 0xFF;
      } else {
        bytes.insert(0, acc & 0xFF);
      }
      acc >>= 8;
    }
  }
  // Leading zeros
  for (final c in input.codeUnits) {
    if (c == 0x31) {
      bytes.insert(0, 0);
    } else {
      break;
    }
  }
  return Uint8List.fromList(bytes);
}

class SwapNotifier extends Notifier<SwapState> {
  Timer? _debounce;

  @override
  SwapState build() {
    final apiKeys = ref.read(apiKeysProvider);
    return SwapState(aggregator: apiKeys.defaultAggregator);
  }

  SolanaRpcClient get _rpc {
    final net = ref.read(networkProvider);
    return SolanaRpcClient(net.rpcUrl);
  }

  String? get _activeAddress => ref.read(activeWalletProvider);

  bool get _isHardwareWallet {
    final wallets = ref.read(walletListProvider).valueOrNull ?? [];
    final address = _activeAddress;
    if (address == null) return false;
    final wallet = wallets.where((w) => w.address == address).firstOrNull;
    return wallet?.source == 'hardware';
  }

  void setInputToken(TokenBalance token) {
    state = state.copyWith(inputToken: token);
    _debouncedQuote();
  }

  void setOutputToken(TokenBalance token) {
    state = state.copyWith(outputToken: token);
    _debouncedQuote();
  }

  void setInputAmount(String amount) {
    state = state.copyWith(inputAmount: amount);
    _debouncedQuote();
  }

  void setAggregator(SwapAggregator aggregator) {
    state = state.copyWith(aggregator: aggregator);
    _debouncedQuote();
  }

  void flipTokens() {
    final input = state.inputToken;
    final output = state.outputToken;
    state = state.copyWith(inputToken: output, outputToken: input);
    _debouncedQuote();
  }

  void goToReview() {
    state = state.copyWith(step: SwapStep.review);
  }

  void goBack() {
    switch (state.step) {
      case SwapStep.review:
        state = state.copyWith(step: SwapStep.configure);
      default:
        break;
    }
  }

  void reset() {
    _debounce?.cancel();
    final apiKeys = ref.read(apiKeysProvider);
    state = SwapState(aggregator: apiKeys.defaultAggregator);
  }

  void _debouncedQuote() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      fetchQuote();
    });
  }

  Future<void> fetchQuote() async {
    final input = state.inputToken;
    final output = state.outputToken;
    if (input == null || output == null || state.inputAmount.isEmpty) return;

    final parsed = double.tryParse(state.inputAmount);
    if (parsed == null || parsed <= 0) return;

    final rawAmount = BigInt.from(
      (parsed * BigInt.from(10).pow(input.definition.decimals).toDouble()).round(),
    );

    state = state.copyWith(isQuoting: true, quoteError: null);

    try {
      if (state.aggregator == SwapAggregator.jupiter) {
        final apiKeys = ref.read(apiKeysProvider);
        final jupiter = JupiterService(apiKey: apiKeys.jupiterKey);
        try {
          final quote = await jupiter.getQuote(
            inputMint: input.definition.mint,
            outputMint: output.definition.mint,
            amount: rawAmount.toString(),
          );
          state = state.copyWith(
            jupiterQuote: quote,
            isQuoting: false,
          );
        } finally {
          jupiter.dispose();
        }
      } else {
        final apiKeys = ref.read(apiKeysProvider);
        final dflow = DFlowService(apiKey: apiKeys.dflowKey);
        try {
          final quote = await dflow.getQuote(
            inputMint: input.definition.mint,
            outputMint: output.definition.mint,
            amount: rawAmount.toString(),
          );
          state = state.copyWith(
            dflowQuote: quote,
            isQuoting: false,
          );
        } finally {
          dflow.dispose();
        }
      }
    } catch (e) {
      state = state.copyWith(
        isQuoting: false,
        quoteError: e.toString(),
      );
    }
  }

  Future<void> simulate() async {
    state = state.copyWith(
      txStatus: TxStatus.simulating,
      simulationError: null,
      simulationSuccess: false,
    );

    final rpc = _rpc;
    try {
      final signedBase64 = await _getSignedTxBase64();
      final sim = await rpc.simulateTransaction(signedBase64);

      if (sim.success) {
        state = state.copyWith(
          txStatus: TxStatus.idle,
          simulationSuccess: true,
        );
      } else {
        state = state.copyWith(
          txStatus: TxStatus.idle,
          simulationSuccess: false,
          simulationError: sim.err.toString(),
        );
      }
    } catch (e) {
      state = state.copyWith(
        txStatus: TxStatus.idle,
        simulationSuccess: false,
        simulationError: e.toString(),
      );
    } finally {
      rpc.dispose();
    }
  }

  Future<void> signAndSubmit() async {
    state = state.copyWith(txStatus: TxStatus.signing, errorMessage: null);

    final rpc = _rpc;
    try {
      final signedBase64 = await _getSignedTxBase64();

      state = state.copyWith(txStatus: TxStatus.submitting);
      final signature = await rpc.sendTransaction(signedBase64);

      state = state.copyWith(
        txStatus: TxStatus.polling,
        txSignature: signature,
        step: SwapStep.confirming,
        confirmationStatus: 'submitted',
      );

      _pollConfirmation(rpc, signature);
    } catch (e) {
      state = state.copyWith(
        txStatus: TxStatus.failed,
        errorMessage: e.toString(),
      );
      rpc.dispose();
    }
  }

  Future<String> _getSignedTxBase64() async {
    final address = _activeAddress;
    if (address == null) throw Exception('No active wallet');

    final rpc = _rpc;
    String unsignedTxBase64;

    try {
      if (state.aggregator == SwapAggregator.jupiter) {
        final quote = state.jupiterQuote;
        if (quote == null) throw Exception('No quote available');
        final apiKeys = ref.read(apiKeysProvider);
        final jupiter = JupiterService(apiKey: apiKeys.jupiterKey);
        try {
          unsignedTxBase64 = await jupiter.getSwapTransaction(
            quoteResponse: quote.raw,
            userPublicKey: address,
          );
        } finally {
          jupiter.dispose();
        }
      } else {
        final quote = state.dflowQuote;
        if (quote == null) throw Exception('No DFlow quote available');
        final apiKeys = ref.read(apiKeysProvider);
        final dflow = DFlowService(apiKey: apiKeys.dflowKey);
        try {
          unsignedTxBase64 = await dflow.getSwapTransaction(
            quoteResponse: quote.raw,
            userPublicKey: address,
          );
        } finally {
          dflow.dispose();
        }
      }

      // Replace stale blockhash with a fresh one
      unsignedTxBase64 = await _replaceBlockhash(rpc, unsignedTxBase64);
    } finally {
      rpc.dispose();
    }

    if (!_isHardwareWallet) {
      final unlocked = wallet_bridge.isWalletUnlocked(address: address);
      if (!unlocked) {
        await wallet_bridge.unlockWallet(address: address);
      }
      final signed = await sign_bridge.signSerializedTransaction(
        unsignedTxBase64: unsignedTxBase64,
      );
      return signed.base64;
    } else {
      final ports = await hw_bridge.scanHardwareWallets();
      if (ports.isEmpty) throw Exception('Hardware wallet not connected');
      final signed = await sign_bridge.signSerializedTransactionHardware(
        portPath: ports.first.path,
        unsignedTxBase64: unsignedTxBase64,
      );
      return signed.base64;
    }
  }

  /// Replace the blockhash in a serialized VersionedTransaction (base64).
  /// Solana VersionedTransactions: first byte is prefix (0x80 = v0),
  /// then the message. The blockhash is the first 32 bytes of the message
  /// body after the header (3 bytes) + signer count + signer pubkeys.
  Future<String> _replaceBlockhash(
      SolanaRpcClient rpc, String txBase64) async {
    final bh = await rpc.getLatestBlockhash();
    final freshHash = base58Decode(bh.blockhash);

    final bytes = base64Decode(txBase64);
    final buf = Uint8List.fromList(bytes);

    // Find message start: skip signature section
    int offset = 0;
    // Compact-u16 for number of signatures
    final numSigs = _readCompactU16(buf, offset);
    offset = numSigs.nextOffset;
    // Skip signature bytes (64 each)
    offset += numSigs.value * 64;

    // Now at message start
    final messageStart = offset;

    if (buf[messageStart] == 0x80) {
      // Versioned transaction (v0): prefix byte + compact header
      offset = messageStart + 1; // skip 0x80 prefix
    }
    // Legacy or after v0 prefix: 3-byte header
    offset += 3; // numRequiredSignatures, numReadonlySignedAccounts, numReadonlyUnsignedAccounts

    // Compact-u16 for number of account keys
    final numKeys = _readCompactU16(buf, offset);
    offset = numKeys.nextOffset;
    // Skip account pubkeys (32 each)
    offset += numKeys.value * 32;

    // Next 32 bytes = blockhash
    buf.setRange(offset, offset + 32, freshHash);

    return base64Encode(buf);
  }

  ({int value, int nextOffset}) _readCompactU16(Uint8List buf, int offset) {
    int value = 0;
    int shift = 0;
    int pos = offset;
    while (true) {
      final byte = buf[pos];
      value |= (byte & 0x7F) << shift;
      pos++;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return (value: value, nextOffset: pos);
  }

  void _pollConfirmation(SolanaRpcClient rpc, String signature) {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final statuses = await rpc.getSignatureStatuses([signature]);
        final status = statuses.firstOrNull;
        if (status != null) {
          state = state.copyWith(confirmationStatus: status);
          if (status == 'confirmed' || status == 'finalized') {
            state = state.copyWith(txStatus: TxStatus.confirmed);
            timer.cancel();
            rpc.dispose();
          }
        }
      } catch (_) {}

      if (timer.tick > 30) {
        timer.cancel();
        rpc.dispose();
        if (state.txStatus == TxStatus.polling) {
          state = state.copyWith(
            txStatus: TxStatus.confirmed,
            confirmationStatus: 'submitted',
          );
        }
      }
    });
  }
}

final swapProvider = NotifierProvider<SwapNotifier, SwapState>(
  SwapNotifier.new,
);
