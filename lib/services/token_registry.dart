import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/token.dart';

class TokenRegistry {
  TokenRegistry._();

  static TokenRegistry? _instance;
  static TokenRegistry get instance => _instance ??= TokenRegistry._();

  final Map<String, TokenDefinition> _tokens = {};

  bool get isLoaded => _tokens.isNotEmpty;

  Future<void> load() async {
    if (_tokens.isNotEmpty) return;
    final json = await rootBundle.loadString('assets/tokens.json');
    final list = jsonDecode(json) as List<dynamic>;
    for (final item in list) {
      final def = TokenDefinition.fromJson(item as Map<String, dynamic>);
      _tokens[def.mint] = def;
    }
  }

  TokenDefinition? lookup(String mint) => _tokens[mint];

  List<TokenDefinition> get allTokens => _tokens.values.toList();
}
