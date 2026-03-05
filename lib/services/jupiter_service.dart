import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/swap.dart';

class JupiterService {
  final String? apiKey;
  final http.Client _client;

  JupiterService({this.apiKey}) : _client = http.Client();

  void dispose() => _client.close();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty) 'x-api-key': apiKey!,
      };

  /// Get a swap quote from Jupiter.
  Future<JupiterQuote> getQuote({
    required String inputMint,
    required String outputMint,
    required String amount,
    int slippageBps = 50,
  }) async {
    final uri = Uri.parse('https://api.jup.ag/swap/v1/quote').replace(
      queryParameters: {
        'inputMint': inputMint,
        'outputMint': outputMint,
        'amount': amount,
        'slippageBps': slippageBps.toString(),
      },
    );

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Jupiter quote failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return JupiterQuote.fromJson(json);
  }

  /// Get a swap transaction from Jupiter.
  /// Returns the base64-encoded unsigned transaction.
  Future<String> getSwapTransaction({
    required Map<String, dynamic> quoteResponse,
    required String userPublicKey,
  }) async {
    final uri = Uri.parse('https://api.jup.ag/swap/v1/swap');
    final body = jsonEncode({
      'quoteResponse': quoteResponse,
      'userPublicKey': userPublicKey,
      'dynamicComputeUnitLimit': true,
      'prioritizationFeeLamports': 'auto',
    });

    final response = await _client.post(uri, headers: _headers, body: body);
    if (response.statusCode != 200) {
      throw Exception('Jupiter swap failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['swapTransaction'] as String;
  }
}
