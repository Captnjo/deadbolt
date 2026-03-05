import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/transaction_history.dart';

class HeliusService {
  final String apiKey;
  final http.Client _client;

  HeliusService(this.apiKey) : _client = http.Client();

  void dispose() => _client.close();

  /// Fetch parsed transaction history for an address directly from Helius.
  /// Uses the `/v0/addresses/{address}/transactions` endpoint.
  /// Returns enriched transactions with type, description, transfers, etc.
  Future<List<HeliusEnhancedTransaction>> getTransactionHistory(
    String address, {
    int limit = 20,
    String? before,
  }) async {
    final params = <String, String>{
      'api-key': apiKey,
      'limit': limit.toString(),
    };
    if (before != null) params['before'] = before;

    final url = Uri.https(
      'api.helius.xyz',
      '/v0/addresses/$address/transactions',
      params,
    );

    final response = await _client.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Helius API error ${response.statusCode}: ${response.body}',
      );
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) =>
            HeliusEnhancedTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch enhanced transaction details by signature list.
  /// Max 100 signatures per call (Helius limit).
  Future<List<HeliusEnhancedTransaction>> getEnhancedTransactions(
    List<String> signatures,
  ) async {
    if (signatures.isEmpty) return [];

    final url = Uri.parse(
      'https://api.helius.xyz/v0/transactions/?api-key=$apiKey',
    );

    final response = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'transactions': signatures}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Helius API error ${response.statusCode}: ${response.body}',
      );
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) =>
            HeliusEnhancedTransaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
