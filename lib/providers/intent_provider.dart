import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/intent.dart';
import '../services/solana_rpc.dart';
import '../src/rust/api/agent.dart' as agent_bridge;
import '../src/rust/api/send.dart' as send_bridge;
import '../src/rust/api/sign.dart' as sign_bridge;
import 'network_provider.dart';

class IntentNotifier extends Notifier<List<PendingIntent>> {
  StreamSubscription<agent_bridge.IntentEvent>? _streamSub;

  @override
  List<PendingIntent> build() {
    // Subscribe to intent stream when server is running
    _subscribeToIntents();

    // Clean up subscription on dispose
    ref.onDispose(() {
      _streamSub?.cancel();
    });

    return [];
  }

  void _subscribeToIntents() {
    _streamSub?.cancel();
    try {
      _streamSub = agent_bridge.streamIntents().listen(
        (event) {
          final intent = PendingIntent.fromEvent(
            event.id,
            event.intentTypeJson,
            event.createdAt.toInt(),
            event.apiTokenPrefix,
          );

          // Add to queue
          state = [...state, intent];

          // Auto-reject Stake intents (unsupported in v1)
          if (intent.isStake) {
            _autoRejectStake(intent.id);
            return;
          }

          // Start simulation in background
          _runSimulation(intent.id);
        },
        onError: (e) {
          // Stream error — server may have stopped. Will resubscribe on next server start.
        },
      );
    } catch (_) {
      // streamIntents throws if server not started yet — that's fine
    }
  }

  /// Call this when server starts to (re)subscribe to the intent stream.
  void resubscribe() {
    _subscribeToIntents();
  }

  // --- Queue management ---

  /// Get pending intents only (lifecycle == pending).
  List<PendingIntent> get pending =>
      state.where((i) => i.lifecycle == IntentLifecycle.pending).toList();

  /// Get the first pending intent (for bottom sheet display).
  PendingIntent? get firstPending => pending.isEmpty ? null : pending.first;

  /// Remove an intent from the local queue (after it transitions out of pending).
  void _removeFromQueue(String intentId) {
    state = state.where((i) => i.id != intentId).toList();
  }

  /// Update a specific intent in the queue.
  void _updateIntent(String intentId, PendingIntent Function(PendingIntent) updater) {
    state = state.map((i) => i.id == intentId ? updater(i) : i).toList();
  }

  // --- Auto-reject Stake ---

  Future<void> _autoRejectStake(String intentId) async {
    try {
      await agent_bridge.rejectIntent(intentId: intentId);
      await agent_bridge.updateIntentStatus(
        intentId: intentId,
        status: 'failed',
        error: 'Staking not supported in this version',
      );
    } catch (_) {}
    // Keep in queue briefly so user sees it, then mark rejected
    _updateIntent(intentId, (i) => i.copyWith(
      lifecycle: IntentLifecycle.rejected,
      errorMessage: 'Staking not supported in this version',
    ));
  }

  // --- Simulation ---

  Future<void> _runSimulation(String intentId) async {
    final intentIndex = state.indexWhere((i) => i.id == intentId);
    if (intentIndex == -1) return;
    final intent = state[intentIndex];

    // Skip simulation for sign_message (no transaction) and swap (requires quote)
    if (intent.isSignMessage || intent.type is SwapIntent) return;

    // Mark simulation as running
    _updateIntent(intentId, (i) => i.copyWith(simulationPhase: SimulationPhase.running));

    final net = ref.read(networkProvider);
    final rpc = SolanaRpcClient(net.rpcUrl);
    try {
      // Build unsigned transaction for simulation
      String unsignedBase64;
      final type = intent.type;
      if (type is SendSolIntent) {
        unsignedBase64 = await send_bridge.buildUnsignedSendSol(
          toAddress: type.to,
          lamports: BigInt.from(type.lamports),
        );
      } else if (type is SendTokenIntent) {
        unsignedBase64 = await send_bridge.buildUnsignedSendToken(
          toAddress: type.to,
          mintAddress: type.mint,
          amount: BigInt.from(type.amount),
          createAtaIfNeeded: true,
        );
      } else {
        return; // Unsupported type for simulation
      }

      // Run simulation via RPC (sigVerify=false, replaceRecentBlockhash=true)
      final result = await rpc.simulateTransaction(unsignedBase64);
      _updateIntent(intentId, (i) => i.copyWith(
        simulationPhase: result.success ? SimulationPhase.success : SimulationPhase.failed,
        simulationError: result.success ? null : result.err?.toString(),
        simulationUnitsConsumed: result.unitsConsumed,
      ));
    } catch (e) {
      _updateIntent(intentId, (i) => i.copyWith(
        simulationPhase: SimulationPhase.failed,
        simulationError: e.toString(),
      ));
    } finally {
      rpc.dispose();
    }
  }

  // --- Approve ---

  Future<void> approve(String intentId) async {
    try {
      // 1. Call Rust approve
      await agent_bridge.approveIntent(intentId: intentId);
      _updateIntent(intentId, (i) => i.copyWith(lifecycle: IntentLifecycle.signing));

      // 2. Update server status
      await agent_bridge.updateIntentStatus(intentId: intentId, status: 'signing');

      // 3. Build + sign transaction
      final signResult = await _signTransaction(intentId);

      // For sign_message, there's no on-chain transaction — skip submission
      final intent2 = state.firstWhere((i) => i.id == intentId);
      if (intent2.isSignMessage) {
        _updateIntent(intentId, (i) => i.copyWith(
          lifecycle: IntentLifecycle.confirmed,
          txSignature: signResult.signature,
        ));
        await agent_bridge.updateIntentStatus(
          intentId: intentId,
          status: 'confirmed',
          signature: signResult.signature,
        );
        return;
      }

      // 4. Submit
      _updateIntent(intentId, (i) => i.copyWith(lifecycle: IntentLifecycle.submitting));
      await agent_bridge.updateIntentStatus(intentId: intentId, status: 'submitted');

      final net = ref.read(networkProvider);
      final rpc = SolanaRpcClient(net.rpcUrl);
      try {
        final signature = await rpc.sendTransaction(signResult.base64);

        // 5. Poll for confirmation
        final confirmed = await _pollConfirmation(rpc, signature);

        if (confirmed) {
          _updateIntent(intentId, (i) => i.copyWith(
            lifecycle: IntentLifecycle.confirmed,
            txSignature: signature,
          ));
          await agent_bridge.updateIntentStatus(
            intentId: intentId,
            status: 'confirmed',
            signature: signature,
          );
        } else {
          throw Exception('Transaction not confirmed within timeout');
        }
      } finally {
        rpc.dispose();
      }
    } catch (e) {
      _updateIntent(intentId, (i) => i.copyWith(
        lifecycle: IntentLifecycle.failed,
        errorMessage: e.toString(),
      ));
      try {
        await agent_bridge.updateIntentStatus(
          intentId: intentId,
          status: 'failed',
          error: e.toString(),
        );
      } catch (_) {}
    }
  }

  // --- Reject ---

  Future<void> reject(String intentId) async {
    try {
      await agent_bridge.rejectIntent(intentId: intentId);
    } catch (_) {}
    _removeFromQueue(intentId);
  }

  // --- Retry (after failure) ---

  Future<void> retry(String intentId) async {
    _updateIntent(intentId, (i) => i.copyWith(
      lifecycle: IntentLifecycle.pending,
      errorMessage: null,
    ));
    await approve(intentId);
  }

  // --- Signing pipeline ---

  /// Returns a ({base64, signature}) record for SOL/Token, or a special result
  /// for sign_message (returns the signature directly; no on-chain submission).
  Future<({String base64, String signature})> _signTransaction(String intentId) async {
    final intent = state.firstWhere((i) => i.id == intentId);

    final net = ref.read(networkProvider);
    final rpc = SolanaRpcClient(net.rpcUrl);
    try {
      final type = intent.type;

      if (type is SendSolIntent) {
        final blockhash = await rpc.getLatestBlockhash();
        final result = await send_bridge.signSendSol(
          toAddress: type.to,
          lamports: BigInt.from(type.lamports),
          recentBlockhash: blockhash.blockhash,
        );
        return (base64: result.base64, signature: result.signature);
      } else if (type is SendTokenIntent) {
        final blockhash = await rpc.getLatestBlockhash();
        final result = await send_bridge.signSendToken(
          toAddress: type.to,
          mintAddress: type.mint,
          amount: BigInt.from(type.amount),
          recentBlockhash: blockhash.blockhash,
          createAtaIfNeeded: true,
        );
        return (base64: result.base64, signature: result.signature);
      } else if (type is SwapIntent) {
        // For swap: fetch fresh Jupiter quote, get serialized tx, sign it
        // This requires Jupiter quote integration — implement in swap integration
        throw UnimplementedError('Swap signing requires Jupiter quote — implement in swap integration');
      } else if (type is SignMessageIntent) {
        // Sign raw message bytes with wallet's Ed25519 key
        // sign_message returns SignedTxDto with empty base64 and hex signature
        final result = await sign_bridge.signMessage(messageHex: type.message);
        return (base64: result.base64, signature: result.signature);
      } else {
        throw Exception('Unsupported intent type for signing');
      }
    } finally {
      rpc.dispose();
    }
  }

  /// Poll for transaction confirmation, matching SendProvider pattern.
  /// Returns true if confirmed within ~30 seconds.
  Future<bool> _pollConfirmation(SolanaRpcClient rpc, String signature) async {
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final statuses = await rpc.getSignatureStatuses([signature]);
        final status = statuses.firstOrNull;
        if (status != null) {
          if (status == 'confirmed' || status == 'finalized') {
            return true;
          }
        }
      } catch (_) {
        // Continue polling
      }
    }
    return false;
  }
}

// --- Providers ---

final intentProvider = NotifierProvider<IntentNotifier, List<PendingIntent>>(
  () => IntentNotifier(),
);

/// Count of pending intents for badge display.
final pendingIntentCountProvider = Provider<int>((ref) {
  final intents = ref.watch(intentProvider);
  return intents.where((i) => i.lifecycle == IntentLifecycle.pending).length;
});

/// The first pending intent (for auto-show bottom sheet).
final firstPendingIntentProvider = Provider<PendingIntent?>((ref) {
  final intents = ref.watch(intentProvider);
  final pending = intents.where((i) => i.lifecycle == IntentLifecycle.pending);
  return pending.isEmpty ? null : pending.first;
});
