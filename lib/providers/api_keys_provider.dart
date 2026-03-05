import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/swap.dart';

class ApiKeysState {
  final String jupiterKey;
  final String dflowKey;
  final SwapAggregator defaultAggregator;
  final bool jitoMevProtection;

  const ApiKeysState({
    this.jupiterKey = '',
    this.dflowKey = '',
    this.defaultAggregator = SwapAggregator.jupiter,
    this.jitoMevProtection = false,
  });

  ApiKeysState copyWith({
    String? jupiterKey,
    String? dflowKey,
    SwapAggregator? defaultAggregator,
    bool? jitoMevProtection,
  }) {
    return ApiKeysState(
      jupiterKey: jupiterKey ?? this.jupiterKey,
      dflowKey: dflowKey ?? this.dflowKey,
      defaultAggregator: defaultAggregator ?? this.defaultAggregator,
      jitoMevProtection: jitoMevProtection ?? this.jitoMevProtection,
    );
  }
}

class ApiKeysNotifier extends Notifier<ApiKeysState> {
  static const _jupiterKeyPref = 'jupiter_api_key';
  static const _dflowKeyPref = 'dflow_api_key';
  static const _aggregatorPref = 'default_aggregator';
  static const _jitoMevPref = 'jito_mev_protection';

  @override
  ApiKeysState build() {
    _loadFromPrefs();
    return const ApiKeysState();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = ApiKeysState(
      jupiterKey: prefs.getString(_jupiterKeyPref) ?? '',
      dflowKey: prefs.getString(_dflowKeyPref) ?? '',
      defaultAggregator: prefs.getString(_aggregatorPref) == 'dflow'
          ? SwapAggregator.dflow
          : SwapAggregator.jupiter,
      jitoMevProtection: prefs.getBool(_jitoMevPref) ?? false,
    );
  }

  Future<void> setJupiterKey(String key) async {
    state = state.copyWith(jupiterKey: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jupiterKeyPref, key);
  }

  Future<void> setDflowKey(String key) async {
    state = state.copyWith(dflowKey: key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dflowKeyPref, key);
  }

  Future<void> setDefaultAggregator(SwapAggregator aggregator) async {
    state = state.copyWith(defaultAggregator: aggregator);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aggregatorPref, aggregator.name);
  }

  Future<void> setJitoMevProtection(bool enabled) async {
    state = state.copyWith(jitoMevProtection: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_jitoMevPref, enabled);
  }
}

final apiKeysProvider = NotifierProvider<ApiKeysNotifier, ApiKeysState>(
  ApiKeysNotifier.new,
);
