import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/app_shell.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/wallet/wallet_list_screen.dart';
import '../features/wallet/create_wallet_screen.dart';
import '../features/wallet/import_wallet_screen.dart';
import '../features/wallet/connect_hardware_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/receive/receive_screen.dart';
import '../features/send/send_screen.dart';
import '../features/history/history_screen.dart';
import '../features/onboarding/onboarding_shell.dart';
import '../providers/onboarding_provider.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final needsOnboarding = ref.watch(needsOnboardingProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: needsOnboarding ? '/onboarding' : '/dashboard',
    redirect: (context, state) {
      final onOnboarding = state.uri.path == '/onboarding';
      if (needsOnboarding && !onOnboarding) return '/onboarding';
      if (!needsOnboarding && onOnboarding) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OnboardingShell(),
      ),
      GoRoute(
        path: '/receive',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ReceiveScreen(),
      ),
      GoRoute(
        path: '/send',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SendScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HistoryScreen(),
            ),
          ),
          GoRoute(
            path: '/wallets',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WalletListScreen(),
            ),
            routes: [
              GoRoute(
                path: 'create',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (context, state) => const CreateWalletScreen(),
              ),
              GoRoute(
                path: 'import',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (context, state) => const ImportWalletScreen(),
              ),
              GoRoute(
                path: 'hardware',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (context, state) => const ConnectHardwareScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
