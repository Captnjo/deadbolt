import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/send.dart';
import '../../models/token.dart';
import '../../providers/address_book_provider.dart';
import '../../providers/api_keys_provider.dart';
import '../../providers/balance_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/send_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../shared/formatters.dart';
import '../../shared/validators.dart';
import '../../theme/brand_theme.dart';
import '../lock/auth_challenge_dialog.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _recipientFocus = FocusNode();
  final _amountFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Reset send state when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sendProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _recipientFocus.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sendState = ref.watch(sendProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (sendState.step == SendStep.recipient) {
            context.pop();
          } else if (sendState.step != SendStep.confirming) {
            ref.read(sendProvider.notifier).goBack();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Send'),
            leading: sendState.step == SendStep.confirming
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (sendState.step == SendStep.recipient) {
                        context.pop();
                      } else {
                        ref.read(sendProvider.notifier).goBack();
                      }
                    },
                  ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildStep(sendState),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(SendState sendState) {
    switch (sendState.step) {
      case SendStep.recipient:
        return _RecipientStep(
          key: const ValueKey('recipient'),
          controller: _recipientController,
          focusNode: _recipientFocus,
        );
      case SendStep.asset:
        return const _AssetStep(key: ValueKey('asset'));
      case SendStep.amount:
        return _AmountStep(
          key: const ValueKey('amount'),
          controller: _amountController,
          focusNode: _amountFocus,
        );
      case SendStep.review:
        return const _ReviewStep(key: ValueKey('review'));
      case SendStep.confirming:
        return const _ConfirmingStep(key: ValueKey('confirming'));
    }
  }
}

// ─── Step 1: Recipient ───

class _RecipientStep extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _RecipientStep({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendState = ref.watch(sendProvider);
    final address = sendState.recipient;
    final isValid = address.isEmpty || isValidSolanaAddress(address);
    final canProceed = address.isNotEmpty && isValidSolanaAddress(address);

    final contacts = ref.watch(addressBookProvider);
    final wallets = ref.watch(walletListProvider).valueOrNull ?? [];
    final q = address.toLowerCase();

    // Filter wallets and contacts — show all when field is empty (focused)
    final filteredWallets = address.isEmpty
        ? wallets
        : wallets.where((w) {
            return w.name.toLowerCase().contains(q) ||
                w.address.toLowerCase().startsWith(q);
          }).toList();
    final filteredContacts = address.isEmpty
        ? contacts
        : contacts.where((c) {
            return c.tag.toLowerCase().contains(q) ||
                c.address.toLowerCase().startsWith(q);
          }).toList();

    final showDropdown =
        !canProceed && (filteredWallets.isNotEmpty || filteredContacts.isNotEmpty);

    // Sync controller with state
    if (controller.text != address) {
      controller.text = address;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Recipient',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Enter the Solana address to send to.',
              style: TextStyle(color: BrandColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Solana address or contact name',
              hintStyle: const TextStyle(color: BrandColors.textSecondary),
              errorText: !isValid ? 'Invalid Solana address' : null,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (address.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        controller.clear();
                        ref.read(sendProvider.notifier).setRecipient('');
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.paste, size: 18),
                    tooltip: 'Paste',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        controller.text = data!.text!.trim();
                        ref
                            .read(sendProvider.notifier)
                            .setRecipient(data.text!.trim());
                      }
                    },
                  ),
                ],
              ),
            ),
            onChanged: (value) {
              ref.read(sendProvider.notifier).setRecipient(value.trim());
            },
            onSubmitted: (_) {
              if (canProceed) {
                ref.read(sendProvider.notifier).goToAssetStep();
              }
            },
          ),
          if (showDropdown) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (filteredWallets.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text('Your Wallets',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: BrandColors.textSecondary)),
                      ),
                      ...filteredWallets.map((w) => ListTile(
                            dense: true,
                            leading: const Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 18),
                            title: Text(w.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text(
                              Formatters.shortAddress(w.address),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: BrandColors.textSecondary),
                            ),
                            onTap: () {
                              controller.text = w.address;
                              ref
                                  .read(sendProvider.notifier)
                                  .setRecipient(w.address);
                            },
                          )),
                    ],
                    if (filteredContacts.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text('Contacts',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: BrandColors.textSecondary)),
                      ),
                      ...filteredContacts.map((c) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.person, size: 18),
                            title: Text(c.tag,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            subtitle: Text(
                              Formatters.shortAddress(c.address),
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: BrandColors.textSecondary),
                            ),
                            onTap: () {
                              controller.text = c.address;
                              ref
                                  .read(sendProvider.notifier)
                                  .setRecipient(c.address);
                            },
                          )),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: canProceed
                ? () => ref.read(sendProvider.notifier).goToAssetStep()
                : null,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

// ─── Step 2: Asset Selection ───

class _AssetStep extends ConsumerWidget {
  const _AssetStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(balanceProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Select Asset',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Choose what to send.',
              style: TextStyle(color: BrandColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          Expanded(
            child: balanceAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error: $err')),
              data: (portfolio) => _assetList(context, ref, portfolio),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assetList(
      BuildContext context, WidgetRef ref, PortfolioState portfolio) {
    final currency = ref.watch(
        apiKeysProvider.select((s) => s.displayCurrency));
    final rate = portfolio.exchangeRate;
    return ListView(
      children: [
        // SOL
        _assetTile(
          ref: ref,
          icon: Icons.currency_exchange,
          symbol: 'SOL',
          name: 'Solana',
          balance: Formatters.formatSol(portfolio.solBalance),
          usdValue: portfolio.solPrice > 0
              ? Formatters.formatCurrency(
                  portfolio.solUsdValue * rate, currency)
              : null,
          onTap: () => ref.read(sendProvider.notifier).selectAsset(
                SendSol(lamportsBalance: portfolio.solBalance),
              ),
        ),
        // SPL tokens
        ...portfolio.tokenBalances.map((tb) => _assetTile(
              ref: ref,
              icon: Icons.token,
              symbol: tb.definition.symbol,
              name: tb.definition.name,
              balance: Formatters.formatTokenAmount(tb.uiAmount),
              usdValue: tb.usdValue != null
                  ? Formatters.formatCurrency(
                      tb.usdValue! * rate, currency)
                  : null,
              onTap: () => ref
                  .read(sendProvider.notifier)
                  .selectAsset(SendToken(tokenBalance: tb)),
            )),
      ],
    );
  }

  Widget _assetTile({
    required WidgetRef ref,
    required IconData icon,
    required String symbol,
    required String name,
    required String balance,
    String? usdValue,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: BrandColors.primary.withAlpha(30),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(symbol.substring(0, 1),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: BrandColors.primary)),
        ),
        title: Text(symbol),
        subtitle: Text(name,
            style: const TextStyle(
                fontSize: 12, color: BrandColors.textSecondary)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(balance,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            if (usdValue != null)
              Text(usdValue,
                  style: const TextStyle(
                      fontSize: 12, color: BrandColors.textSecondary)),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ─── Step 3: Amount ───

class _AmountStep extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _AmountStep({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendState = ref.watch(sendProvider);
    final asset = sendState.asset;
    if (asset == null) return const SizedBox.shrink();

    final network = ref.watch(networkProvider).network;
    final balanceAsync = ref.watch(balanceProvider);
    final solPrice = balanceAsync.valueOrNull?.solPrice ?? 0;

    final String assetSymbol;
    final String availableBalance;
    if (asset is SendSol) {
      assetSymbol = 'SOL';
      availableBalance = Formatters.formatSol(asset.lamportsBalance);
    } else if (asset is SendToken) {
      assetSymbol = asset.tokenBalance.definition.symbol;
      availableBalance =
          Formatters.formatTokenAmount(asset.tokenBalance.uiAmount);
    } else {
      assetSymbol = '';
      availableBalance = '0';
    }

    // Sync controller
    if (controller.text != sendState.amountText) {
      controller.text = sendState.amountText;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
    }

    final amount = double.tryParse(sendState.amountText) ?? 0;
    final hasAmount = amount > 0;
    final exceedsBalance = sendState.amountExceedsBalance;

    // Value estimate in display currency
    final currency = ref.watch(
        apiKeysProvider.select((s) => s.displayCurrency));
    final exchangeRate = balanceAsync.valueOrNull?.exchangeRate ?? 1.0;
    String? valueEstimate;
    if (network == SolanaNetwork.mainnet && asset is SendSol && solPrice > 0) {
      valueEstimate = Formatters.formatCurrency(
          amount * solPrice * exchangeRate, currency);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Send $assetSymbol',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Available: $availableBalance $assetSymbol',
              style: const TextStyle(
                  color: BrandColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '0.0',
              hintStyle: const TextStyle(color: BrandColors.textSecondary),
              suffixText: assetSymbol,
              errorText: exceedsBalance ? 'Insufficient balance' : null,
              suffixIcon: TextButton(
                onPressed: () {
                  final maxAmount = _computeMax(asset);
                  controller.text = maxAmount;
                  ref.read(sendProvider.notifier).setAmount(maxAmount);
                },
                child: const Text('MAX',
                    style: TextStyle(color: BrandColors.primary)),
              ),
            ),
            onChanged: (value) {
              ref.read(sendProvider.notifier).setAmount(value);
            },
            onSubmitted: (_) {
              if (hasAmount && !exceedsBalance) {
                ref.read(sendProvider.notifier).goToReview();
              }
            },
          ),
          if (valueEstimate != null) ...[
            const SizedBox(height: 8),
            Text(valueEstimate,
                style: const TextStyle(
                    color: BrandColors.textSecondary, fontSize: 14)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: hasAmount && !exceedsBalance
                ? () => ref.read(sendProvider.notifier).goToReview()
                : null,
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }

  String _computeMax(SendAsset asset) {
    if (asset is SendSol) {
      // Reserve ~0.005 SOL for fees
      final reserved = 5000000; // 0.005 SOL in lamports
      final max = asset.lamportsBalance - reserved;
      if (max <= 0) return '0';
      return (max / 1e9).toStringAsFixed(9).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    } else if (asset is SendToken) {
      return asset.tokenBalance.uiAmount.toStringAsFixed(
          asset.tokenBalance.definition.decimals);
    }
    return '0';
  }
}

// ─── Step 4: Review ───

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendState = ref.watch(sendProvider);
    final wallets = ref.watch(walletListProvider);
    final activeAddress = ref.watch(activeWalletProvider) ?? '';
    final activeWallet = wallets.whenOrNull(
      data: (list) =>
          list.where((w) => w.address == activeAddress).firstOrNull,
    );
    final walletName = activeWallet?.name;
    final isHardware = activeWallet?.source == 'hardware';

    final asset = sendState.asset;
    final String assetSymbol;
    if (asset is SendSol) {
      assetSymbol = 'SOL';
    } else if (asset is SendToken) {
      assetSymbol = asset.tokenBalance.definition.symbol;
    } else {
      assetSymbol = '';
    }

    final isProcessing = sendState.txStatus == TxStatus.simulating ||
        sendState.txStatus == TxStatus.signing ||
        sendState.txStatus == TxStatus.submitting;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Review Transaction',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _reviewRow('From', walletName ?? Formatters.shortAddress(activeAddress)),
                  const Divider(height: 24),
                  _reviewRow('To', Formatters.shortAddress(sendState.recipient)),
                  const Divider(height: 24),
                  _reviewRow('Amount', '${sendState.amountText} $assetSymbol'),
                  const Divider(height: 24),
                  _reviewRow('Network Fee', '~0.000005 SOL'),
                ],
              ),
            ),
          ),
          // Simulation result
          if (sendState.simulationSuccess) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BrandColors.success.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BrandColors.success.withAlpha(60)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: BrandColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Simulation passed (${sendState.simulationUnitsConsumed} CU)',
                    style: const TextStyle(color: BrandColors.success, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
          if (sendState.simulationError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BrandColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BrandColors.error.withAlpha(60)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: BrandColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Simulation failed: ${sendState.simulationError}',
                      style: const TextStyle(color: BrandColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Error from signing/submission
          if (sendState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BrandColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BrandColors.error.withAlpha(60)),
              ),
              child: Text(
                sendState.errorMessage!,
                style: const TextStyle(color: BrandColors.error, fontSize: 13),
              ),
            ),
          ],
          // Hardware wallet notice
          if (isHardware && sendState.txStatus == TxStatus.signing) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BrandColors.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BrandColors.warning.withAlpha(60)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.usb, color: BrandColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Press the BOOT button on your hardware wallet to sign...',
                      style: TextStyle(color: BrandColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Guardrail violation banner
          if (sendState.guardrailViolation != null && !sendState.guardrailBypassed) ...[
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
                          sendState.guardrailViolation!,
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
                          ref.read(sendProvider.notifier).bypassGuardrails();
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
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isProcessing
                      ? null
                      : () => ref.read(sendProvider.notifier).simulate(),
                  child: sendState.txStatus == TxStatus.simulating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simulate'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isProcessing || (sendState.guardrailViolation != null && !sendState.guardrailBypassed)
                      ? null
                      : () => ref.read(sendProvider.notifier).signAndSubmit(),
                  child: isProcessing && sendState.txStatus != TxStatus.simulating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Send'),
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
}

// ─── Step 5: Confirming ───

class _ConfirmingStep extends ConsumerWidget {
  const _ConfirmingStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendState = ref.watch(sendProvider);
    final network = ref.watch(networkProvider).network;
    final signature = sendState.txSignature ?? '';
    final status = sendState.confirmationStatus ?? 'submitted';
    final isConfirmed = sendState.txStatus == TxStatus.confirmed;
    final isFailed = sendState.txStatus == TxStatus.failed;

    final suffix = network == SolanaNetwork.devnet ? '?cluster=devnet' : '';
    final explorerUrl = 'https://orb.helius.dev/tx/$signature$suffix';

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
                ? 'Transaction Confirmed'
                : isFailed
                    ? 'Transaction Failed'
                    : 'Confirming...',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          // Status tracker
          _statusTracker(status, isConfirmed),
          const SizedBox(height: 24),
          // Signature
          if (signature.isNotEmpty) ...[
            const Text('Signature',
                style: TextStyle(
                    color: BrandColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: SelectableText(
                    Formatters.shortAddress(signature),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: signature));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Signature copied'),
                          duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          ],
          // Explorer link
          if (signature.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              explorerUrl,
              style: const TextStyle(
                  fontSize: 11,
                  color: BrandColors.primary,
                  fontFamily: 'monospace'),
            ),
          ],
          if (sendState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(sendState.errorMessage!,
                style: const TextStyle(color: BrandColors.error, fontSize: 13),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          // Done button
          if (isConfirmed || isFailed)
            ElevatedButton(
              onPressed: () {
                ref.read(sendProvider.notifier).reset();
                context.go('/dashboard');
              },
              child: const Text('Done'),
            ),
        ],
      ),
    );
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
                width: 32,
                height: 2,
                color: isActive
                    ? BrandColors.success
                    : BrandColors.border,
              ),
            Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? BrandColors.success
                        : BrandColors.border,
                  ),
                  alignment: Alignment.center,
                  child: isActive
                      ? const Icon(Icons.check, size: 14, color: Colors.black)
                      : Text('${i + 1}',
                          style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i].substring(0, 1).toUpperCase() +
                      steps[i].substring(1),
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive
                        ? BrandColors.success
                        : BrandColors.textSecondary,
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
