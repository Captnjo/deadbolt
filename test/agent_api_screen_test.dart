import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Import the screen under test
import 'package:deadbolt/features/agent/agent_api_screen.dart';

void main() {
  group('AgentApiScreen', () {
    testWidgets('renders without error', (tester) async {
      // AGNT-14: /agent-api route renders without error.
      // This is a smoke test — verifies the widget tree builds.
      // Full interaction tests require FRB bridge mocking (added after codegen).
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AgentApiScreen(),
            ),
          ),
        ),
      );

      // The screen should render without throwing
      expect(find.byType(AgentApiScreen), findsOneWidget);
    });

    // TODO: Add interaction tests after FRB codegen provides mockable bindings:
    // - test empty state shows "Connect AI Agents" heading
    // - test server toggle is disabled when no keys exist
    // - test key creation flow triggers auth challenge
  });
}
