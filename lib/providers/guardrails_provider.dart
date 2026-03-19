import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/guardrails.dart' as guardrails_bridge;

class GuardrailsNotifier
    extends Notifier<guardrails_bridge.GuardrailsConfigDto> {
  @override
  guardrails_bridge.GuardrailsConfigDto build() {
    try {
      return guardrails_bridge.getGuardrailsConfig();
    } catch (_) {
      return const guardrails_bridge.GuardrailsConfigDto(
        enabled: true,
        tokenWhitelist: [],
      );
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final updated = state.copyWith(enabled: enabled);
    await guardrails_bridge.updateGuardrailsConfig(dto: updated);
    state = updated;
  }

  Future<void> addToken(String mint) async {
    if (state.tokenWhitelist.contains(mint)) return;
    final newList = [...state.tokenWhitelist, mint];
    final updated = state.copyWith(tokenWhitelist: newList);
    await guardrails_bridge.updateGuardrailsConfig(dto: updated);
    state = updated;
  }

  Future<void> removeToken(String mint) async {
    final newList = state.tokenWhitelist.where((m) => m != mint).toList();
    final updated = state.copyWith(tokenWhitelist: newList);
    await guardrails_bridge.updateGuardrailsConfig(dto: updated);
    state = updated;
  }

  void refresh() {
    try {
      state = guardrails_bridge.getGuardrailsConfig();
    } catch (_) {
      // keep current state on error
    }
  }
}

final guardrailsProvider =
    NotifierProvider<GuardrailsNotifier, guardrails_bridge.GuardrailsConfigDto>(
  GuardrailsNotifier.new,
);
