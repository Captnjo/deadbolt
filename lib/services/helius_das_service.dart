import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/nft.dart';

class HeliusDasService {
  final String apiKey;
  final http.Client _client;

  HeliusDasService({required this.apiKey}) : _client = http.Client();

  void dispose() => _client.close();

  /// Fetch NFTs owned by an address using Helius DAS API.
  Future<List<NftAsset>> getAssetsByOwner(
    String ownerAddress, {
    int page = 1,
    int limit = 50,
  }) async {
    final uri = Uri.parse('https://mainnet.helius-rpc.com/?api-key=$apiKey');
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': 'deadbolt-nfts',
      'method': 'getAssetsByOwner',
      'params': {
        'ownerAddress': ownerAddress,
        'page': page,
        'limit': limit,
        'displayOptions': {'showFungible': false, 'showNativeBalance': false},
      },
    });

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Helius DAS failed (${response.statusCode}): ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      final err = json['error'] as Map<String, dynamic>;
      throw Exception('DAS error: ${err['message']}');
    }

    final result = json['result'] as Map<String, dynamic>;
    final items = result['items'] as List<dynamic>? ?? [];

    return items
        .where((item) {
          final iface = (item as Map<String, dynamic>)['interface'] as String?;
          return iface == 'V1_NFT' ||
              iface == 'ProgrammableNFT' ||
              iface == 'V2_NFT';
        })
        .map((item) => NftAsset.fromDas(item as Map<String, dynamic>))
        .toList();
  }
}
