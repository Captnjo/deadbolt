import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../src/rust/api/auth.dart' as auth_bridge;
import '../../theme/brand_theme.dart';
import '../lock/widgets/password_strength_meter.dart';

/// Security section for the Settings screen.
///
/// Provides:
/// - Change Password (requires current password, validates new >= 8 chars)
/// - Auto-Lock Timeout dropdown (5 min / 15 min / 30 min / 1 hour / Never)
/// - Lock Now button (immediately locks the app via AuthProvider)
class SecuritySettingsSection extends ConsumerStatefulWidget {
  const SecuritySettingsSection({super.key});

  @override
  ConsumerState<SecuritySettingsSection> createState() =>
      _SecuritySettingsSectionState();
}

class _SecuritySettingsSectionState
    extends ConsumerState<SecuritySettingsSection> {
  static const Map<int, String> _timeoutOptions = {
    300: '5 minutes',
    900: '15 minutes',
    1800: '30 minutes',
    3600: '1 hour',
    0: 'Never',
  };

  void _showChangePasswordDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => const _ChangePasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTimeout = ref.watch(idleTimeoutSecondsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Security',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: BrandColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),

        // Change Password
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Change Password',
              style: TextStyle(fontSize: 14)),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showChangePasswordDialog,
        ),

        // Auto-Lock Timeout
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-Lock Timeout',
              style: TextStyle(fontSize: 14)),
          trailing: DropdownButton<int>(
            value: _timeoutOptions.containsKey(currentTimeout)
                ? currentTimeout
                : 900,
            underline: const SizedBox.shrink(),
            items: _timeoutOptions.entries
                .map(
                  (e) => DropdownMenuItem<int>(
                    value: e.key,
                    child: Text(e.value,
                        style: const TextStyle(fontSize: 14)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setIdleTimeout(ref, value);
              }
            },
          ),
        ),

        const SizedBox(height: 12),

        // Lock Now
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Lock Now'),
            onPressed: () {
              ref.read(authProvider.notifier).lock();
            },
          ),
        ),
      ],
    );
  }
}

/// Internal dialog for changing the app password.
/// Validates current password via FFI before accepting a new one.
class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState
    extends ConsumerState<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _currentObscure = true;
  bool _newObscure = true;
  bool _confirmObscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final current = _currentController.text;
    final newPw = _newController.text;
    final confirm = _confirmController.text;

    // Validate locally first
    if (newPw.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (newPw != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await auth_bridge.changeAppPassword(
        current: current,
        newPassword: newPw,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      setState(() {
        _error = 'Current password is incorrect.';
        _loading = false;
      });
      _currentController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final newPw = _newController.text;

    return AlertDialog(
      title: const Text(
        'Change Password',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current password
            TextField(
              controller: _currentController,
              obscureText: _currentObscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Current Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _currentObscure
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _currentObscure = !_currentObscure),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // New password
            TextField(
              controller: _newController,
              obscureText: _newObscure,
              decoration: InputDecoration(
                labelText: 'New Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _newObscure
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _newObscure = !_newObscure),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            PasswordStrengthMeter(password: newPw),
            const SizedBox(height: 12),

            // Confirm new password
            TextField(
              controller: _confirmController,
              obscureText: _confirmObscure,
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _confirmObscure
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _confirmObscure = !_confirmObscure),
                ),
              ),
              onSubmitted: (_) => _loading ? null : _save(),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
