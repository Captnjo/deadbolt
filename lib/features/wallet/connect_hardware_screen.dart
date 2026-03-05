import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/wallet_provider.dart';
import '../../shared/wallet_name_generator.dart';
import '../../src/rust/api/hardware.dart' as hw_bridge;
import '../../src/rust/api/hardware.dart' show DetectedPortDto;
import '../../theme/brand_theme.dart';

class ConnectHardwareScreen extends ConsumerStatefulWidget {
  const ConnectHardwareScreen({super.key});

  @override
  ConsumerState<ConnectHardwareScreen> createState() =>
      _ConnectHardwareScreenState();
}

class _ConnectHardwareScreenState
    extends ConsumerState<ConnectHardwareScreen> {
  final _nameController = TextEditingController(text: generateWalletName());
  List<DetectedPortDto> _ports = [];
  DetectedPortDto? _selected;
  Timer? _timer;
  bool _scanning = false;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _scan());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      final ports = await hw_bridge.scanHardwareWallets();
      if (mounted) setState(() => _ports = ports);
    } catch (_) {}
    _scanning = false;
  }

  Future<void> _connect() async {
    if (_selected == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a wallet name');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      await hw_bridge.connectHardwareWallet(
        portPath: _selected!.path,
        name: name,
      );
      ref.invalidate(walletListProvider);
      if (mounted) context.go('/wallets');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Hardware Wallet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/wallets'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Wallet Name',
                    hintText: 'e.g. Hardware Wallet',
                  ),
                ),
                const SizedBox(height: 24),
                if (_ports.isEmpty) ...[
                  const Icon(Icons.usb_outlined, size: 48, color: Colors.white12),
                  const SizedBox(height: 12),
                  const Text(
                    'Plug in your Unruggable signer via USB',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: BrandColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ] else ...[
                  for (final port in _ports)
                    Card(
                      color: _selected?.path == port.path
                          ? BrandColors.primary.withAlpha(15)
                          : null,
                      child: ListTile(
                        leading: const Icon(Icons.usb, color: BrandColors.primary),
                        title: Text(
                          port.product.isNotEmpty ? port.product : 'USB Device',
                        ),
                        subtitle: Text(
                          port.path,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: BrandColors.textSecondary,
                          ),
                        ),
                        trailing: _selected?.path == port.path
                            ? const Icon(Icons.check_circle, color: BrandColors.primary)
                            : null,
                        onTap: () => setState(() => _selected = port),
                      ),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: BrandColors.error)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed:
                      _selected != null && !_connecting ? _connect : null,
                  child: _connecting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
