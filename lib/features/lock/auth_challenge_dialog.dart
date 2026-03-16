import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/rust/api/auth.dart' as auth_bridge;
import '../../theme/brand_theme.dart';

/// Shows auth challenge dialog. Returns true if password verified, false if cancelled.
Future<bool> showAuthChallengeDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AuthChallengeDialog(),
  );
  return result ?? false;
}

/// Modal dialog that challenges the user to re-enter their app password before
/// allowing access to a sensitive operation (e.g. reveal seed phrase, API key management).
class AuthChallengeDialog extends ConsumerStatefulWidget {
  const AuthChallengeDialog({super.key});

  @override
  ConsumerState<AuthChallengeDialog> createState() =>
      _AuthChallengeDialogState();
}

class _AuthChallengeDialogState extends ConsumerState<AuthChallengeDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await auth_bridge.verifyAppPassword(password: _passwordController.text);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      setState(() {
        _error = 'Incorrect password. Please try again.';
        _loading = false;
      });
      _passwordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Confirm Password',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your app password to continue.',
            style: TextStyle(fontSize: 14, color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Password',
              suffixIcon: Semantics(
                label: _obscure ? 'Show password' : 'Hide password',
                child: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            onSubmitted: (_) => _loading ? null : _verify(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 14,
                  color: BrandColors.error,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Go Back'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _verify,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}
