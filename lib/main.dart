import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize flutter_rust_bridge
  await RustLib.init();

  // Configure window
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(480, 650),
    minimumSize: Size(450, 600),
    center: true,
    title: 'Deadbolt',
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: DeadboltApp()));
}

