import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/onboarding_provider.dart';
import '../../../theme/brand_theme.dart';
import '../../lock/widgets/password_strength_meter.dart';

class SetPasswordStep extends ConsumerStatefulWidget {
  const SetPasswordStep({super.key});

  @override
  ConsumerState<SetPasswordStep> createState() => _SetPasswordStepState();
}

class _SetPasswordStepState extends ConsumerState<SetPasswordStep> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _hasAttemptedSubmit = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _passwordController.text.length >= 8 &&
      _passwordController.text == _confirmController.text &&
      !_loading;

  Future<void> _onContinue() async {
    setState(() {
      _hasAttemptedSubmit = true;
    });

    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 8) {
      setState(() {
        _error = 'Password must be at least 8 characters';
      });
      return;
    }

    if (password != confirm) {
      setState(() {
        _error = 'Passwords do not match';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref
          .read(onboardingStateProvider.notifier)
          .advanceFromPassword(password);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Create App Password',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Protects your wallet on this device. Cannot be recovered if forgotten.',
            style: TextStyle(fontSize: 16, color: BrandColors.textSecondary),
          ),
          const SizedBox(height: 32),

          // Password field
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: Semantics(
                label: _obscurePassword ? 'Show password' : 'Hide password',
                child: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Strength meter
          PasswordStrengthMeter(password: _passwordController.text),

          const SizedBox(height: 12),

          // Confirm password field
          TextField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              suffixIcon: Semantics(
                label: _obscureConfirm ? 'Show password' : 'Hide password',
                child: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
          ),

          // Error text area
          if (_hasAttemptedSubmit && _error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 14,
                color: BrandColors.error,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Continue button
          Opacity(
            opacity: _canContinue ? 1.0 : 0.5,
            child: ElevatedButton(
              onPressed: _canContinue ? _onContinue : null,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}
