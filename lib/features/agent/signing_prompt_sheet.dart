import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/intent.dart';
import '../../providers/intent_provider.dart';
import '../../theme/brand_theme.dart';

// ---------------------------------------------------------------------------
// Public API — call this to show the signing prompt for a given intent.
// ---------------------------------------------------------------------------

void showSigningPrompt(BuildContext context, String intentId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => SigningPromptSheet(
        intentId: intentId,
        scrollController: scrollController,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// SigningPromptSheet widget
// ---------------------------------------------------------------------------

class SigningPromptSheet extends ConsumerStatefulWidget {
  final String intentId;
  final ScrollController scrollController;

  const SigningPromptSheet({
    super.key,
    required this.intentId,
    required this.scrollController,
  });

  @override
  ConsumerState<SigningPromptSheet> createState() => _SigningPromptSheetState();
}

class _SigningPromptSheetState extends ConsumerState<SigningPromptSheet> {
  late String _currentIntentId;
  Timer? _autoDismissTimer;
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    _currentIntentId = widget.intentId;
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  // ---- Actions ----

  Future<void> _approve() async {
    await ref.read(intentProvider.notifier).approve(_currentIntentId);
  }

  Future<void> _reject() async {
    // Capture next intent before removing current, to avoid double-pop race.
    final next = ref.read(firstPendingIntentProvider);
    final hasNext = next != null && next.id != _currentIntentId;

    await ref.read(intentProvider.notifier).reject(_currentIntentId);
    if (!mounted) return;

    if (hasNext) {
      setState(() => _currentIntentId = next.id);
    } else if (!_popping) {
      _popping = true;
      Navigator.of(context).pop();
    }
  }

  Future<void> _retry() async {
    await ref.read(intentProvider.notifier).retry(_currentIntentId);
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  /// After current intent is handled, advance to the next pending intent or close.
  void _advanceToNext() {
    final next = ref.read(firstPendingIntentProvider);
    if (next != null && next.id != _currentIntentId) {
      setState(() => _currentIntentId = next.id);
    } else if (!_popping) {
      _popping = true;
      Navigator.of(context).pop();
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final intents = ref.watch(intentProvider);
    final pendingCount = ref.watch(pendingIntentCountProvider);

    // Find the current intent in state.
    final intentOrNull = intents.where((i) => i.id == _currentIntentId).firstOrNull;

    // If the intent was removed (e.g. rejected and purged), close the sheet.
    if (intentOrNull == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_popping) {
          _popping = true;
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    final intent = intentOrNull;

    // Watch for lifecycle transitions to trigger auto-dismiss or advance.
    _handleLifecycleChange(intent);

    final isSigningInProgress = intent.lifecycle != IntentLifecycle.pending &&
        intent.lifecycle != IntentLifecycle.rejected;

    return Container(
      decoration: const BoxDecoration(
        color: BrandColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: BrandColors.border, width: 1),
        ),
      ),
      child: ListView(
        controller: widget.scrollController,
        padding: EdgeInsets.zero,
        children: [
          // ---- Drag handle ----
          const _DragHandle(),

          // ---- "N more pending" indicator ----
          if (pendingCount > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${pendingCount - 1} more pending',
                style: const TextStyle(
                  fontSize: 12,
                  color: BrandColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // ---- Content: preview or signing progress ----
          if (isSigningInProgress)
            _SigningProgressView(
              intent: intent,
              onRetry: _retry,
              onDismiss: _dismiss,
              onAutoDismiss: () {
                _autoDismissTimer?.cancel();
                _autoDismissTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) {
                    Navigator.of(context).pop();
                    _advanceToNext();
                  }
                });
              },
            )
          else
            _IntentPreviewContent(
              intent: intent,
              onApprove: _approve,
              onReject: _reject,
            ),
        ],
      ),
    );
  }

  void _handleLifecycleChange(PendingIntent intent) {
    // Schedule auto-dismiss on confirmed state.
    if (intent.lifecycle == IntentLifecycle.confirmed) {
      if (_autoDismissTimer == null || !_autoDismissTimer!.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _autoDismissTimer?.cancel();
            _autoDismissTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) {
                Navigator.of(context).pop();
                _advanceToNext();
              }
            });
          }
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Drag handle
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: BrandColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Intent preview content (lifecycle == pending)
// ---------------------------------------------------------------------------

class _IntentPreviewContent extends StatelessWidget {
  final PendingIntent intent;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _IntentPreviewContent({
    required this.intent,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Agent label ----
          Text(
            intent.agentTokenPrefix,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: BrandColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // ---- Intent type header ----
          Text(
            _intentTypeLabel(intent.type),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // ---- Type-specific rows ----
          _buildTypeSpecificRows(intent),

          // ---- Simulation status row ----
          if (!intent.isSignMessage)
            _SimulationStatusRow(intent: intent),

          const SizedBox(height: 24),

          // ---- Action buttons ----
          _ActionButtons(
            intent: intent,
            onApprove: onApprove,
            onReject: onReject,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _intentTypeLabel(AgentIntentType type) {
    return switch (type) {
      SendSolIntent() => 'Send SOL',
      SendTokenIntent() => 'Send Token',
      SwapIntent() => 'Swap',
      SignMessageIntent() => 'Sign Message',
      StakeIntent() => 'Stake',
    };
  }

  Widget _buildTypeSpecificRows(PendingIntent intent) {
    final type = intent.type;

    if (type is SendSolIntent) {
      return _SendSolRows(intent: type);
    } else if (type is SendTokenIntent) {
      return _SendTokenRows(intent: type);
    } else if (type is SwapIntent) {
      return _SwapRows(intent: intent, swap: type);
    } else if (type is SignMessageIntent) {
      return _SignMessageRows(message: type);
    } else if (type is StakeIntent) {
      return _StakeRows();
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// SendSol preview rows
// ---------------------------------------------------------------------------

class _SendSolRows extends StatelessWidget {
  final SendSolIntent intent;
  const _SendSolRows({required this.intent});

  @override
  Widget build(BuildContext context) {
    final truncated = _truncateAddress(intent.to);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${intent.solAmount.toStringAsFixed(4)} SOL',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: BrandColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Recipient
        const Text(
          'To',
          style: TextStyle(fontSize: 12, color: BrandColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          truncated,
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        // Fee
        const Text(
          '~0.000005 SOL',
          style: TextStyle(fontSize: 14, color: BrandColors.textSecondary),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SendToken preview rows
// ---------------------------------------------------------------------------

class _SendTokenRows extends StatelessWidget {
  final SendTokenIntent intent;
  const _SendTokenRows({required this.intent});

  @override
  Widget build(BuildContext context) {
    final truncated = _truncateAddress(intent.to);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${intent.amount} tokens',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: BrandColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'To',
          style: TextStyle(fontSize: 12, color: BrandColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          truncated,
          style: const TextStyle(
            fontSize: 14,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '~0.000005 SOL',
          style: TextStyle(fontSize: 14, color: BrandColors.textSecondary),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Swap preview rows
// ---------------------------------------------------------------------------

class _SwapRows extends StatelessWidget {
  final PendingIntent intent;
  final SwapIntent swap;
  const _SwapRows({required this.intent, required this.swap});

  @override
  Widget build(BuildContext context) {
    final slippageText = swap.slippageBps != null
        ? '${(swap.slippageBps! / 100).toStringAsFixed(1)}%'
        : '0.5%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input
        Text(
          '${swap.amount} tokens',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        // Output
        if (intent.swapQuote != null) ...[
          Text(
            '~${intent.swapQuote!.expectedOutput.toStringAsFixed(4)} ${intent.swapQuote!.outputSymbol}',
            style: const TextStyle(fontSize: 14, color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '1 token = ${intent.swapQuote!.exchangeRate.toStringAsFixed(6)}',
            style: const TextStyle(fontSize: 12, color: BrandColors.textSecondary),
          ),
        ] else ...[
          const Text(
            'Fetching quote...',
            style: TextStyle(fontSize: 12, color: BrandColors.textDisabled),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Slippage: $slippageText',
          style: const TextStyle(fontSize: 12, color: BrandColors.textSecondary),
        ),
        const SizedBox(height: 4),
        const Text(
          '~0.000005 SOL',
          style: TextStyle(fontSize: 14, color: BrandColors.textSecondary),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SignMessage preview rows
// ---------------------------------------------------------------------------

class _SignMessageRows extends StatelessWidget {
  final SignMessageIntent message;
  const _SignMessageRows({required this.message});

  @override
  Widget build(BuildContext context) {
    final messageText = message.messageUtf8 ?? message.message;
    final isUtf8 = message.messageUtf8 != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BrandColors.warning.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BrandColors.warning),
          ),
          child: const Text(
            'Message signature only. No transaction, no fees.',
            style: TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 16),
        // Message label
        Text(
          isUtf8 ? 'Message (UTF-8)' : 'Message (hex)',
          style: const TextStyle(fontSize: 12, color: BrandColors.textSecondary),
        ),
        const SizedBox(height: 4),
        // Message body — scrollable, max 6 lines
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 6 * 18.0),
          child: SingleChildScrollView(
            child: Text(
              messageText,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: BrandColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stake preview rows (unsupported)
// ---------------------------------------------------------------------------

class _StakeRows extends StatelessWidget {
  const _StakeRows();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BrandColors.warning.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BrandColors.warning),
          ),
          child: const Text(
            'Staking is not supported in this version.',
            style: TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Simulation status row
// ---------------------------------------------------------------------------

class _SimulationStatusRow extends StatelessWidget {
  final PendingIntent intent;
  const _SimulationStatusRow({required this.intent});

  @override
  Widget build(BuildContext context) {
    switch (intent.simulationPhase) {
      case SimulationPhase.idle:
        return const SizedBox.shrink();

      case SimulationPhase.running:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: const [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: BrandColors.primary,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Simulation: Running...',
                style: TextStyle(fontSize: 12, color: BrandColors.textSecondary),
              ),
            ],
          ),
        );

      case SimulationPhase.success:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: const [
              Icon(Icons.check_circle_outline, size: 14, color: BrandColors.success),
              SizedBox(width: 8),
              Text(
                'Simulation: Passed',
                style: TextStyle(fontSize: 12, color: BrandColors.success),
              ),
            ],
          ),
        );

      case SimulationPhase.failed:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BrandColors.error.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: BrandColors.error),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Simulation failed',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: BrandColors.error,
                  ),
                ),
                if (intent.simulationError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    intent.simulationError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: BrandColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Approving a failed simulation may result in a lost tx fee',
                  style: TextStyle(fontSize: 12, color: BrandColors.warning),
                ),
              ],
            ),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Action buttons (Approve/Sign + Reject)
// ---------------------------------------------------------------------------

class _ActionButtons extends StatelessWidget {
  final PendingIntent intent;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ActionButtons({
    required this.intent,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isStake = intent.isStake;
    final label = intent.isSignMessage ? 'Sign' : 'Approve';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Approve / Sign button
        ElevatedButton(
          style: isStake
              ? ElevatedButton.styleFrom(
                  backgroundColor: BrandColors.textDisabled,
                  foregroundColor: BrandColors.background,
                )
              : null,
          onPressed: isStake ? null : onApprove,
          child: Text(label),
        ),
        const SizedBox(height: 8),
        // Reject button
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: BrandColors.error,
            side: const BorderSide(color: BrandColors.error),
          ),
          onPressed: onReject,
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Signing progress view (replaces preview after approve)
// ---------------------------------------------------------------------------

class _SigningProgressView extends StatefulWidget {
  final PendingIntent intent;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;
  final VoidCallback onAutoDismiss;

  const _SigningProgressView({
    required this.intent,
    required this.onRetry,
    required this.onDismiss,
    required this.onAutoDismiss,
  });

  @override
  State<_SigningProgressView> createState() => _SigningProgressViewState();
}

class _SigningProgressViewState extends State<_SigningProgressView> {
  bool _autoDismissScheduled = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: _buildLifecycleContent(widget.intent.lifecycle),
    );
  }

  Widget _buildLifecycleContent(IntentLifecycle lifecycle) {
    switch (lifecycle) {
      case IntentLifecycle.signing:
        return _buildSigning();
      case IntentLifecycle.submitting:
        return _buildSubmitting();
      case IntentLifecycle.confirmed:
        _scheduleAutoDismiss();
        return _buildConfirmed();
      case IntentLifecycle.failed:
        return _buildFailed();
      case IntentLifecycle.pending:
      case IntentLifecycle.rejected:
        return const SizedBox.shrink();
    }
  }

  void _scheduleAutoDismiss() {
    if (!_autoDismissScheduled) {
      _autoDismissScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onAutoDismiss();
      });
    }
  }

  Widget _buildSigning() {
    // TODO: detect hardware wallet — for now always show hot wallet variant
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: BrandColors.primary),
        ),
        SizedBox(height: 16),
        Text(
          'Signing...',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          'Connect your ESP32 to sign',
          style: TextStyle(fontSize: 14, color: BrandColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSubmitting() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: BrandColors.primary),
        ),
        SizedBox(height: 16),
        Text(
          'Submitting...',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildConfirmed() {
    final sig = widget.intent.txSignature;
    final truncatedSig = sig != null && sig.length > 16
        ? '${sig.substring(0, 8)}...${sig.substring(sig.length - 8)}'
        : sig ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 48, color: BrandColors.success),
        const SizedBox(height: 16),
        const Text(
          'Confirmed',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (truncatedSig.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            truncatedSig,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: BrandColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFailed() {
    final errorMsg = widget.intent.errorMessage ?? 'Transaction failed';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48, color: BrandColors.error),
        const SizedBox(height: 16),
        Text(
          errorMsg,
          style: const TextStyle(fontSize: 14, color: BrandColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: widget.onRetry,
              child: const Text('Retry'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: widget.onDismiss,
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helper utilities
// ---------------------------------------------------------------------------

/// Truncate a wallet address: first 6 chars + "..." + last 4 chars.
String _truncateAddress(String address) {
  if (address.length <= 10) return address;
  return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
}
