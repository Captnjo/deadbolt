import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'shared/widgets/title_bar.dart';
import 'theme/brand_theme.dart';

class DeadboltApp extends ConsumerWidget {
  const DeadboltApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
