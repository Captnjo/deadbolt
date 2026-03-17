// Typed stub — replaced by FRB codegen when Flutter toolchain is available.
// Follows same pattern as auth.dart stub.

class AgentStatusEvent {
  final String status;
  final int? port;
  final String? error;
  AgentStatusEvent({required this.status, this.port, this.error});
}

class ApiKeyEntry {
  final String tokenMasked;
  final String tokenPrefix;
  final String label;
  final int? createdAt;
  ApiKeyEntry({
    required this.tokenMasked,
    required this.tokenPrefix,
    required this.label,
    this.createdAt,
  });
}

Future<AgentStatusEvent> startAgentServer({required int port}) =>
    throw UnimplementedError('FRB codegen required');

void stopAgentServer() => throw UnimplementedError('FRB codegen required');

bool isAgentServerRunning() => throw UnimplementedError('FRB codegen required');

Future<String> createApiKey({required String label}) =>
    throw UnimplementedError('FRB codegen required');

Future<void> revokeApiKey({required String token}) =>
    throw UnimplementedError('FRB codegen required');

List<ApiKeyEntry> listApiKeys() =>
    throw UnimplementedError('FRB codegen required');

Future<String> getFullApiKey({required String tokenPrefix}) =>
    throw UnimplementedError('FRB codegen required');

Future<void> updateAgentWalletData({
  double? solBalance,
  double? solUsd,
  required String tokensJson,
  required String historyJson,
  required String pricesJson,
}) =>
    throw UnimplementedError('FRB codegen required');
