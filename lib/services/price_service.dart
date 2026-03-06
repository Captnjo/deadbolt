import 'dart:convert';

import 'package:http/http.dart' as http;

const _stablecoins = {
  'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', // USDC
  'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB', // USDT
};

/// Fetch SOL price from CoinGecko in USD and an optional display currency.
/// When [displayCode] is 'usd' or 'sol', only the USD price is fetched.
Future<({double usd, double display})> fetchSolPrice({
  String displayCode = 'usd',
}) async {
  final needsDisplay = displayCode != 'usd' && displayCode != 'sol';
  final currencies = needsDisplay ? 'usd,$displayCode' : 'usd';
  final uri = Uri.parse(
    'https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=$currencies',
  );
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('CoinGecko HTTP ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final solana = json['solana'] as Map<String, dynamic>;
  final usd = (solana['usd'] as num).toDouble();
  final display = needsDisplay
      ? (solana[displayCode] as num).toDouble()
      : usd;
  return (usd: usd, display: display);
}

/// Fetch token price from Jupiter Price API v2.
/// Returns null if the token is not found.
Future<double?> fetchTokenPrice(String mint) async {
  if (_stablecoins.contains(mint)) return 1.0;

  final uri = Uri.parse('https://api.jup.ag/price/v2?ids=$mint');
  final response = await http.get(uri);
  if (response.statusCode != 200) return null;

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final data = json['data'] as Map<String, dynamic>?;
  if (data == null) return null;
  final tokenData = data[mint] as Map<String, dynamic>?;
  if (tokenData == null) return null;
  final price = tokenData['price'];
  if (price == null) return null;
  if (price is num) return price.toDouble();
  if (price is String) return double.tryParse(price);
  return null;
}
