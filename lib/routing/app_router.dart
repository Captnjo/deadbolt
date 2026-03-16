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
import '../features/swap/swap_screen.dart';
import '../features/nft/send_nft_screen.dart';
import '../features/address_book/address_book_screen.dart';
import '../features/history/history_screen.dart';
import '../features/onboarding/onboarding_shell.dart';
import '../features/lock/lock_screen.dart';
import '../providers/onboarding_provider.dart';
import '../providers/auth_provider.dart';
import '../src/rust/api/auth.dart' as auth_bridge;

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final needsOnboarding = ref.watch(needsOnboardingProvider);
  final authState = ref.watch(authProvider);
  final isLocked = authState.status == AuthStatus.locked;
  final hasPassword = auth_bridge.hasAppPassword();

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: needsOnboarding ? '/onboarding' : '/lock',
    redirect: (context, state) {
      final path = state.uri.path;
      final onOnboarding = path == '/onboarding';
      final onLock = path == '/lock';

      // Onboarding takes priority over everything
      if (needsOnboarding && !onOnboarding) return '/onboarding';
      if (!needsOnboarding && onOnboarding) return '/dashboard';

      // Lock screen redirect (only if a password has been set)
      if (!needsOnboarding && hasPassword && isLocked && !onLock) {
        return '/lock';
      }
      if (!needsOnboarding && !isLocked && onLock) return '/dashboard';

      return null;
    },
    routes: [
      // Lock screen — full-screen route outside the shell
      GoRoute(
        path: '/lock',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LockScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 200),
        ),
      ),
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
      GoRoute(
        path: '/swap',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SwapScreen(),
      ),
      GoRoute(
        path: '/send-nft',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SendNftScreen(),
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
            path: '/address-book',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AddressBookScreen(),
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
