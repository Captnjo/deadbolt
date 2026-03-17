import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FRB-generated or stub import for agent bridge functions.
// If FRB codegen has not run, create lib/src/rust/api/agent.dart as a typed stub
// (same pattern as auth.dart — functions throw UnimplementedError).
import '../src/rust/api/agent.dart' as agent_bridge;

// Import wallet provider for auto-start wallet availability guard
import 'wallet_provider.dart';

// --- Server Status ---

enum ServerStatus { running, stopped, error }

class AgentServerState {
  final ServerStatus status;
  final String? errorMessage;
  final int? port;

  const AgentServerState({
    required this.status,
    this.errorMessage,
    this.port,
  });

  const AgentServerState.stopped()
      : status = ServerStatus.stopped,
        errorMessage = null,
        port = null;

  const AgentServerState.running(this.port)
      : status = ServerStatus.running,
        errorMessage = null;

  AgentServerState.error(this.errorMessage)
      : status = ServerStatus.error,
        port = null;
}

class AgentServerNotifier extends AsyncNotifier<AgentServerState> {
  static const _prefKey = 'agent_server_enabled';
  static const _defaultPort = 9876;

  @override
  Future<AgentServerState> build() async {
    // Check auto-start preference
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool(_prefKey) ?? false;

    if (wasEnabled) {
      // Guard: only auto-start if wallet is available (RESEARCH.md Pitfall 6)
      final address = ref.read(activeWalletProvider);
      if (address == null) {
        return const AgentServerState.stopped();
      }

      // Only auto-start if we have keys
      try {
        final keys = agent_bridge.listApiKeys();
        if (keys.isNotEmpty) {
          return _startServer();
        }
      } catch (_) {
        // If listing keys fails, stay stopped
      }
    }

    return const AgentServerState.stopped();
  }

  Future<AgentServerState> _startServer() async {
    try {
      final result = await agent_bridge.startAgentServer(port: _defaultPort);
      if (result.status == 'running') {
        return AgentServerState.running(result.port ?? _defaultPort);
      } else if (result.status == 'error') {
        return AgentServerState.error(result.error ?? 'Unknown error');
      }
      return const AgentServerState.stopped();
    } catch (e) {
      final msg = e.toString();
      // Translate common errors to user-friendly messages
      if (msg.contains('Bind') && msg.contains('in use')) {
        return AgentServerState.error(
            'Port $_defaultPort is in use by another process. Close it and try again.');
      }
      return AgentServerState.error(msg);
    }
  }

  Future<void> toggleServer(bool enable) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enable);

    if (enable) {
      state = const AsyncValue.loading();
      state = AsyncValue.data(await _startServer());
    } else {
      agent_bridge.stopAgentServer();
      state = const AsyncValue.data(AgentServerState.stopped());
    }
  }

  /// Force stop without updating preference (used on window close).
  void forceStop() {
    agent_bridge.stopAgentServer();
  }
}

final agentServerProvider =
    AsyncNotifierProvider<AgentServerNotifier, AgentServerState>(
  () => AgentServerNotifier(),
);

// --- API Key Management ---

class AgentKeyNotifier extends Notifier<List<agent_bridge.ApiKeyEntry>> {
  @override
  List<agent_bridge.ApiKeyEntry> build() {
    try {
      return agent_bridge.listApiKeys();
    } catch (_) {
      return [];
    }
  }

  /// Create a new key. Returns the full token string (shown once).
  Future<String> createKey(String label) async {
    final token = await agent_bridge.createApiKey(label: label);
    // Refresh the list
    state = agent_bridge.listApiKeys();
    return token;
  }

  /// Revoke a key by full token.
  Future<void> revokeKey(String token) async {
    await agent_bridge.revokeApiKey(token: token);
    state = agent_bridge.listApiKeys();
  }

  /// Get full (unmasked) key by prefix (requires prior auth challenge).
  Future<String> getFullKey(String tokenPrefix) async {
    return agent_bridge.getFullApiKey(tokenPrefix: tokenPrefix);
  }

  /// Refresh the key list from config.
  void refresh() {
    try {
      state = agent_bridge.listApiKeys();
    } catch (_) {
      // Keep current state on error
    }
  }
}

final agentKeyProvider =
    NotifierProvider<AgentKeyNotifier, List<agent_bridge.ApiKeyEntry>>(
  () => AgentKeyNotifier(),
);

/// Convenience provider: true if at least one API key exists.
final hasApiKeysProvider = Provider<bool>((ref) {
  return ref.watch(agentKeyProvider).isNotEmpty;
});

/// Convenience provider: number of API keys.
final apiKeyCountProvider = Provider<int>((ref) {
  return ref.watch(agentKeyProvider).length;
});
