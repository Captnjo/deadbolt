import 'dart:async';

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
        final address = _activeAddress;
        if (address == null) throw Exception('No active wallet');
        final apiKeys = ref.read(apiKeysProvider);
        final dflow = DFlowService(apiKey: apiKeys.dflowKey);
        try {
          final order = await dflow.getOrder(
            inputMint: input.definition.mint,
            outputMint: output.definition.mint,
            amount: rawAmount.toString(),
            userPublicKey: address,
          );
          state = state.copyWith(
            dflowOrder: order,
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

    String unsignedTxBase64;

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
      final order = state.dflowOrder;
      if (order == null) throw Exception('No DFlow order available');
      unsignedTxBase64 = order.transaction;
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
