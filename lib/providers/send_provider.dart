import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/send.dart';
import '../services/solana_rpc.dart';
import '../src/rust/api/guardrails.dart' as guardrails_bridge;
import '../src/rust/api/hardware.dart' as hw_bridge;
import '../src/rust/api/send.dart' as bridge;
import '../src/rust/api/wallet.dart' as wallet_bridge;
import 'network_provider.dart';
import 'wallet_provider.dart';

class SendNotifier extends Notifier<SendState> {
  @override
  SendState build() => const SendState();

  SolanaRpcClient get _rpc {
    final net = ref.read(networkProvider);
    return SolanaRpcClient(net.rpcUrl);
  }

  String? get _activeAddress => ref.read(activeWalletProvider);

  /// Check if the active wallet is a hardware wallet.
  bool get _isHardwareWallet {
    final wallets = ref.read(walletListProvider).valueOrNull ?? [];
    final address = _activeAddress;
    if (address == null) return false;
    final wallet = wallets.where((w) => w.address == address).firstOrNull;
    return wallet?.source == 'hardware';
  }

  void setRecipient(String address) {
    state = state.copyWith(recipient: address);
  }

  void goToAssetStep() {
    state = state.copyWith(step: SendStep.asset);
  }

  void selectAsset(SendAsset asset) {
    state = state.copyWith(asset: asset, amountText: '', step: SendStep.amount);
  }

  void setAmount(String amount) {
    state = state.copyWith(amountText: amount);
  }

  void goToReview() {
    state = state.copyWith(step: SendStep.review);
  }

  void goBack() {
    switch (state.step) {
      case SendStep.asset:
        state = state.copyWith(step: SendStep.recipient);
      case SendStep.amount:
        state = state.copyWith(step: SendStep.asset);
      case SendStep.review:
        state = state.copyWith(step: SendStep.amount);
      default:
        break;
    }
  }

  void reset() {
    state = const SendState();
  }

  /// Check the current send against guardrails. Called from UI before signAndSubmit.
  void checkGuardrails() {
    final asset = state.asset;
    String? mint;
    if (asset is SendToken) {
      mint = asset.tokenBalance.definition.mint;
    }
    // SOL sends: mint is null, passes whitelist check (SOL exempt per decision)
    // NFT sends use a completely separate flow (NftNotifier) and are NOT checked here
    final violation = guardrails_bridge.checkManualTransaction(
      mint: mint,
      outputMint: null,
    );
    state = state.copyWith(
      guardrailViolation: violation,
      guardrailBypassed: false,
    );
  }

  /// Mark current transaction as having guardrail bypass approved.
  void bypassGuardrails() {
    state = state.copyWith(guardrailBypassed: true, guardrailViolation: null);
  }

  Future<void> simulate() async {
    state = state.copyWith(
      txStatus: TxStatus.simulating,
      simulationError: null,
      simulationSuccess: false,
    );

    final rpc = _rpc;
    try {
      final address = _activeAddress;
      if (address == null) throw Exception('No active wallet');

      if (!_isHardwareWallet) {
        await _ensureUnlocked(address);
      }

      final blockhash = await rpc.getLatestBlockhash();
      final signedTx = await _buildSignedTx(blockhash.blockhash);
      final sim = await rpc.simulateTransaction(signedTx.base64);

      if (sim.success) {
        state = state.copyWith(
          txStatus: TxStatus.idle,
          simulationSuccess: true,
          simulationUnitsConsumed: sim.unitsConsumed,
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
    // Check guardrails before signing (skip if already bypassed)
    if (!state.guardrailBypassed) {
      final asset = state.asset;
      String? mint;
      if (asset is SendToken) {
        mint = asset.tokenBalance.definition.mint;
      }
      // SOL sends: mint is null -> passes whitelist check
      // NFT sends: completely separate flow (NftNotifier), never reaches here
      final violation = guardrails_bridge.checkManualTransaction(
        mint: mint,
        outputMint: null,
      );
      if (violation != null) {
        state = state.copyWith(guardrailViolation: violation);
        return; // UI shows banner; user must bypass
      }
    }

    state = state.copyWith(
      txStatus: TxStatus.signing,
      errorMessage: null,
    );

    final rpc = _rpc;
    try {
      final address = _activeAddress;
      if (address == null) throw Exception('No active wallet');

      if (!_isHardwareWallet) {
        await _ensureUnlocked(address);
      }

      // Get fresh blockhash
      state = state.copyWith(txStatus: TxStatus.signing);
      final blockhash = await rpc.getLatestBlockhash();

      // Build + sign via Rust
      final signedTx = await _buildSignedTx(blockhash.blockhash);

      // Submit
      state = state.copyWith(txStatus: TxStatus.submitting);
      final signature = await rpc.sendTransaction(signedTx.base64);

      state = state.copyWith(
        txStatus: TxStatus.polling,
        txSignature: signature,
        step: SendStep.confirming,
        confirmationStatus: 'submitted',
      );

      // Poll for confirmation
      _pollConfirmation(rpc, signature);
    } catch (e) {
      state = state.copyWith(
        txStatus: TxStatus.failed,
        errorMessage: e.toString(),
      );
      rpc.dispose();
    }
  }

  Future<void> _ensureUnlocked(String address) async {
    final unlocked = wallet_bridge.isWalletUnlocked(address: address);
    if (!unlocked) {
      await wallet_bridge.unlockWallet(address: address);
    }
  }

  /// Find the serial port for the connected hardware wallet.
  Future<String> _findHardwarePort() async {
    final ports = await hw_bridge.scanHardwareWallets();
    if (ports.isEmpty) {
      throw Exception(
          'Hardware wallet not found. Please connect your device via USB.');
    }
    // Use the first detected port
    return ports.first.path;
  }

  Future<({String base64, String signature})> _buildSignedTx(
    String blockhash,
  ) async {
    final asset = state.asset;
    final rawAmount = state.rawAmount;
    if (rawAmount == null) throw Exception('Invalid amount');

    if (_isHardwareWallet) {
      return _buildSignedTxHardware(blockhash, asset!, rawAmount);
    }
    return _buildSignedTxSoftware(blockhash, asset!, rawAmount);
  }

  Future<({String base64, String signature})> _buildSignedTxSoftware(
    String blockhash,
    SendAsset asset,
    BigInt rawAmount,
  ) async {
    if (asset is SendSol) {
      final result = await bridge.signSendSol(
        toAddress: state.recipient,
        lamports: rawAmount,
        recentBlockhash: blockhash,
        computeUnitLimit: 200000,
        computeUnitPrice: BigInt.from(50000),
      );
      return (base64: result.base64, signature: result.signature);
    } else if (asset is SendToken) {
      final result = await bridge.signSendToken(
        toAddress: state.recipient,
        mintAddress: asset.tokenBalance.definition.mint,
        amount: rawAmount,
        recentBlockhash: blockhash,
        createAtaIfNeeded: true,
        computeUnitLimit: 200000,
        computeUnitPrice: BigInt.from(50000),
      );
      return (base64: result.base64, signature: result.signature);
    }
    throw Exception('No asset selected');
  }

  Future<({String base64, String signature})> _buildSignedTxHardware(
    String blockhash,
    SendAsset asset,
    BigInt rawAmount,
  ) async {
    final portPath = await _findHardwarePort();

    if (asset is SendSol) {
      final result = await bridge.signSendSolHardware(
        portPath: portPath,
        toAddress: state.recipient,
        lamports: rawAmount,
        recentBlockhash: blockhash,
        computeUnitLimit: 200000,
        computeUnitPrice: BigInt.from(50000),
      );
      return (base64: result.base64, signature: result.signature);
    } else if (asset is SendToken) {
      final result = await bridge.signSendTokenHardware(
        portPath: portPath,
        toAddress: state.recipient,
        mintAddress: asset.tokenBalance.definition.mint,
        amount: rawAmount,
        recentBlockhash: blockhash,
        createAtaIfNeeded: true,
        computeUnitLimit: 200000,
        computeUnitPrice: BigInt.from(50000),
      );
      return (base64: result.base64, signature: result.signature);
    }
    throw Exception('No asset selected');
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
      } catch (_) {
        // Keep polling on transient errors
      }

      // Stop after ~60 seconds
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

final sendProvider = NotifierProvider<SendNotifier, SendState>(
  SendNotifier.new,
);
