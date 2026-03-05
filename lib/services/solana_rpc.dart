import 'dart:convert';

import 'package:http/http.dart' as http;

class TokenAccountEntry {
  final String pubkey;
  final String mint;
  final String owner;
  final String amount;
  final int decimals;
  final double? uiAmount;

  const TokenAccountEntry({
    required this.pubkey,
    required this.mint,
    required this.owner,
    required this.amount,
    required this.decimals,
    this.uiAmount,
  });
}

class SolanaRpcClient {
  final String rpcUrl;
  final http.Client _client;
  int _requestId = 0;

  SolanaRpcClient(this.rpcUrl) : _client = http.Client();

  void dispose() => _client.close();

  Future<dynamic> _jsonRpc(String method, List<dynamic> params) async {
    _requestId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': _requestId,
      'method': method,
      'params': params,
    });
    final response = await _client.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('RPC HTTP ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      final err = json['error'] as Map<String, dynamic>;
      throw Exception('RPC error ${err['code']}: ${err['message']}');
    }
    return json['result'];
  }

  /// Get SOL balance in lamports.
  Future<int> getBalance(String address) async {
    final result = await _jsonRpc('getBalance', [address]);
    return (result as Map<String, dynamic>)['value'] as int;
  }

  /// Get the latest blockhash. Returns (blockhash, lastValidBlockHeight).
  Future<({String blockhash, int lastValidBlockHeight})>
      getLatestBlockhash() async {
    final result = await _jsonRpc('getLatestBlockhash', [
      {'commitment': 'finalized'},
    ]);
    final value = (result as Map<String, dynamic>)['value']
        as Map<String, dynamic>;
    return (
      blockhash: value['blockhash'] as String,
      lastValidBlockHeight: value['lastValidBlockHeight'] as int,
    );
  }

  /// Send a signed transaction (base64-encoded).
  /// Returns the transaction signature.
  Future<String> sendTransaction(String base64Tx) async {
    final result = await _jsonRpc('sendTransaction', [
      base64Tx,
      {'encoding': 'base64', 'skipPreflight': false},
    ]);
    return result as String;
  }

  /// Simulate a transaction (base64-encoded).
  Future<SimulationResult> simulateTransaction(String base64Tx) async {
    final result = await _jsonRpc('simulateTransaction', [
      base64Tx,
      {
        'encoding': 'base64',
        'sigVerify': false,
        'replaceRecentBlockhash': true,
      },
    ]);
    final value = (result as Map<String, dynamic>)['value']
        as Map<String, dynamic>;
    return SimulationResult(
      err: value['err'],
      logs: (value['logs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      unitsConsumed: value['unitsConsumed'] as int? ?? 0,
    );
  }

  /// Get confirmation status for a list of signatures.
  Future<List<String?>> getSignatureStatuses(List<String> signatures) async {
    final result = await _jsonRpc('getSignatureStatuses', [
      signatures,
      {'searchTransactionHistory': false},
    ]);
    final values = (result as Map<String, dynamic>)['value'] as List<dynamic>;
    return values.map((v) {
      if (v == null) return null;
      return (v as Map<String, dynamic>)['confirmationStatus'] as String?;
    }).toList();
  }

  /// Check if an account exists (non-null response).
  Future<bool> accountExists(String address) async {
    final result = await _jsonRpc('getAccountInfo', [
      address,
      {'encoding': 'base64'},
    ]);
    final value = (result as Map<String, dynamic>)['value'];
    return value != null;
  }

  /// Get recent transaction signatures for an address.
  Future<List<SignatureInfo>> getSignaturesForAddress(
    String address, {
    int limit = 20,
    String? before,
  }) async {
    final opts = <String, dynamic>{'limit': limit};
    if (before != null) opts['before'] = before;
    final result = await _jsonRpc('getSignaturesForAddress', [address, opts]);
    return (result as List<dynamic>).map((item) {
      final map = item as Map<String, dynamic>;
      return SignatureInfo(
        signature: map['signature'] as String,
        slot: map['slot'] as int,
        blockTime: map['blockTime'] as int?,
        err: map['err'],
      );
    }).toList();
  }

  /// Get all SPL token accounts for an owner.
  Future<List<TokenAccountEntry>> getTokenAccountsByOwner(
    String address,
  ) async {
    final result = await _jsonRpc('getTokenAccountsByOwner', [
      address,
      {'programId': 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'},
      {'encoding': 'jsonParsed'},
    ]);
    final accounts =
        (result as Map<String, dynamic>)['value'] as List<dynamic>;
    return accounts.map((item) {
      final account = item as Map<String, dynamic>;
      final pubkey = account['pubkey'] as String;
      final parsed = account['account']['data']['parsed']['info']
          as Map<String, dynamic>;
      final tokenAmount = parsed['tokenAmount'] as Map<String, dynamic>;
      return TokenAccountEntry(
        pubkey: pubkey,
        mint: parsed['mint'] as String,
        owner: parsed['owner'] as String,
        amount: tokenAmount['amount'] as String,
        decimals: tokenAmount['decimals'] as int,
        uiAmount: (tokenAmount['uiAmount'] as num?)?.toDouble(),
      );
    }).toList();
  }
}

class SignatureInfo {
  final String signature;
  final int slot;
  final int? blockTime;
  final dynamic err;

  const SignatureInfo({
    required this.signature,
    required this.slot,
    this.blockTime,
    this.err,
  });

  bool get success => err == null;
}

class SimulationResult {
  final dynamic err;
  final List<String> logs;
  final int unitsConsumed;

  const SimulationResult({
    required this.err,
    required this.logs,
    required this.unitsConsumed,
  });

  bool get success => err == null;
}
