import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/intent.dart';
import '../../providers/agent_provider.dart';
import '../../providers/intent_provider.dart';
import '../../theme/brand_theme.dart';
import '../lock/auth_challenge_dialog.dart';
import '../../src/rust/api/agent.dart' as agent_bridge;
import 'signing_prompt_sheet.dart';

class AgentApiScreen extends ConsumerStatefulWidget {
  const AgentApiScreen({super.key});

  @override
  ConsumerState<AgentApiScreen> createState() => _AgentApiScreenState();
}

class _AgentApiScreenState extends ConsumerState<AgentApiScreen> {
  String _selectedEndpoint = '/health';
  int _selectedKeyIndex = 0;

  // --- Auth cooldown (skip re-prompt within 60 seconds) ---
  DateTime? _lastAuthTime;
  static const _authCooldown = Duration(seconds: 60);

  Future<bool> _requireAuth(BuildContext context) async {
    if (_lastAuthTime != null &&
        DateTime.now().difference(_lastAuthTime!) < _authCooldown) {
      return true;
    }
    final authed = await showAuthChallengeDialog(context);
    if (authed) _lastAuthTime = DateTime.now();
    return authed;
  }

  // --- Clipboard auto-clear (PLSH-02 — 30 seconds) ---
  Timer? _clipboardClearTimer;

  void _scheduleClipboardClear() {
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(const Duration(seconds: 30), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    super.dispose();
  }

  // ---- Helpers ----

  void _copyToClipboard(String text, BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    _scheduleClipboardClear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2)),
    );
  }

  String _buildCurlCommand(List<agent_bridge.ApiKeyEntry> keys) {
    if (keys.isEmpty) return '';
    final keyIndex = _selectedKeyIndex.clamp(0, keys.length - 1);
    final token = keys[keyIndex].tokenMasked;
    return 'curl -H "Authorization: Bearer $token" http://localhost:9876$_selectedEndpoint';
  }

  // ---- Interaction Flows ----

  Future<void> _createKey(BuildContext context, WidgetRef ref) async {
    final authed = await _requireAuth(context);
    if (!authed || !context.mounted) return;

    final keyNotifier = ref.read(agentKeyProvider.notifier);
    final currentKeyCount = ref.read(agentKeyProvider).length;

    // Dialog 1: get label from user
    final label = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text(
            'Create API Key',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g. Claude agent, Trading bot',
              labelText: 'Label (optional)',
            ),
            onSubmitted: (value) => Navigator.pop(ctx, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (label == null || !context.mounted) return;

    // Create the key
    String token;
    try {
      final defaultLabel = label.trim().isEmpty
          ? 'API Key ${currentKeyCount + 1}'
          : label.trim();
      token = await keyNotifier.createKey(defaultLabel);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create key: $e')),
        );
      }
      ref.read(agentKeyProvider.notifier).refresh();
      return;
    }

    ref.read(agentKeyProvider.notifier).refresh();
    if (!context.mounted) return;

    // Dialog 2: show the token once
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'API Key Created',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This is your full API key. Keep it secret.',
                  style: TextStyle(
                      fontSize: 14, color: BrandColors.textSecondary),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  token,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: BrandColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                _copyToClipboard(token, context);
                Navigator.pop(ctx);
              },
              child: const Text('Copy & Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _revealKey(
      BuildContext context, WidgetRef ref, agent_bridge.ApiKeyEntry key) async {
    final authed = await _requireAuth(context);
    if (!authed || !context.mounted) return;

    String? fullKey;
    try {
      fullKey = await ref
          .read(agentKeyProvider.notifier)
          .getFullKey(key.tokenPrefix);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to retrieve key: $e')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final tokenController = TextEditingController(text: fullKey);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'API Key',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This is your full API key. Keep it secret.',
                style: TextStyle(
                    fontSize: 14, color: BrandColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tokenController,
                readOnly: true,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: BrandColors.textSecondary,
                ),
                decoration:
                    const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              _copyToClipboard(fullKey!, context);
              Navigator.pop(ctx);
            },
            child: const Text('Copy & Close'),
          ),
        ],
      ),
    );

    tokenController.dispose();
  }

  Future<bool> _confirmRevoke(
      BuildContext context, WidgetRef ref, agent_bridge.ApiKeyEntry key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Revoke API key?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '"${key.label}" will be permanently revoked. '
          'Any agent using it will lose access immediately.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Key'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: OutlinedButton.styleFrom(
              foregroundColor: BrandColors.error,
              side: const BorderSide(color: BrandColors.error),
            ),
            child: const Text('Revoke Key'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;
    if (!context.mounted) return false;

    final authed = await _requireAuth(context);
    if (!authed || !context.mounted) return false;

    try {
      final keyNotifier = ref.read(agentKeyProvider.notifier);
      final fullToken = await keyNotifier.getFullKey(key.tokenPrefix);
      await keyNotifier.revokeKey(fullToken);

      // Refresh key list after revoke
      keyNotifier.refresh();

      // If last key was revoked, stop the server
      final remainingKeys = ref.read(agentKeyProvider);
      if (remainingKeys.isEmpty) {
        await ref.read(agentServerProvider.notifier).toggleServer(false);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to revoke key: $e')),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _copyCurlCommand(
      BuildContext context, List<agent_bridge.ApiKeyEntry> keys) async {
    if (keys.isEmpty) return;

    final authed = await _requireAuth(context);
    if (!authed || !context.mounted) return;

    try {
      final keyIndex = _selectedKeyIndex.clamp(0, keys.length - 1);
      final fullToken = await ref
          .read(agentKeyProvider.notifier)
          .getFullKey(keys[keyIndex].tokenPrefix);
      final curlCmd =
          'curl -H "Authorization: Bearer $fullToken" http://localhost:9876$_selectedEndpoint';
      if (context.mounted) {
        _copyToClipboard(curlCmd, context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to copy: $e')),
        );
      }
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final serverAsync = ref.watch(agentServerProvider);
    final keys = ref.watch(agentKeyProvider);
    final hasApiKeys = ref.watch(hasApiKeysProvider);

    // Pending intents for the queue section.
    final pendingIntents = ref.watch(intentProvider)
        .where((i) => i.lifecycle == IntentLifecycle.pending)
        .toList();

    // Derive server state values
    final serverState = serverAsync.valueOrNull;
    final isRunning = serverState?.status == ServerStatus.running;
    final isLoading = serverAsync.isLoading;

    Color statusColor;
    String statusText;

    if (isLoading) {
      statusColor = BrandColors.textDisabled;
      statusText = 'Starting...';
    } else if (serverState == null) {
      statusColor = BrandColors.textDisabled;
      statusText = 'Stopped';
    } else {
      switch (serverState.status) {
        case ServerStatus.running:
          statusColor = BrandColors.success;
          statusText = 'Running on :9876';
          break;
        case ServerStatus.stopped:
          statusColor = BrandColors.textDisabled;
          statusText = 'Stopped';
          break;
        case ServerStatus.error:
          statusColor = BrandColors.error;
          statusText =
              'Error: ${serverState.errorMessage ?? 'Unknown error'}';
          break;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Agent API',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        // ---- Section: Pending Requests (conditional) ----
        if (pendingIntents.isNotEmpty) ...[
          const Text(
            'PENDING REQUESTS',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: BrandColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...pendingIntents.map((intent) => Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  intent.type.summary,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  intent.timeAgo,
                  style: const TextStyle(
                    fontSize: 12,
                    color: BrandColors.textSecondary,
                  ),
                ),
                trailing: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => showSigningPrompt(context, intent.id),
                  child: const Text('Review'),
                ),
              ),
              const Divider(),
            ],
          )),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
        ],

        // ---- Section: Server ----
        const Text(
          'Server',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BrandColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Agent Server'),
          subtitle: const Text(
            'Allow AI agents to connect on localhost:9876',
            style:
                TextStyle(fontSize: 12, color: BrandColors.textSecondary),
          ),
          value: isRunning,
          activeColor: BrandColors.primary,
          onChanged: hasApiKeys && !isLoading
              ? (value) {
                  ref
                      .read(agentServerProvider.notifier)
                      .toggleServer(value);
                }
              : null,
          secondary: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Server status: $statusText',
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 13,
                  color: serverState?.status == ServerStatus.error
                      ? BrandColors.error
                      : BrandColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // ---- Section: API Keys ----
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'API Keys',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BrandColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),

        if (keys.isEmpty)
          _buildEmptyState(context, ref)
        else ...[
          ...keys.map((key) => _buildKeyRow(context, ref, key)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _createKey(context, ref),
              child: const Text('+ Create Key'),
            ),
          ),
          const SizedBox(height: 32),

          // ---- Section: Quick Test ----
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            'Quick Test',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: BrandColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _buildQuickTest(context, keys),
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.lan_outlined,
            size: 48, color: BrandColors.textDisabled),
        const SizedBox(height: 16),
        const Text(
          'Connect AI Agents',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: 320,
          child: Text(
            'AI agents can query your balances, request transactions, and more. Create an API key to get started.',
            style: TextStyle(
                fontSize: 14, color: BrandColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 320,
          child: ElevatedButton(
            onPressed: () => _createKey(context, ref),
            child: const Text('Create Your First Key'),
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildKeyRow(
      BuildContext context, WidgetRef ref, agent_bridge.ApiKeyEntry key) {
    return Dismissible(
      key: ValueKey(key.tokenPrefix),
      direction: DismissDirection.endToStart,
      background: Container(
        color: BrandColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmRevoke(context, ref, key),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(key.label),
        subtitle: Semantics(
          label: 'API key, masked. Tap eye icon to reveal.',
          child: Text(
            key.tokenMasked,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: BrandColors.textSecondary,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Reveal key',
              child: IconButton(
                icon:
                    const Icon(Icons.visibility_outlined, size: 20),
                onPressed: () => _revealKey(context, ref, key),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTest(
      BuildContext context, List<agent_bridge.ApiKeyEntry> keys) {
    const endpoints = [
      '/health',
      '/wallet',
      '/balance',
      '/tokens',
      '/price',
      '/history',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DropdownButton<String>(
              value: _selectedEndpoint,
              underline: const SizedBox.shrink(),
              items: endpoints
                  .map((ep) => DropdownMenuItem(
                        value: ep,
                        child: Text(ep,
                            style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace')),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedEndpoint = value);
                }
              },
            ),
            if (keys.length > 1) ...[
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: _selectedKeyIndex.clamp(0, keys.length - 1),
                underline: const SizedBox.shrink(),
                items: List.generate(
                  keys.length,
                  (i) => DropdownMenuItem(
                    value: i,
                    child: Text(keys[i].label,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedKeyIndex = value);
                  }
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BrandColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BrandColors.border),
          ),
          child: SelectableText(
            _buildCurlCommand(keys),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: BrandColors.textSecondary,
            ),
          ),
        ),
        Row(
          children: [
            const Spacer(),
            Tooltip(
              message: 'Copy to clipboard',
              child: IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => _copyCurlCommand(context, keys),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
