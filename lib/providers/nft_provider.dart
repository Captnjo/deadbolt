import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nft.dart';
import '../models/send.dart' show TxStatus;
import '../models/token.dart';
import '../services/helius_das_service.dart';
import '../services/solana_rpc.dart';
import '../src/rust/api/send.dart' as send_bridge;
import '../src/rust/api/wallet.dart' as wallet_bridge;
import '../src/rust/api/hardware.dart' as hw_bridge;
import 'network_provider.dart';
import 'wallet_provider.dart';

class NftNotifier extends Notifier<SendNftState> {
  @override
  SendNftState build() {
    _loadNfts();
    return const SendNftState(isLoadingNfts: true);
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

  Future<void> _loadNfts() async {
    final address = _activeAddress;
    final net = ref.read(networkProvider);

    if (address == null || net.network != SolanaNetwork.mainnet) {
      state = state.copyWith(
        isLoadingNfts: false,
        nfts: [],
        nftLoadError: net.network != SolanaNetwork.mainnet
            ? 'NFTs only available on mainnet'
            : null,
      );
      return;
    }

    final heliusKey = net.heliusApiKey;
    if (heliusKey.isEmpty) {
      state = state.copyWith(
        isLoadingNfts: false,
        nfts: [],
        nftLoadError: 'Helius API key required for NFTs',
      );
      return;
    }

    final das = HeliusDasService(apiKey: heliusKey);
    try {
      final nfts = await das.getAssetsByOwner(address);
      state = state.copyWith(nfts: nfts, isLoadingNfts: false);
    } catch (e) {
      state = state.copyWith(
        isLoadingNfts: false,
        nftLoadError: e.toString(),
      );
    } finally {
      das.dispose();
    }
  }

  void selectNft(NftAsset nft) {
    state = state.copyWith(selectedNft: nft, step: SendNftStep.recipient);
  }

  void setRecipient(String address) {
    state = state.copyWith(recipient: address);
  }

  void goToReview() {
    state = state.copyWith(step: SendNftStep.review);
  }

  void goBack() {
    switch (state.step) {
      case SendNftStep.recipient:
        state = state.copyWith(step: SendNftStep.selectNft);
      case SendNftStep.review:
        state = state.copyWith(step: SendNftStep.recipient);
      default:
        break;
    }
  }

  void reset() {
    state = const SendNftState();
    _loadNfts();
  }

  Future<void> simulate() async {
    state = state.copyWith(
      txStatus: TxStatus.simulating,
      simulationError: null,
      simulationSuccess: false,
    );

    final rpc = _rpc;
    try {
      final signedTx = await _buildSignedTx();
      final sim = await rpc.simulateTransaction(signedTx);

      if (sim.success) {
        state = state.copyWith(txStatus: TxStatus.idle, simulationSuccess: true);
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
      final signedTx = await _buildSignedTx();

      state = state.copyWith(txStatus: TxStatus.submitting);
      final signature = await rpc.sendTransaction(signedTx);

      state = state.copyWith(
        txStatus: TxStatus.polling,
        txSignature: signature,
        step: SendNftStep.confirming,
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

  /// NFTs are SPL tokens with amount=1. Use the existing signSendToken bridge.
  Future<String> _buildSignedTx() async {
    final address = _activeAddress;
    if (address == null) throw Exception('No active wallet');

    final nft = state.selectedNft;
    if (nft == null) throw Exception('No NFT selected');

    final rpc = _rpc;
    final blockhash = await rpc.getLatestBlockhash();
    rpc.dispose();

    if (!_isHardwareWallet) {
      final unlocked = wallet_bridge.isWalletUnlocked(address: address);
      if (!unlocked) {
        await wallet_bridge.unlockWallet(address: address);
      }
      final result = await send_bridge.signSendToken(
        toAddress: state.recipient,
        mintAddress: nft.mint,
        amount: BigInt.one,
        recentBlockhash: blockhash.blockhash,
        createAtaIfNeeded: true,
        computeUnitLimit: 200000,
        computeUnitPrice: BigInt.from(50000),
      );
      return result.base64;
    } else {
      final ports = await hw_bridge.scanHardwareWallets();
      if (ports.isEmpty) throw Exception('Hardware wallet not connected');
      final result = await send_bridge.signSendTokenHardware(
        portPath: ports.first.path,
        toAddress: state.recipient,
        mintAddress: nft.mint,
        amount: BigInt.one,
        recentBlockhash: blockhash.blockhash,
        createAtaIfNeeded: true,
        computeUnitLimit: 200000,
        computeUnitPrice: BigInt.from(50000),
      );
      return result.base64;
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

final nftProvider = NotifierProvider<NftNotifier, SendNftState>(
  NftNotifier.new,
);
