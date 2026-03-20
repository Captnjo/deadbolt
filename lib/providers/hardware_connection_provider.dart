import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/hardware.dart' as hw_bridge;
import '../src/rust/api/hardware_stubs.dart' as hw_stubs;
import 'wallet_provider.dart';

/// Connection state for the paired hardware wallet.
enum HwConnState {
  notPaired,       // No hardware wallet registered in wallet list
  disconnected,    // Hardware wallet registered but device not detected on USB
  connected,       // Device detected and pubkey matches registered address
  pubkeyMismatch,  // Device detected but pubkey does NOT match registered address
}

/// Immutable snapshot of the hardware wallet connection at a point in time.
class HwConnectionInfo {
  final HwConnState state;
  final String? deviceName;   // Registered wallet name (null if notPaired)
  final String? address;      // Registered wallet address (null if notPaired)
  final String? portPath;     // Serial port path when connected (null if disconnected/notPaired)

  const HwConnectionInfo({
    required this.state,
    this.deviceName,
    this.address,
    this.portPath,
  });

  const HwConnectionInfo.notPaired()
      : state = HwConnState.notPaired,
        deviceName = null,
        address = null,
        portPath = null;
}

/// Polls for hardware wallet connection status every 5 seconds.
///
/// Emits [HwConnectionInfo] with one of four states:
/// - [HwConnState.notPaired]      — no hardware wallet registered
/// - [HwConnState.disconnected]   — registered but no device detected on USB
/// - [HwConnState.connected]      — device found and pubkey matches
/// - [HwConnState.pubkeyMismatch] — device found but pubkey does not match
final hardwareConnectionProvider =
    StreamProvider.autoDispose<HwConnectionInfo>((ref) async* {
  // Initial check immediately on subscription
  yield await _checkConnection(ref);
  // Then poll every 5 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
    yield await _checkConnection(ref);
  }
});

Future<HwConnectionInfo> _checkConnection(
    AutoDisposeStreamProviderRef<HwConnectionInfo> ref) async {
  // Step 1: Find registered hardware wallet in wallet list
  final wallets = ref.read(walletListProvider).valueOrNull ?? [];
  final hwWallet = wallets.where((w) => w.source == 'hardware').firstOrNull;

  if (hwWallet == null) {
    return const HwConnectionInfo.notPaired();
  }

  // Step 2: Scan for ESP32 devices on USB
  try {
    final ports = await hw_bridge.scanHardwareWallets();
    if (ports.isEmpty) {
      return HwConnectionInfo(
        state: HwConnState.disconnected,
        deviceName: hwWallet.name,
        address: hwWallet.address,
      );
    }

    // Step 3: Try to get pubkey from first detected device
    final port = ports.first;
    try {
      final deviceAddress =
          await hw_stubs.getHardwarePubkey(portPath: port.path);
      // Step 4: Compare device pubkey with registered wallet address (HWLT-03)
      if (deviceAddress == hwWallet.address) {
        return HwConnectionInfo(
          state: HwConnState.connected,
          deviceName: hwWallet.name,
          address: hwWallet.address,
          portPath: port.path,
        );
      } else {
        return HwConnectionInfo(
          state: HwConnState.pubkeyMismatch,
          deviceName: hwWallet.name,
          address: hwWallet.address,
          portPath: port.path,
        );
      }
    } catch (_) {
      // Could not communicate with device — treat as disconnected
      return HwConnectionInfo(
        state: HwConnState.disconnected,
        deviceName: hwWallet.name,
        address: hwWallet.address,
      );
    }
  } catch (_) {
    // Scan failed — treat as disconnected
    return HwConnectionInfo(
      state: HwConnState.disconnected,
      deviceName: hwWallet.name,
      address: hwWallet.address,
    );
  }
}
