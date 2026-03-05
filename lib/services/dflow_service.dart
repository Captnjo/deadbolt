import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/swap.dart';

class DFlowService {
  final String? apiKey;
  final http.Client _client;

  DFlowService({this.apiKey}) : _client = http.Client();

  void dispose() => _client.close();

  /// Get an order from DFlow aggregator.
  /// Returns a DFlowOrder containing the pre-built base64 transaction.
  Future<DFlowOrder> getOrder({
    required String inputMint,
    required String outputMint,
    required String amount,
    required String userPublicKey,
  }) async {
    final uri = Uri.parse('https://app.dflow.net/api/v1/order').replace(
      queryParameters: {
        'inputMint': inputMint,
        'outputMint': outputMint,
        'amount': amount,
        'publicKey': userPublicKey,
        if (apiKey != null && apiKey!.isNotEmpty) 'apiKey': apiKey!,
      },
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('DFlow order failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DFlowOrder.fromJson(json);
  }
}
