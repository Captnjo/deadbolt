import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/hardware.dart' as hw_bridge;
import '../src/rust/api/types.dart';
import '../src/rust/api/wallet.dart' as bridge;

final hwDetectedProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final ports = await hw_bridge.scanHardwareWallets();
    return ports.isNotEmpty;
  } catch (_) {
    return false;
  }
});

final walletListProvider =
    AsyncNotifierProvider<WalletNotifier, List<WalletInfoDto>>(
  WalletNotifier.new,
);

class WalletNotifier extends AsyncNotifier<List<WalletInfoDto>> {
  @override
  Future<List<WalletInfoDto>> build() => bridge.listWallets();

  Future<List<String>> createWallet(String name, int wordCount) async {
    final result = await bridge.createWallet(name: name, wordCount: wordCount);
    ref.invalidateSelf();
    return result.mnemonicWords;
  }

  Future<void> importWallet(String name, List<String> words) async {
    await bridge.importWallet(name: name, words: words);
    ref.invalidateSelf();
  }

  Future<void> removeWallet(String address) async {
    await bridge.removeWallet(address: address);
    ref.invalidateSelf();
  }

  Future<void> setActive(String address) async {
    await bridge.setActiveWallet(address: address);
    ref.invalidateSelf();
    ref.invalidate(activeWalletProvider);
  }
}

final activeWalletProvider = Provider<String?>((ref) {
  // Re-read whenever the wallet list changes
  ref.watch(walletListProvider);
  return bridge.getActiveWallet();
});
