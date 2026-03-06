import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/swap.dart';

class DFlowService {
  static const _baseUrl = 'https://e.quote-api.dflow.net';

  final String? apiKey;
  final http.Client _client;

  DFlowService({this.apiKey}) : _client = http.Client();

  void dispose() => _client.close();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty) 'x-api-key': apiKey!,
      };

  /// Get a swap quote from DFlow.
  Future<DFlowQuote> getQuote({
    required String inputMint,
    required String outputMint,
    required String amount,
    int slippageBps = 50,
  }) async {
    final uri = Uri.parse('$_baseUrl/quote').replace(
      queryParameters: {
        'inputMint': inputMint,
        'outputMint': outputMint,
        'amount': amount,
        'slippageBps': slippageBps.toString(),
      },
    );

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception(
          'DFlow quote failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DFlowQuote.fromJson(json);
  }

  /// Get a swap transaction from DFlow.
  /// Returns the base64-encoded unsigned transaction.
  Future<String> getSwapTransaction({
    required Map<String, dynamic> quoteResponse,
    required String userPublicKey,
  }) async {
    final uri = Uri.parse('$_baseUrl/swap');
    final body = jsonEncode({
      'quoteResponse': quoteResponse,
      'userPublicKey': userPublicKey,
    });

    final response = await _client.post(uri, headers: _headers, body: body);
    if (response.statusCode != 200) {
      throw Exception(
          'DFlow swap failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['swapTransaction'] as String;
  }
}
