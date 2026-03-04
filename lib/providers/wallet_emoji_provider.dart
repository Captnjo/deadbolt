import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'wallet_emojis';

const walletEmojiOptions = [
  '🔑', '🔌', '🛡️', '🔒', '💎', '🚀', '⚡', '🔥', '🌙', '🌊',
  '🦊', '🐺', '🦁', '🐉', '🦅', '🎯', '💰', '🏦', '👾', '🤖',
];

String resolveWalletEmoji(
  Map<String, String> emojiMap,
  String address,
  String source,
) {
  final custom = emojiMap[address];
  if (custom != null) return custom;
  return switch (source.toLowerCase()) {
    'hardware' => '🔌',
    _ => '🔑',
  };
}

final walletEmojiProvider =
    AsyncNotifierProvider<WalletEmojiNotifier, Map<String, String>>(
  WalletEmojiNotifier.new,
);

class WalletEmojiNotifier extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> setEmoji(String address, String emoji) async {
    final current = {...?state.valueOrNull};
    current[address] = emoji;
    await _persist(current);
    state = AsyncData(current);
  }

  Future<void> removeEmoji(String address) async {
    final current = {...?state.valueOrNull};
    current.remove(address);
    await _persist(current);
    state = AsyncData(current);
  }

  Future<void> _persist(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(map));
  }
}
