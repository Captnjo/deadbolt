import 'package:flutter_test/flutter_test.dart';

// Import the provider types under test
import 'package:deadbolt/providers/agent_provider.dart';

void main() {
  group('AgentServerState', () {
    test('stopped state has correct defaults', () {
      // AGNT-15: Status indicator reflects actual server state.
      // Verify state model correctness.
      const state = AgentServerState.stopped();
      expect(state.status, ServerStatus.stopped);
      expect(state.errorMessage, isNull);
      expect(state.port, isNull);
    });

    test('running state includes port', () {
      const state = AgentServerState.running(9876);
      expect(state.status, ServerStatus.running);
      expect(state.port, 9876);
      expect(state.errorMessage, isNull);
    });

    test('error state includes message', () {
      final state = AgentServerState.error('Port in use');
      expect(state.status, ServerStatus.error);
      expect(state.errorMessage, 'Port in use');
      expect(state.port, isNull);
    });
  });

  group('ServerStatus enum', () {
    test('has all expected values', () {
      expect(ServerStatus.values, containsAll([
        ServerStatus.running,
        ServerStatus.stopped,
        ServerStatus.error,
      ]));
    });
  });

  // TODO: Add integration tests after FRB codegen provides mockable bindings:
  // - test AgentServerNotifier.build() returns stopped when pref is false
  // - test AgentServerNotifier.toggleServer(true) transitions to running
  // - test AgentKeyNotifier.build() returns empty list initially
}
