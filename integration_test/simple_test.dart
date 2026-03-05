import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/app.dart';
import 'package:deadbolt/src/rust/frb_generated.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('App launches and shows wallets screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DeadboltApp()));
    await tester.pumpAndSettle();
    expect(find.text('Wallets'), findsWidgets);
  });
}
