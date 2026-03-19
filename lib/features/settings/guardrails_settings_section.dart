import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/token.dart';
import '../../providers/balance_provider.dart';
import '../../providers/guardrails_provider.dart';
import '../../providers/jupiter_token_list_provider.dart';
import '../../src/rust/api/guardrails.dart' as guardrails_bridge;
import '../../theme/brand_theme.dart';
import '../lock/auth_challenge_dialog.dart';

/// Guardrails section for the Settings screen.
///
/// Provides:
/// - Master toggle (toggling OFF requires password authentication)
/// - Token Whitelist expandable card (add/remove tokens)
class GuardrailsSettingsSection extends ConsumerStatefulWidget {
  const GuardrailsSettingsSection({super.key});

  @override
  ConsumerState<GuardrailsSettingsSection> createState() =>
      _GuardrailsSettingsSectionState();
}

class _GuardrailsSettingsSectionState
    extends ConsumerState<GuardrailsSettingsSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(guardrailsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Guardrails',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BrandColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),

        // Master toggle
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Guardrails', style: TextStyle(fontSize: 14)),
          subtitle: config.enabled
              ? null
              : const Text(
                  'All guardrails disabled',
                  style: TextStyle(fontSize: 13, color: BrandColors.error),
                ),
          trailing: Switch(
            value: config.enabled,
            activeThumbColor: BrandColors.primary,
            onChanged: (val) async {
              if (!val) {
                // Toggling OFF requires password
                final ok = await showAuthChallengeDialog(context);
                if (!ok) return;
              }
              ref.read(guardrailsProvider.notifier).setEnabled(val);
            },
          ),
        ),

        // Token Whitelist card (only shown when guardrails are enabled)
        if (config.enabled) _buildTokenWhitelistCard(config),

        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTokenWhitelistCard(guardrails_bridge.GuardrailsConfigDto config) {
    return Card(
      color: BrandColors.card,
      child: Column(
        children: [
          ListTile(
            title: const Text('Token Whitelist',
                style: TextStyle(fontSize: 14)),
            subtitle: Text(
              config.tokenWhitelist.isEmpty
                  ? 'No restrictions \u2014 all SPL tokens allowed'
                  : '${config.tokenWhitelist.length} tokens',
              style: const TextStyle(
                  fontSize: 13, color: BrandColors.textSecondary),
            ),
            trailing:
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedContent(config),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(guardrails_bridge.GuardrailsConfigDto config) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const Divider(),
          for (final mint in config.tokenWhitelist) _buildTokenRow(mint),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Token'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: BrandColors.primary),
                onPressed: () => _showAddTokenSheet(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenRow(String mint) {
    // Resolve token info from wallet balances, Jupiter list, or registry
    final portfolio = ref.watch(balanceProvider).valueOrNull;
    final walletMatch = portfolio?.tokenBalances
        .where((tb) => tb.definition.mint == mint)
        .firstOrNull;

    TokenDefinition? def = walletMatch?.definition;
    if (def == null) {
      final jupiterTokens = ref.watch(jupiterTokenListProvider).valueOrNull;
      def = jupiterTokens?.where((d) => d.mint == mint).firstOrNull;
    }

    final symbol = def?.symbol ?? 'Unknown';
    final logoUri = def?.logoUri;
    final truncated = mint.length >= 8
        ? '${mint.substring(0, 4)}...${mint.substring(mint.length - 4)}'
        : mint;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: logoUri != null && logoUri.isNotEmpty
          ? CircleAvatar(
              radius: 16,
              backgroundColor: BrandColors.card,
              backgroundImage: NetworkImage(logoUri),
              onBackgroundImageError: (e, s) {},
              child: const SizedBox.shrink(),
            )
          : CircleAvatar(
              radius: 16,
              backgroundColor: BrandColors.surface,
              child: Text(
                symbol.isNotEmpty ? symbol[0] : '?',
                style: const TextStyle(fontSize: 12),
              ),
            ),
      title: Text(symbol, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        truncated,
        style: const TextStyle(
            fontSize: 13, color: BrandColors.textSecondary),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Remove token',
        onPressed: () =>
            ref.read(guardrailsProvider.notifier).removeToken(mint),
      ),
    );
  }

  void _showAddTokenSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => _AddTokenSheetContent(
          scrollController: scrollController,
          existingMints: ref.read(guardrailsProvider).tokenWhitelist,
          onAddAll: (mints) {
            Navigator.pop(ctx);
            ref.read(guardrailsProvider.notifier).addTokens(mints);
          },
        ),
      ),
    );
  }
}

/// Private bottom sheet content for adding tokens to the whitelist.
/// Shows wallet tokens + Jupiter verified tokens, with multi-select.
class _AddTokenSheetContent extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final List<String> existingMints;
  final void Function(List<String> mints) onAddAll;

  const _AddTokenSheetContent({
    required this.scrollController,
    required this.existingMints,
    required this.onAddAll,
  });

  @override
  ConsumerState<_AddTokenSheetContent> createState() =>
      _AddTokenSheetContentState();
}

class _AddTokenSheetContentState
    extends ConsumerState<_AddTokenSheetContent> {
  final _mintController = TextEditingController();
  final Set<String> _selected = {};
  String _searchQuery = '';
  String? _mintError;

  @override
  void dispose() {
    _mintController.dispose();
    super.dispose();
  }

  void _submitMint(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 32 || trimmed.length > 44) {
      setState(() =>
          _mintError = 'Invalid mint address');
      return;
    }
    if (widget.existingMints.contains(trimmed) ||
        _selected.contains(trimmed)) {
      setState(() => _mintError = 'Already added');
      return;
    }
    setState(() {
      _mintError = null;
      _selected.add(trimmed);
      _mintController.clear();
    });
  }

  void _toggleToken(String mint) {
    setState(() {
      if (_selected.contains(mint)) {
        _selected.remove(mint);
      } else {
        _selected.add(mint);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(balanceProvider).valueOrNull;
    final walletTokens = portfolio?.tokenBalances ?? [];
    final jupiterAsync = ref.watch(jupiterTokenListProvider);

    // Build merged list: wallet tokens first, then Jupiter verified tokens
    final walletDefs = walletTokens
        .where((tb) => !widget.existingMints.contains(tb.definition.mint))
        .map((tb) => tb.definition)
        .toList();

    final walletMints = walletDefs.map((d) => d.mint).toSet();

    final jupiterDefs = jupiterAsync.valueOrNull
            ?.where((d) =>
                !widget.existingMints.contains(d.mint) &&
                !walletMints.contains(d.mint))
            .toList() ??
        [];

    // Apply search filter
    List<TokenDefinition> filteredWallet;
    List<TokenDefinition> filteredJupiter;
    if (_searchQuery.isEmpty) {
      filteredWallet = walletDefs;
      // Don't dump all 1000+ Jupiter tokens — only show when searching
      filteredJupiter = [];
    } else {
      final q = _searchQuery.toLowerCase();
      bool matchesQuery(TokenDefinition d) =>
          d.symbol.toLowerCase().contains(q) ||
          d.name.toLowerCase().contains(q) ||
          d.mint.toLowerCase().startsWith(q);
      filteredWallet = walletDefs.where(matchesQuery).toList();
      filteredJupiter = jupiterDefs.where(matchesQuery).take(50).toList();
    }

    final hasResults = filteredWallet.isNotEmpty || filteredJupiter.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Add Tokens to Whitelist',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              // Search field
              TextField(
                decoration: InputDecoration(
                  labelText: 'Search by name, symbol, or mint',
                  suffixIcon: jupiterAsync.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),

              // Wallet tokens section
              if (filteredWallet.isNotEmpty) ...[
                const Text(
                  'Your Wallet',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BrandColors.textSecondary,
                  ),
                ),
                for (final def in filteredWallet)
                  _buildTokenCheckTile(def, inWallet: true),
              ],

              // Jupiter verified tokens section
              if (filteredJupiter.isNotEmpty) ...[
                if (filteredWallet.isNotEmpty) const Divider(),
                const Text(
                  'Jupiter Verified',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BrandColors.textSecondary,
                  ),
                ),
                for (final def in filteredJupiter)
                  _buildTokenCheckTile(def, inWallet: false),
              ],

              if (!hasResults && _searchQuery.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No tokens found',
                    style: TextStyle(
                        fontSize: 13, color: BrandColors.textSecondary),
                  ),
                ),

              if (!hasResults && _searchQuery.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    jupiterAsync.isLoading
                        ? 'Loading verified token list...'
                        : 'Type to search verified tokens on Solana',
                    style: const TextStyle(
                        fontSize: 13, color: BrandColors.textSecondary),
                  ),
                ),

              const Divider(),
              const SizedBox(height: 8),

              // Paste mint address field
              TextField(
                controller: _mintController,
                decoration: InputDecoration(
                  labelText: 'Or paste a mint address',
                  errorText: _mintError,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => _submitMint(_mintController.text),
                  ),
                ),
                onSubmitted: _submitMint,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // Sticky bottom bar with Add button
        if (_selected.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: BrandColors.surface,
              border: Border(top: BorderSide(color: BrandColors.card)),
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => widget.onAddAll(_selected.toList()),
                  child: Text('Add ${_selected.length} token${_selected.length == 1 ? '' : 's'}'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTokenCheckTile(TokenDefinition def, {required bool inWallet}) {
    final isChecked = _selected.contains(def.mint);
    final truncated = def.mint.length >= 8
        ? '${def.mint.substring(0, 4)}...${def.mint.substring(def.mint.length - 4)}'
        : def.mint;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buildTokenAvatar(def),
      title: Text(
        def.symbol,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${def.name}  $truncated',
        style: const TextStyle(
            fontSize: 12, color: BrandColors.textSecondary),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Checkbox(
        value: isChecked,
        activeColor: BrandColors.primary,
        onChanged: (_) => _toggleToken(def.mint),
      ),
      onTap: () => _toggleToken(def.mint),
    );
  }

  Widget _buildTokenAvatar(TokenDefinition def) {
    if (def.logoUri != null && def.logoUri!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: BrandColors.card,
        backgroundImage: NetworkImage(def.logoUri!),
        onBackgroundImageError: (e, s) {},
        child: const SizedBox.shrink(),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: BrandColors.card,
      child: Text(
        def.symbol.isNotEmpty ? def.symbol[0] : '?',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
