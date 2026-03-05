import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/address_book_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../shared/formatters.dart';
import '../../theme/brand_theme.dart';

class AddressBookScreen extends ConsumerStatefulWidget {
  const AddressBookScreen({super.key});

  @override
  ConsumerState<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends ConsumerState<AddressBookScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(addressBookProvider);
    final wallets = ref.watch(walletListProvider).valueOrNull ?? [];
    final q = _searchQuery.toLowerCase();

    final filteredContacts = _searchQuery.isEmpty
        ? contacts
        : contacts.where((c) {
            return c.tag.toLowerCase().contains(q) ||
                c.address.toLowerCase().contains(q);
          }).toList();

    final filteredWallets = _searchQuery.isEmpty
        ? wallets
        : wallets.where((w) {
            return w.name.toLowerCase().contains(q) ||
                w.address.toLowerCase().contains(q);
          }).toList();

    final hasResults = filteredContacts.isNotEmpty || filteredWallets.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Address Book',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
            FilledButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Contact'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by tag or address',
            hintStyle: const TextStyle(color: BrandColors.textSecondary),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        const SizedBox(height: 16),
        if (contacts.isEmpty && wallets.isEmpty)
          _emptyState(context)
        else if (!hasResults)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text('No contacts match your search',
                  style: TextStyle(color: BrandColors.textSecondary)),
            ),
          )
        else ...[
          // Your Wallets section
          if (filteredWallets.isNotEmpty) ...[
            const Text('Your Wallets',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BrandColors.textSecondary)),
            const SizedBox(height: 8),
            ...filteredWallets.map((w) => _walletRow(context, w.name, w.address)),
            const SizedBox(height: 20),
          ],
          // Contacts section
          if (filteredContacts.isNotEmpty) ...[
            const Text('Contacts',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: BrandColors.textSecondary)),
            const SizedBox(height: 8),
            ...filteredContacts.map((contact) {
              final index = contacts.indexOf(contact);
              return _contactRow(context, contact, index);
            }),
          ],
        ],
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts_outlined,
                size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('No contacts yet',
                style: TextStyle(
                    fontSize: 18, color: BrandColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Contact'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactRow(BuildContext context, Contact contact, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(contact.tag,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          Formatters.shortAddress(contact.address),
          style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: BrandColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy address',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: contact.address));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Address copied'),
                      duration: Duration(seconds: 1)),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              tooltip: 'Edit',
              onPressed: () => _showEditDialog(context, contact, index),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Delete',
              onPressed: () => _showDeleteDialog(context, contact, index),
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletRow(BuildContext context, String name, String address) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined,
            size: 20, color: BrandColors.textSecondary),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          Formatters.shortAddress(address),
          style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: BrandColors.textSecondary),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy address',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Address copied'),
                  duration: Duration(seconds: 1)),
            );
          },
        ),
      ),
    );
  }

  // ─── Dialogs ───

  Future<void> _showAddDialog(BuildContext context) async {
    final tagController = TextEditingController();
    final addressController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Contact'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tagController,
                  autofocus: true,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Tag',
                    hintText: 'e.g. Alice',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Solana Address',
                    hintText: 'Base58 address',
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final result = await ref
                    .read(addressBookProvider.notifier)
                    .addContact(
                        tagController.text, addressController.text.trim());
                if (result != null) {
                  setDialogState(() => errorText = result);
                } else {
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    tagController.dispose();
    addressController.dispose();
  }

  Future<void> _showEditDialog(
      BuildContext context, Contact contact, int index) async {
    final tagController = TextEditingController(text: contact.tag);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Contact'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tagController,
                autofocus: true,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Tag'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller:
                    TextEditingController(text: contact.address),
                readOnly: true,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: BrandColors.textSecondary),
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(addressBookProvider.notifier)
                  .updateContact(index, tagController.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    tagController.dispose();
  }

  Future<void> _showDeleteDialog(
      BuildContext context, Contact contact, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('Remove "${contact.tag}" from your address book?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BrandColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(addressBookProvider.notifier).deleteContact(index);
    }
  }
}
