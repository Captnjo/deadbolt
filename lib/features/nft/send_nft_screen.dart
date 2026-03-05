import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/nft.dart';
import '../../models/send.dart' show TxStatus;
import '../../models/token.dart';
import '../../providers/network_provider.dart';
import '../../providers/nft_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../shared/formatters.dart';
import '../../shared/validators.dart';
import '../../theme/brand_theme.dart';

class SendNftScreen extends ConsumerStatefulWidget {
  const SendNftScreen({super.key});

  @override
  ConsumerState<SendNftScreen> createState() => _SendNftScreenState();
}

class _SendNftScreenState extends ConsumerState<SendNftScreen> {
  final _recipientController = TextEditingController();
  final _recipientFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(nftProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _recipientFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nftState = ref.watch(nftProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (nftState.step == SendNftStep.selectNft) {
            context.pop();
          } else if (nftState.step != SendNftStep.confirming) {
            ref.read(nftProvider.notifier).goBack();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Send NFT'),
            leading: nftState.step == SendNftStep.confirming
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (nftState.step == SendNftStep.selectNft) {
                        context.pop();
                      } else {
                        ref.read(nftProvider.notifier).goBack();
                      }
                    },
                  ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _buildStep(nftState),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(SendNftState nftState) {
    switch (nftState.step) {
      case SendNftStep.selectNft:
        return _SelectNftStep(key: const ValueKey('selectNft'));
      case SendNftStep.recipient:
        return _RecipientStep(
          key: const ValueKey('recipient'),
          controller: _recipientController,
          focusNode: _recipientFocus,
        );
      case SendNftStep.review:
        return const _ReviewStep(key: ValueKey('review'));
      case SendNftStep.confirming:
        return const _ConfirmingStep(key: ValueKey('confirming'));
    }
  }
}

// ─── Select NFT Step ───

class _SelectNftStep extends ConsumerWidget {
  const _SelectNftStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nftState = ref.watch(nftProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Select NFT',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Choose an NFT to send.',
              style: TextStyle(color: BrandColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          if (nftState.isLoadingNfts)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (nftState.nftLoadError != null)
            Expanded(
              child: Center(
                child: Text(nftState.nftLoadError!,
                    style: const TextStyle(
                        color: BrandColors.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center),
              ),
            )
          else if (nftState.nfts.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No NFTs found',
                    style: TextStyle(
                        color: BrandColors.textSecondary, fontSize: 14)),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: nftState.nfts.length,
                itemBuilder: (ctx, i) {
                  final nft = nftState.nfts[i];
                  return _nftCard(ref, nft);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _nftCard(WidgetRef ref, NftAsset nft) {
    return InkWell(
      onTap: () => ref.read(nftProvider.notifier).selectNft(nft),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: nft.imageUrl != null
                  ? Image.network(
                      nft.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, st) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                nft.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: BrandColors.card,
      alignment: Alignment.center,
      child: const Icon(Icons.image, color: BrandColors.textSecondary, size: 32),
    );
  }
}

// ─── Recipient Step ───

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
    final nftState = ref.watch(nftProvider);
    final address = nftState.recipient;
    final isValid = address.isEmpty || isValidSolanaAddress(address);
    final canProceed = address.isNotEmpty && isValidSolanaAddress(address);

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
          Text('Sending: ${nftState.selectedNft?.name ?? ''}',
              style: const TextStyle(
                  color: BrandColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Solana address (Base58)',
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
                        ref.read(nftProvider.notifier).setRecipient('');
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
                            .read(nftProvider.notifier)
                            .setRecipient(data.text!.trim());
                      }
                    },
                  ),
                ],
              ),
            ),
            onChanged: (value) {
              ref.read(nftProvider.notifier).setRecipient(value.trim());
            },
            onSubmitted: (_) {
              if (canProceed) {
                ref.read(nftProvider.notifier).goToReview();
              }
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: canProceed
                ? () => ref.read(nftProvider.notifier).goToReview()
                : null,
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }
}

// ─── Review Step ───

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nftState = ref.watch(nftProvider);
    final wallets = ref.watch(walletListProvider);
    final activeAddress = ref.watch(activeWalletProvider) ?? '';
    final activeWallet = wallets.whenOrNull(
      data: (list) =>
          list.where((w) => w.address == activeAddress).firstOrNull,
    );
    final isHardware = activeWallet?.source == 'hardware';

    final isProcessing = nftState.txStatus == TxStatus.simulating ||
        nftState.txStatus == TxStatus.signing ||
        nftState.txStatus == TxStatus.submitting;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Review NFT Transfer',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          // NFT preview
          if (nftState.selectedNft?.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                nftState.selectedNft!.imageUrl!,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (_, e, st) => const SizedBox.shrink(),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _reviewRow('NFT', nftState.selectedNft?.name ?? ''),
                  const Divider(height: 24),
                  _reviewRow('To',
                      Formatters.shortAddress(nftState.recipient)),
                  const Divider(height: 24),
                  _reviewRow('Network Fee', '~0.000005 SOL'),
                ],
              ),
            ),
          ),
          if (nftState.simulationSuccess) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.check_circle, BrandColors.success,
                'Simulation passed'),
          ],
          if (nftState.simulationError != null) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.error_outline, BrandColors.error,
                'Simulation failed: ${nftState.simulationError}'),
          ],
          if (nftState.errorMessage != null) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.error_outline, BrandColors.error,
                nftState.errorMessage!),
          ],
          if (isHardware && nftState.txStatus == TxStatus.signing) ...[
            const SizedBox(height: 12),
            _statusBanner(Icons.usb, BrandColors.warning,
                'Press the BOOT button on your hardware wallet to sign...'),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isProcessing
                      ? null
                      : () => ref.read(nftProvider.notifier).simulate(),
                  child: nftState.txStatus == TxStatus.simulating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simulate'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () => ref.read(nftProvider.notifier).signAndSubmit(),
                  child: isProcessing && nftState.txStatus != TxStatus.simulating
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
    final nftState = ref.watch(nftProvider);
    final network = ref.watch(networkProvider).network;
    final signature = nftState.txSignature ?? '';
    final status = nftState.confirmationStatus ?? 'submitted';
    final isConfirmed = nftState.txStatus == TxStatus.confirmed;
    final isFailed = nftState.txStatus == TxStatus.failed;

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
                ? 'NFT Sent'
                : isFailed
                    ? 'Transfer Failed'
                    : 'Confirming...',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _statusTracker(status, isConfirmed),
          const SizedBox(height: 24),
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
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
            const SizedBox(height: 8),
            SelectableText(
              _explorerUrl(network, signature),
              style: const TextStyle(
                  fontSize: 11,
                  color: BrandColors.primary,
                  fontFamily: 'monospace'),
            ),
          ],
          if (nftState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(nftState.errorMessage!,
                style: const TextStyle(color: BrandColors.error, fontSize: 13),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          if (isConfirmed || isFailed)
            ElevatedButton(
              onPressed: () {
                ref.read(nftProvider.notifier).reset();
                context.go('/dashboard');
              },
              child: const Text('Done'),
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
