import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/token.dart';
import '../services/token_registry.dart';
import 'api_keys_provider.dart';

/// Fetches verified tokens from Jupiter API (if key configured),
/// falling back to the bundled token registry.
final jupiterTokenListProvider =
    FutureProvider<List<TokenDefinition>>((ref) async {
  final apiKeys = ref.watch(apiKeysProvider);
  final jupiterKey = apiKeys.jupiterKey;

  // Try Jupiter API if key is configured
  if (jupiterKey.isNotEmpty) {
    try {
      final response = await http.get(
        Uri.parse('https://api.jup.ag/tokens/v1'),
        headers: {
          'Accept': 'application/json',
          'x-api-key': jupiterKey,
        },
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((item) {
          final json = item as Map<String, dynamic>;
          return TokenDefinition(
            mint: json['address'] as String,
            name: json['name'] as String? ?? '',
            symbol: json['symbol'] as String? ?? '',
            decimals: json['decimals'] as int? ?? 0,
            logoUri: json['logoURI'] as String?,
          );
        }).toList();
      }
    } catch (_) {
      // Fall through to bundled registry
    }
  }

  // Fallback: use bundled token registry
  final registry = TokenRegistry.instance;
  await registry.load();
  return registry.allTokens;
});
