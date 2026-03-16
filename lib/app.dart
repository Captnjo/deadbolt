import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'routing/app_router.dart';
import 'shared/widgets/title_bar.dart';
import 'theme/brand_theme.dart';

class DeadboltApp extends ConsumerStatefulWidget {
  const DeadboltApp({super.key});

  @override
  ConsumerState<DeadboltApp> createState() => _DeadboltAppState();
}

class _DeadboltAppState extends ConsumerState<DeadboltApp> {
  @override
  void initState() {
    super.initState();
    // Load saved idle timeout from SharedPreferences after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initIdleTimeout(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Deadbolt',
      debugShowCheckedModeBanner: false,
      theme: buildBrandTheme(),
      routerConfig: router,
      builder: (context, child) {
        return Column(
          children: [
            const TitleBar(),
            Expanded(child: child!),
          ],
        );
      },
    );
  }
}
