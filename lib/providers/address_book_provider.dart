import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/validators.dart';

class Contact {
  final String tag;
  final String address;

  const Contact({required this.tag, required this.address});

  Map<String, dynamic> toJson() => {'tag': tag, 'address': address};

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        tag: json['tag'] as String,
        address: json['address'] as String,
      );
}

class AddressBookNotifier extends Notifier<List<Contact>> {
  static const _prefsKey = 'address_book_contacts';

  @override
  List<Contact> build() {
    _loadFromPrefs();
    return [];
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Contact.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {
      // Corrupted data — start fresh
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(state.map((c) => c.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  /// Returns null on success, or an error message.
  Future<String?> addContact(String tag, String address) async {
    if (tag.trim().isEmpty) return 'Tag is required';
    if (!isValidSolanaAddress(address)) return 'Invalid Solana address';
    if (state.any((c) => c.address == address)) return 'Address already exists';

    state = [...state, Contact(tag: tag.trim(), address: address)];
    await _saveToPrefs();
    return null;
  }

  Future<void> updateContact(int index, String tag) async {
    if (index < 0 || index >= state.length) return;
    final updated = List<Contact>.from(state);
    updated[index] = Contact(tag: tag.trim(), address: updated[index].address);
    state = updated;
    await _saveToPrefs();
  }

  Future<void> deleteContact(int index) async {
    if (index < 0 || index >= state.length) return;
    final updated = List<Contact>.from(state);
    updated.removeAt(index);
    state = updated;
    await _saveToPrefs();
  }
}

final addressBookProvider =
    NotifierProvider<AddressBookNotifier, List<Contact>>(
  AddressBookNotifier.new,
);
