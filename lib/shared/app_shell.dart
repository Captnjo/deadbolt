import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../features/agent/signing_prompt_sheet.dart';
import '../providers/agent_provider.dart';
import '../providers/auth_provider.dart';
import '../models/intent.dart';
import '../providers/intent_provider.dart';
import '../providers/hardware_connection_provider.dart';
import '../providers/wallet_emoji_provider.dart';
import '../providers/wallet_provider.dart';
import '../routing/app_router.dart';
import '../theme/brand_theme.dart';
import 'widgets/wallet_drawer.dart';

class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin, WindowListener {
  late final AnimationController _drawerController;
  late final Animation<Offset> _slideAnimation;

  /// FocusNode for KeyboardListener activity detection.
  final FocusNode _activityFocusNode = FocusNode();

  static const _routes = ['/dashboard', '/history', '/address-book', '/agent-api', '/hardware', '/settings'];

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
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _drawerController.dispose();
    _activityFocusNode.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Gracefully stop the agent server before window closes (INFR-08).
    try {
      ref.read(agentServerProvider.notifier).forceStop();
    } catch (_) {
      // Guard: agent bridge may be stubbed before FRB codegen
    }
    await windowManager.destroy();
  }

  void _openDrawer() => _drawerController.forward();
  void _closeDrawer() => _drawerController.reverse();

  /// Builds the NavigationRail icon for the Hardware Wallet destination,
  /// reflecting the current [HwConnState] with appropriate color and badge.
  Widget _buildHwNavIcon(HwConnectionInfo hwConn, bool selected) {
    switch (hwConn.state) {
      case HwConnState.notPaired:
        return Badge(
          label: const Text('Setup', style: TextStyle(fontSize: 9)),
          backgroundColor: BrandColors.primary,
          child: Icon(
            selected ? Icons.usb : Icons.usb_outlined,
            color: BrandColors.textSecondary,
            size: 18,
          ),
        );
      case HwConnState.disconnected:
        return Icon(
          selected ? Icons.usb : Icons.usb_outlined,
          color: BrandColors.textDisabled,
          size: 18,
        );
      case HwConnState.connected:
        return Icon(
          selected ? Icons.usb : Icons.usb_outlined,
          color: BrandColors.primary,
          size: 18,
        );
      case HwConnState.pubkeyMismatch:
        return Badge(
          label: const Text('!', style: TextStyle(fontSize: 9)),
          backgroundColor: BrandColors.error,
          child: Icon(
            selected ? Icons.usb : Icons.usb_outlined,
            color: BrandColors.error,
            size: 18,
          ),
        );
    }
  }

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

    // Badge count for Agent API icon.
    final pendingCount = ref.watch(pendingIntentCountProvider);

    // Hardware wallet connection state — drives NavigationRail icon and badge.
    final hwConn = ref.watch(hardwareConnectionProvider).valueOrNull ??
        const HwConnectionInfo.notPaired();

    // Auto-show signing prompt when a new intent arrives and app is unlocked.
    ref.listen<PendingIntent?>(firstPendingIntentProvider, (prev, next) {
      if (next != null && prev?.id != next.id) {
        final authState = ref.read(authProvider);
        if (authState.status == AuthStatus.locked) return;

        final navKey = ref.read(rootNavigatorKeyProvider);
        final navContext = navKey.currentContext;
        if (navContext == null) return;

        // Only show if no modal is currently on top.
        final route = ModalRoute.of(navContext);
        if (route != null && !route.isCurrent) return;

        showSigningPrompt(navContext, next.id);
      }
    });

    // Resubscribe intent stream when the server starts.
    ref.listen(agentServerProvider, (prev, next) {
      final serverState = next.valueOrNull;
      if (serverState?.status == ServerStatus.running) {
        ref.read(intentProvider.notifier).resubscribe();
      }
    });

    // Show disconnect snackbar when hardware wallet transitions from connected to disconnected.
    ref.listen<AsyncValue<HwConnectionInfo>>(hardwareConnectionProvider,
        (prev, next) {
      final prevState = prev?.valueOrNull?.state;
      final nextState = next.valueOrNull?.state;
      if (prevState == HwConnState.connected &&
          nextState == HwConnState.disconnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hardware wallet disconnected'),
            duration: Duration(seconds: 3),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    });

    // Build destinations dynamically so Agent API icon can carry a badge.
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: Text('History'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.contacts_outlined),
        selectedIcon: Icon(Icons.contacts),
        label: Text('Contacts'),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount', style: const TextStyle(fontSize: 10)),
          child: const Icon(Icons.lan_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount', style: const TextStyle(fontSize: 10)),
          child: const Icon(Icons.lan),
        ),
        label: const Text('Agent API'),
      ),
      NavigationRailDestination(
        icon: _buildHwNavIcon(hwConn, false),
        selectedIcon: _buildHwNavIcon(hwConn, true),
        label: const Text('Hardware'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Settings'),
      ),
    ];

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
            destinations: destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Stack(
              children: [
                // Wrap child in Listener + KeyboardListener to reset idle timer
                // on any mouse or keyboard activity while the app is unlocked.
                Listener(
                  onPointerMove: (_) =>
                      ref.read(authProvider.notifier).resetActivity(),
                  onPointerDown: (_) =>
                      ref.read(authProvider.notifier).resetActivity(),
                  child: KeyboardListener(
                    focusNode: _activityFocusNode,
                    autofocus: true,
                    onKeyEvent: (_) =>
                        ref.read(authProvider.notifier).resetActivity(),
                    child: widget.child,
                  ),
                ),
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
