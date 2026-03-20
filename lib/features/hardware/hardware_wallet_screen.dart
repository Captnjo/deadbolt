import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/hardware_connection_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../src/rust/api/hardware.dart' as hw_bridge;
import '../../src/rust/api/hardware_stubs.dart' as hw_stubs;
import '../../features/lock/auth_challenge_dialog.dart';
import '../../theme/brand_theme.dart';

class HardwareWalletScreen extends ConsumerStatefulWidget {
  const HardwareWalletScreen({super.key});

  @override
  ConsumerState<HardwareWalletScreen> createState() =>
      _HardwareWalletScreenState();
}

class _HardwareWalletScreenState extends ConsumerState<HardwareWalletScreen> {
  bool _generating = false;
  bool _resetting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final hwConnAsync = ref.watch(hardwareConnectionProvider);
    final hwConn =
        hwConnAsync.valueOrNull ?? const HwConnectionInfo.notPaired();

    return Scaffold(
      appBar: AppBar(title: const Text('Hardware Wallet')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._buildContent(hwConn),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: BrandColors.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(HwConnectionInfo hwConn) {
    switch (hwConn.state) {
      case HwConnState.notPaired:
        return _buildNotPaired();
      case HwConnState.disconnected:
        return _buildDisconnected(hwConn);
      case HwConnState.connected:
        return _buildConnected(hwConn);
      case HwConnState.pubkeyMismatch:
        return _buildPubkeyMismatch(hwConn);
    }
  }

  List<Widget> _buildNotPaired() {
    return [
      const Center(
        child: Icon(Icons.usb_outlined,
            size: 48, color: BrandColors.textSecondary),
      ),
      const SizedBox(height: 16),
      const Text(
        'No Hardware Wallet',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      const Text(
        'Plug in your Unruggable signer and tap Connect to pair it.',
        style: TextStyle(color: BrandColors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Center(
        child: ElevatedButton(
          onPressed: () => context.go('/wallets/hardware'),
          child: const Text('Connect Device'),
        ),
      ),
    ];
  }

  List<Widget> _buildDisconnected(HwConnectionInfo hwConn) {
    return [
      _buildDeviceInfoCard(hwConn, connected: false),
      const SizedBox(height: 16),
      Row(
        children: [
          OutlinedButton(
            child: const Text('Reconnect'),
            onPressed: () => ref.invalidate(hardwareConnectionProvider),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: BrandColors.error),
            child: const Text('Factory Reset'),
            onPressed: _resetting ? null : _handleFactoryReset,
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildConnected(HwConnectionInfo hwConn) {
    return [
      _buildDeviceInfoCard(hwConn, connected: true),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          ElevatedButton(
            onPressed: _generating ? null : _handleGenerate,
            child: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Generate New Keypair'),
          ),
          OutlinedButton(
            child: const Text('Disconnect Device'),
            onPressed: _handleDisconnect,
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: BrandColors.error),
            child: const Text('Factory Reset'),
            onPressed: _resetting ? null : _handleFactoryReset,
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildPubkeyMismatch(HwConnectionInfo hwConn) {
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BrandColors.error.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BrandColors.error.withAlpha(60)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                color: BrandColors.error, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Device mismatch \u2014 this hardware wallet\'s public key does not match the registered wallet address. Signing is blocked until resolved.',
                style: TextStyle(
                    color: BrandColors.error, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildDeviceInfoCard(hwConn, connected: true),
      const SizedBox(height: 16),
      Row(
        children: [
          ElevatedButton(
            child: const Text('Re-register Device'),
            onPressed: _handleReregister,
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            child: const Text('Disconnect Device'),
            onPressed: _handleDisconnect,
          ),
        ],
      ),
    ];
  }

  Widget _buildDeviceInfoCard(HwConnectionInfo hwConn,
      {required bool connected}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  hwConn.deviceName ?? 'Hardware Wallet',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (connected) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: BrandColors.success,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Connected',
                      style: TextStyle(
                          color: BrandColors.success, fontSize: 12)),
                ] else ...[
                  const Text('Disconnected',
                      style: TextStyle(
                          color: BrandColors.textSecondary, fontSize: 12)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (hwConn.address != null)
              Text(
                hwConn.address!,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: BrandColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGenerate() async {
    final hwConn = ref.read(hardwareConnectionProvider).valueOrNull;
    if (hwConn?.portPath == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final words =
          await hw_stubs.generateHardwareKeypair(portPath: hwConn!.portPath!);
      if (mounted) {
        context.go('/hardware/mnemonic', extra: words);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _generating = false;
        });
      }
    }
  }

  Future<void> _handleFactoryReset() async {
    // Step 1: Auth challenge
    if (!mounted) return;
    final authed = await showAuthChallengeDialog(context);
    if (!authed || !mounted) return;

    // Step 2: Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factory Reset Hardware Wallet'),
        content: const Text(
            'This will permanently erase the device\'s private key. Hold the BOOT button for 5 seconds when prompted to confirm.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Device'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BrandColors.error),
            child: const Text('Reset Device'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Step 3: Send reset command
    final hwConn = ref.read(hardwareConnectionProvider).valueOrNull;
    if (hwConn?.portPath == null) return;
    setState(() {
      _resetting = true;
      _error = null;
    });
    try {
      await hw_stubs.factoryResetHardware(portPath: hwConn!.portPath!);
      // Remove hardware wallet from wallet list
      final wallets = ref.read(walletListProvider).valueOrNull ?? [];
      final hwWallet =
          wallets.where((w) => w.source == 'hardware').firstOrNull;
      if (hwWallet != null) {
        await ref
            .read(walletListProvider.notifier)
            .removeWallet(hwWallet.address);
      }
      ref.invalidate(hardwareConnectionProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Hardware wallet reset. Device unpaired.')),
        );
        setState(() => _resetting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _resetting = false;
        });
      }
    }
  }

  void _handleDisconnect() {
    final wallets = ref.read(walletListProvider).valueOrNull ?? [];
    final hwWallet =
        wallets.where((w) => w.source == 'hardware').firstOrNull;
    if (hwWallet != null) {
      ref.read(walletListProvider.notifier).removeWallet(hwWallet.address);
    }
    ref.invalidate(hardwareConnectionProvider);
  }

  Future<void> _handleReregister() async {
    if (!mounted) return;
    final authed = await showAuthChallengeDialog(context);
    if (!authed || !mounted) return;

    final hwConn = ref.read(hardwareConnectionProvider).valueOrNull;
    if (hwConn?.portPath == null) return;

    setState(() => _error = null);
    try {
      // Get the device's actual current address (confirms device responds before de-registering)
      await hw_stubs.getHardwarePubkey(portPath: hwConn!.portPath!);
      // Remove old registration
      final wallets = ref.read(walletListProvider).valueOrNull ?? [];
      final hwWallet =
          wallets.where((w) => w.source == 'hardware').firstOrNull;
      if (hwWallet != null) {
        await ref
            .read(walletListProvider.notifier)
            .removeWallet(hwWallet.address);
      }
      // Re-register with new address — use connect flow which registers in config
      await hw_bridge.connectHardwareWallet(
        portPath: hwConn.portPath!,
        name: hwConn.deviceName ?? 'Hardware Wallet',
      );
      ref.invalidate(walletListProvider);
      ref.invalidate(hardwareConnectionProvider);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }
}
