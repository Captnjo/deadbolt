import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/wallet_emoji_provider.dart';
import '../providers/wallet_provider.dart';
import '../theme/brand_theme.dart';
import 'widgets/wallet_drawer.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drawerController;
  late final Animation<Offset> _slideAnimation;

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: Text('Dashboard'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: Text('History'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.contacts_outlined),
      selectedIcon: Icon(Icons.contacts),
      label: Text('Contacts'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('Settings'),
    ),
  ];

  static const _routes = ['/dashboard', '/history', '/address-book', '/settings'];

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _drawerController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _drawerController.dispose();
    super.dispose();
  }

  void _openDrawer() => _drawerController.forward();
  void _closeDrawer() => _drawerController.reverse();

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    for (var i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) return i;
    }
    return 0; // default to Dashboard
  }

  @override
  Widget build(BuildContext context) {
    final index = _selectedIndex(context);
    final activeAddress = ref.watch(activeWalletProvider);
    final emojiMap = ref.watch(walletEmojiProvider).valueOrNull ?? {};
    final wallets = ref.watch(walletListProvider).valueOrNull ?? [];

    // Resolve active wallet emoji
    String activeEmoji = '🔑';
    if (activeAddress != null) {
      final wallet =
          wallets.where((w) => w.address == activeAddress).firstOrNull;
      if (wallet != null) {
        activeEmoji =
            resolveWalletEmoji(emojiMap, wallet.address, wallet.source);
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_drawerController.isForwardOrCompleted) {
            _closeDrawer();
          } else if (index != 0) {
            context.go('/dashboard');
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) {
              _closeDrawer();
              context.go(_routes[i]);
            },
            labelType: NavigationRailLabelType.all,
            leading: Column(
              children: [
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _openDrawer,
                  child: Tooltip(
                    message: 'Switch wallet',
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BrandColors.card,
                        border: Border.all(color: BrandColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        activeEmoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Image.asset(
                    'assets/deadbolt_logomark.png',
                    width: 48,
                    height: 48,
                    color: Colors.white,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            destinations: _destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Stack(
              children: [
                widget.child,
                // Scrim
                AnimatedBuilder(
                  animation: _drawerController,
                  builder: (context, _) {
                    if (_drawerController.value == 0) {
                      return const SizedBox.shrink();
                    }
                    return GestureDetector(
                      onTap: _closeDrawer,
                      child: Container(
                        color: Colors.black
                            .withAlpha((_drawerController.value * 128).round()),
                      ),
                    );
                  },
                ),
                // Drawer
                AnimatedBuilder(
                  animation: _drawerController,
                  builder: (context, child) {
                    if (_drawerController.isDismissed) {
                      return const SizedBox.shrink();
                    }
                    return SlideTransition(
                      position: _slideAnimation,
                      child: child,
                    );
                  },
                  child: WalletDrawer(onClose: _closeDrawer),
                ),
              ],
            ),
          ),
        ],
      ),
    )),
    );
  }
}
