import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/send.dart' show TxStatus;
import '../../models/swap.dart';
import '../../models/token.dart';
import '../../providers/balance_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/swap_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/token_registry.dart';
import '../../shared/formatters.dart';
import '../../theme/brand_theme.dart';
import '../lock/auth_challenge_dialog.dart';

class SwapScreen extends ConsumerStatefulWidget {
  const SwapScreen({super.key});

  @override
  ConsumerState<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends ConsumerState<SwapScreen> {
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(swapProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (swapState.step == SwapStep.configure) {
            context.pop();
          } else if (swapState.step != SwapStep.confirming) {
            ref.read(swapProvider.notifier).goBack();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Swap'),
            leading: swapState.step == SwapStep.confirming
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (swapState.step == SwapStep.configure) {
                        context.pop();
                      } else {
                        ref.read(swapProvider.notifier).goBack();
                      }
                    },
                  ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildStep(swapState),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(SwapState swapState) {
    switch (swapState.step) {
      case SwapStep.configure:
        return _ConfigureStep(
          key: const ValueKey('configure'),
          amountController: _amountController,
          amountFocus: _amountFocus,
        );
      case SwapStep.review:
        return const _ReviewStep(key: ValueKey('review'));
      case SwapStep.confirming:
        return const _ConfirmingStep(key: ValueKey('confirming'));
    }
  }
}

// ─── Configure Step ───

class _ConfigureStep extends ConsumerWidget {
  final TextEditingController amountController;
  final FocusNode amountFocus;

  const _ConfigureStep({
    super.key,
    required this.amountController,
    required this.amountFocus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swapState = ref.watch(swapProvider);
    final balanceAsync = ref.watch(balanceProvider);

    if (amountController.text != swapState.inputAmount) {
      amountController.text = swapState.inputAmount;
      amountController.selection =
          TextSelection.collapsed(offset: amountController.text.length);
    }

    final hasQuote = swapState.outputAmount != null;
    final canReview = hasQuote && !swapState.isQuoting;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          const Text('Swap',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Exchange tokens via Jupiter or DFlow.',
              style: TextStyle(color: BrandColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),

          // Aggregator toggle
          SegmentedButton<SwapAggregator>(
            segments: const [
              ButtonSegment(value: SwapAggregator.dflow, label: Text('DFlow')),
              ButtonSegment(value: SwapAggregator.jupiter, label: Text('Jupiter')),
            ],
            selected: {swapState.aggregator},
            onSelectionChanged: (selected) {
              ref.read(swapProvider.notifier).setAggregator(selected.first);
            },
          ),
          const SizedBox(height: 24),

          // Input token selector
          _tokenSelector(
            context, ref,
            label: 'From',
            selected: swapState.inputToken,
            balanceAsync: balanceAsync,
            onSelect: (tb) => ref.read(swapProvider.notifier).setInputToken(tb),
            isOutput: false,
          ),
          const SizedBox(height: 12),

          // Amount input
          TextField(
            controller: amountController,
            focusNode: amountFocus,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '0.0',
              hintStyle: const TextStyle(color: BrandColors.textSecondary),
              suffixText: swapState.inputToken?.definition.symbol ?? '',
              suffixIcon: TextButton(
                onPressed: () {
                  final input = swapState.inputToken;
                  if (input != null) {
                    final max = input.uiAmount.toString();
                    amountController.text = max;
                    ref.read(swapProvider.notifier).setInputAmount(max);
                  }
                },
                child: const Text('MAX',
                    style: TextStyle(color: BrandColors.primary)),
              ),
            ),
            onChanged: (value) {
              ref.read(swapProvider.notifier).setInputAmount(value);
            },
          ),
          const SizedBox(height: 12),

          // Flip button
          Center(
            child: IconButton(
              onPressed: () => ref.read(swapProvider.notifier).flipTokens(),
              icon: const Icon(Icons.swap_vert, color: BrandColors.primary),
            ),
          ),
          const SizedBox(height: 12),

          // Output token selector
          _tokenSelector(
            context, ref,
            label: 'To',
            selected: swapState.outputToken,
            balanceAsync: balanceAsync,
            onSelect: (tb) => ref.read(swapProvider.notifier).setOutputToken(tb),
            isOutput: true,
          ),
          const SizedBox(height: 16),

          // Quote display
          if (swapState.isQuoting)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (hasQuote && !swapState.isQuoting) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _infoRow('Output', _formatOutputAmount(swapState)),
                    if (swapState.priceImpact != null) ...[
                      const SizedBox(height: 8),
                      _infoRow('Price Impact',
                          '${swapState.priceImpact!.toStringAsFixed(4)}%'),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (swapState.quoteError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(swapState.quoteError!,
                  style: const TextStyle(color: BrandColors.error, fontSize: 13)),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: canReview
                ? () => ref.read(swapProvider.notifier).goToReview()
                : null,
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }

  String _formatOutputAmount(SwapState s) {
    final raw = s.outputAmount;
    if (raw == null) return '—';
    final output = s.outputToken;
    if (output != null) {
      final decimals = output.definition.decimals;
      final parsed = BigInt.tryParse(raw);
      if (parsed != null) {
        final ui = parsed.toDouble() / BigInt.from(10).pow(decimals).toDouble();
        return '${Formatters.formatTokenAmount(ui)} ${output.definition.symbol}';
      }
    }
    return raw;
  }

  Widget _tokenSelector(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required TokenBalance? selected,
    required AsyncValue<PortfolioState> balanceAsync,
    required void Function(TokenBalance) onSelect,
    required bool isOutput,
  }) {
    return InkWell(
      onTap: () {
        _showTokenPicker(context, ref, balanceAsync, onSelect,
            isOutput: isOutput);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: BrandColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BrandColors.border),
        ),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: BrandColors.textSecondary, fontSize: 13)),
            const Spacer(),
            if (selected != null)
              Text(selected.definition.symbol,
                  style: const TextStyle(fontWeight: FontWeight.w500))
            else
              const Text('Select token',
                  style: TextStyle(color: BrandColors.textSecondary)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: BrandColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showTokenPicker(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<PortfolioState> balanceAsync,
    void Function(TokenBalance) onSelect, {
    bool isOutput = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: BrandColors.surface,
      isScrollControlled: true,
      builder: (ctx) {
        return balanceAsync.when(
          loading: () => const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(
              height: 200, child: Center(child: Text('Error: $e'))),
          data: (portfolio) {
            // SOL as a synthetic TokenBalance
            final solDef = TokenDefinition(
              mint: 'So11111111111111111111111111111111111111112',
              name: 'Solana',
              symbol: 'SOL',
              decimals: 9,
            );
            final solBalance = TokenBalance(
              definition: solDef,
              rawAmount: portfolio.solBalance.toString(),
              uiAmount: portfolio.solBalance / 1e9,
            );
            final walletTokens = [solBalance, ...portfolio.tokenBalances];

            if (!isOutput) {
              // "From" picker: only wallet tokens
              return _TokenPickerList(
                tokens: walletTokens,
                onSelect: onSelect,
              );
            }

            // "To" picker: all verified tokens + unverified wallet tokens
            final registry = TokenRegistry.instance;
            final heldMints = walletTokens
                .map((tb) => tb.definition.mint)
                .toSet();

            // Verified tokens not held — show with 0 balance
            final verifiedNotHeld = registry.allTokens
                .where((def) => !heldMints.contains(def.mint))
                .map((def) => TokenBalance(
                      definition: def,
                      rawAmount: '0',
                      uiAmount: 0,
                    ))
                .toList();

            // Wallet tokens first (user has balance), then verified-not-held
            final allTokens = [...walletTokens, ...verifiedNotHeld];

            return _TokenPickerList(
              tokens: allTokens,
              onSelect: onSelect,
            );
          },
        );
      },
    );
  }

}

class _TokenPickerList extends StatefulWidget {
  final List<TokenBalance> tokens;
  final void Function(TokenBalance) onSelect;

  const _TokenPickerList({required this.tokens, required this.onSelect});

  @override
  State<_TokenPickerList> createState() => _TokenPickerListState();
}

class _TokenPickerListState extends State<_TokenPickerList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.tokens
        : widget.tokens.where((tb) {
            final q = _query.toLowerCase();
            return tb.definition.symbol.toLowerCase().contains(q) ||
                tb.definition.name.toLowerCase().contains(q);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search tokens',
                hintStyle: TextStyle(color: BrandColors.textSecondary),
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final tb = filtered[i];
                final hasBalance = tb.uiAmount > 0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: BrandColors.primary.withAlpha(30),
                    child: Text(
                      tb.definition.symbol.isNotEmpty
                          ? tb.definition.symbol.substring(0, 1)
                          : '?',
                      style: const TextStyle(
                          color: BrandColors.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(tb.definition.symbol),
                  subtitle: Text(tb.definition.name,
                      style: const TextStyle(
                          fontSize: 12, color: BrandColors.textSecondary)),
                  trailing: hasBalance
                      ? Text(Formatters.formatTokenAmount(tb.uiAmount),
                          style: const TextStyle(fontSize: 13))
                      : null,
                  onTap: () {
                    widget.onSelect(tb);
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Widget _infoRow(String label, String value) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label,
          style: const TextStyle(
              color: BrandColors.textSecondary, fontSize: 14)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
    ],
  );
}

// ─── Review Step ───

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swapState = ref.watch(swapProvider);
    final wallets = ref.watch(walletListProvider);
    final activeAddress = ref.watch(activeWalletProvider) ?? '';
    final activeWallet = wallets.whenOrNull(
      data: (list) =>
          list.where((w) => w.address == activeAddress).firstOrNull,
    );
    final isHardware = activeWallet?.source == 'hardware';

    final inputSymbol = swapState.inputToken?.definition.symbol ?? '';

    final isProcessing = swapState.txStatus == TxStatus.simulating ||
        swapState.txStatus == TxStatus.signing ||
        swapState.txStatus == TxStatus.submitting;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Review Swap',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _reviewRow('From', '${swapState.inputAmount} $inputSymbol'),
                  const Divider(height: 24),
                  _reviewRow('To', _formatOutputForReview(swapState)),
                  const Divider(height: 24),
                  _reviewRow('Aggregator',
                      swapState.aggregator == SwapAggregator.jupiter ? 'Jupiter' : 'DFlow'),
                  if (swapState.priceImpact != null) ...[
                    const Divider(height: 24),
                    _reviewRow('Price Impact',
                        '${swapState.priceImpact!.toStringAsFixed(4)}%'),
                  ],
                ],
              ),
            ),
          ),
          if (swapState.simulationSuccess) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.check_circle, BrandColors.success,
                'Simulation passed'),
          ],
          if (swapState.simulationError != null) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.error_outline, BrandColors.error,
                'Simulation failed: ${swapState.simulationError}'),
          ],
          if (swapState.errorMessage != null) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.error_outline, BrandColors.error,
                swapState.errorMessage!),
          ],
          if (isHardware && swapState.txStatus == TxStatus.signing) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.usb, BrandColors.warning,
                'Press the BOOT button on your hardware wallet to sign...'),
          ],
          // Guardrail violation banner
          if (swapState.guardrailViolation != null && !swapState.guardrailBypassed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: BrandColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BrandColors.error.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: BrandColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          swapState.guardrailViolation!,
                          style: const TextStyle(color: BrandColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: BrandColors.warning),
                      onPressed: () async {
                        final ok = await showAuthChallengeDialog(context);
                        if (ok) {
                          ref.read(swapProvider.notifier).bypassGuardrails();
                        }
                      },
                      child: const Text('Override with Password'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isProcessing
                      ? null
                      : () => ref.read(swapProvider.notifier).simulate(),
                  child: swapState.txStatus == TxStatus.simulating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simulate'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isProcessing || (swapState.guardrailViolation != null && !swapState.guardrailBypassed)
                      ? null
                      : () => ref.read(swapProvider.notifier).signAndSubmit(),
                  child: isProcessing && swapState.txStatus != TxStatus.simulating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Swap'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: BrandColors.textSecondary, fontSize: 14)),
        Flexible(
          child: Text(value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }

  String _formatOutputForReview(SwapState s) {
    final raw = s.outputAmount;
    if (raw == null) return '—';
    final output = s.outputToken;
    if (output != null) {
      final decimals = output.definition.decimals;
      final parsed = BigInt.tryParse(raw);
      if (parsed != null) {
        final ui = parsed.toDouble() / BigInt.from(10).pow(decimals).toDouble();
        return '${Formatters.formatTokenAmount(ui)} ${output.definition.symbol}';
      }
    }
    return raw;
  }

  Widget _statusBanner(IconData icon, Color color, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Confirming Step ───

class _ConfirmingStep extends ConsumerWidget {
  const _ConfirmingStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swapState = ref.watch(swapProvider);
    final network = ref.watch(networkProvider).network;
    final signature = swapState.txSignature ?? '';
    final status = swapState.confirmationStatus ?? 'submitted';
    final isConfirmed = swapState.txStatus == TxStatus.confirmed;
    final isFailed = swapState.txStatus == TxStatus.failed;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConfirmed
                ? Icons.check_circle
                : isFailed
                    ? Icons.error
                    : Icons.hourglass_top,
            size: 64,
            color: isConfirmed
                ? BrandColors.success
                : isFailed
                    ? BrandColors.error
                    : BrandColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            isConfirmed
                ? 'Swap Confirmed'
                : isFailed
                    ? 'Swap Failed'
                    : 'Confirming...',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _statusTracker(status, isConfirmed),
          const SizedBox(height: 24),
          if (swapState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(swapState.errorMessage!,
                style: const TextStyle(color: BrandColors.error, fontSize: 13),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          if (isConfirmed || isFailed)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (signature.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      launchUrl(
                        Uri.parse(_explorerUrl(network, signature)),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Text('View'),
                    label: const Icon(Icons.open_in_new, size: 16),
                  ),
                if (signature.isNotEmpty) const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    ref.read(swapProvider.notifier).reset();
                    context.go('/dashboard');
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _explorerUrl(SolanaNetwork network, String sig) {
    final suffix = network == SolanaNetwork.devnet ? '?cluster=devnet' : '';
    return 'https://orb.helius.dev/tx/$sig$suffix';
  }

  Widget _statusTracker(String status, bool isConfirmed) {
    final steps = ['submitted', 'confirmed', 'finalized'];
    final currentIndex = steps.indexOf(status).clamp(0, 2);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length, (i) {
        final isActive = i <= currentIndex;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              Container(
                width: 32, height: 2,
                color: isActive ? BrandColors.success : BrandColors.border,
              ),
            Column(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? BrandColors.success : BrandColors.border,
                  ),
                  alignment: Alignment.center,
                  child: isActive
                      ? const Icon(Icons.check, size: 14, color: Colors.black)
                      : Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i].substring(0, 1).toUpperCase() + steps[i].substring(1),
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? BrandColors.success : BrandColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
