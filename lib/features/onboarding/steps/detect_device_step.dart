import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../src/rust/api/hardware.dart' as hw_bridge;
import '../../../src/rust/api/hardware.dart' show DetectedPortDto;
import '../../../theme/brand_theme.dart';

class DetectDeviceStep extends ConsumerStatefulWidget {
  const DetectDeviceStep({super.key});

  @override
  ConsumerState<DetectDeviceStep> createState() => _DetectDeviceStepState();
}

class _DetectDeviceStepState extends ConsumerState<DetectDeviceStep> {
  List<DetectedPortDto> _ports = [];
  Timer? _timer;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scan();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _scan());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      final ports = await hw_bridge.scanHardwareWallets();
      if (mounted) setState(() => _ports = ports);
    } catch (_) {
      // Silently retry on next tick
    }
    _scanning = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingStateProvider);
    final notifier = ref.read(onboardingStateProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Connect Hardware Wallet',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Plug in your Unruggable signer via USB.',
            style: TextStyle(color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 32),
          if (_ports.isEmpty) ...[
            const Icon(Icons.usb_outlined, size: 64, color: Colors.white12),
            const SizedBox(height: 16),
            const Text(
              'Scanning for devices...',
              textAlign: TextAlign.center,
              style: TextStyle(color: BrandColors.textSecondary),
            ),
            const SizedBox(height: 8),
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ] else ...[
            for (final port in _ports)
              Card(
                color: state.detectedDevice?.path == port.path
                    ? BrandColors.primary.withAlpha(15)
                    : null,
                child: ListTile(
                  leading: const Icon(Icons.usb, color: BrandColors.primary),
                  title: Text(
                    port.product.isNotEmpty ? port.product : 'USB Device',
                  ),
                  subtitle: Text(
                    '${port.path} (${port.vid.toRadixString(16)}:${port.pid.toRadixString(16)})',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: BrandColors.textSecondary,
                    ),
                  ),
                  trailing: state.detectedDevice?.path == port.path
                      ? const Icon(Icons.check_circle, color: BrandColors.primary)
                      : null,
                  onTap: () => notifier.selectDevice(port),
                ),
              ),
          ],
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: state.detectedDevice != null ? notifier.advanceFromDetect : null,
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}
