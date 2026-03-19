import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/balance_provider.dart';
import '../../providers/guardrails_provider.dart';
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
    final portfolio = ref.watch(balanceProvider).valueOrNull;
    final match = portfolio?.tokenBalances
        .where((tb) => tb.definition.mint == mint)
        .firstOrNull;

    final symbol = match?.definition.symbol ?? 'Unknown';
    final truncated = mint.length >= 8
        ? '${mint.substring(0, 4)}...${mint.substring(mint.length - 4)}'
        : mint;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
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
          onAdd: (mint) {
            ref.read(guardrailsProvider.notifier).addToken(mint);
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }
}

/// Private bottom sheet content for adding a token to the whitelist.
class _AddTokenSheetContent extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final List<String> existingMints;
  final void Function(String mint) onAdd;

  const _AddTokenSheetContent({
    required this.scrollController,
    required this.existingMints,
    required this.onAdd,
  });

  @override
  ConsumerState<_AddTokenSheetContent> createState() =>
      _AddTokenSheetContentState();
}

class _AddTokenSheetContentState
    extends ConsumerState<_AddTokenSheetContent> {
  final _mintController = TextEditingController();
  String _searchQuery = '';
  String? _mintError;

  @override
  void dispose() {
    _mintController.dispose();
    super.dispose();
  }

  void _submitMint(String value) {
    final trimmed = value.trim();
    if (trimmed.length != 44) {
      setState(() =>
          _mintError = 'Invalid mint address (must be 44 characters)');
      return;
    }
    setState(() => _mintError = null);
    widget.onAdd(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(balanceProvider).valueOrNull;
    final allTokens = portfolio?.tokenBalances ?? [];

    // Filter by search query, exclude already-whitelisted tokens
    final filtered = allTokens.where((tb) {
      if (widget.existingMints.contains(tb.definition.mint)) return false;
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return tb.definition.symbol.toLowerCase().contains(q) ||
          tb.definition.name.toLowerCase().contains(q);
    }).toList();

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Add Token to Whitelist',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),

        // Search field
        TextField(
          decoration: const InputDecoration(labelText: 'Search by name or symbol'),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        const SizedBox(height: 8),

        // Held tokens list
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No tokens in your wallet yet',
              style:
                  TextStyle(fontSize: 13, color: BrandColors.textSecondary),
            ),
          )
        else
          for (final tb in filtered)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: BrandColors.surface,
                child: Text(
                  tb.definition.symbol.isNotEmpty
                      ? tb.definition.symbol[0]
                      : '?',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              title: Text(tb.definition.symbol,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                tb.definition.mint.length >= 8
                    ? '${tb.definition.mint.substring(0, 4)}...${tb.definition.mint.substring(tb.definition.mint.length - 4)}'
                    : tb.definition.mint,
                style: const TextStyle(
                    fontSize: 13, color: BrandColors.textSecondary),
              ),
              onTap: () => widget.onAdd(tb.definition.mint),
            ),

        const Divider(),
        const SizedBox(height: 8),

        // Paste mint address field
        TextField(
          controller: _mintController,
          decoration: InputDecoration(
            labelText: 'Or paste a mint address',
            errorText: _mintError,
          ),
          onSubmitted: _submitMint,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _submitMint(_mintController.text),
            child: const Text('Add'),
          ),
        ),
      ],
    );
  }
}
