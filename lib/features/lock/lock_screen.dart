import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../theme/brand_theme.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  bool _obscureText = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Countdown state for escalating delay
  int _countdown = 0;
  Timer? _countdownTimer;

  // Shake animation
  late final AnimationController _shakeController;
  late final Animation<Offset> _shakeAnimation;

  // Border flash state
  bool _flashError = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _shakeAnimation = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: const Offset(0.02, 0)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: const Offset(0.02, 0),
          end: const Offset(-0.02, 0),
        ),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: const Offset(-0.02, 0),
          end: const Offset(0.02, 0),
        ),
        weight: 2,
      ),
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0.02, 0), end: Offset.zero),
        weight: 1,
      ),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.linear,
    ));
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _shakeController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_isLoading || _countdown > 0) return;

    final password = _passwordController.text;
    if (password.isEmpty) return;

    // Begin loading
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authProvider.notifier).unlock(password);
      // On success: GoRouter redirect takes over navigation automatically.
    } catch (e) {
      // Wrong password: record attempt, trigger shake + flash
      ref.read(authProvider.notifier).recordFailedAttempt();
      _shakeController.forward(from: 0);

      // Start escalating delay countdown for the NEXT attempt
      final updatedState = ref.read(authProvider);
      final delay = AuthNotifier.delayForAttempt(updatedState.failedAttempts);
      if (delay > 0) {
        _startCountdown(delay);
      }

      setState(() {
        _errorMessage = 'Incorrect password';
        _flashError = true;
        _isLoading = false;
      });
      // Reset border flash after 600ms
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() => _flashError = false);
        }
      });
    }

    // Clear password field after each attempt
    _passwordController.clear();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() => _countdown = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _countdown = 0;
          timer.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Deadbolt logomark
                Image.asset(
                  'assets/deadbolt_logomark.png',
                  height: 80,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (_, __, _) => const Icon(
                    Icons.lock,
                    size: 64,
                    color: BrandColors.primary,
                  ),
                ),
                const SizedBox(height: 48),
                const Text(
                  'Deadbolt',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: BrandColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your self-custodial Solana wallet',
                  style: TextStyle(
                    fontSize: 16,
                    color: BrandColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),
                // Password field with shake animation
                SlideTransition(
                  position: _shakeAnimation,
                  child: TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscureText,
                    autofocus: true,
                    onSubmitted: (_) => _onSubmit(),
                    decoration: InputDecoration(
                      hintText: 'Enter password',
                      filled: true,
                      fillColor: BrandColors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _flashError
                              ? BrandColors.error
                              : BrandColors.border,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _flashError
                              ? BrandColors.error
                              : BrandColors.border,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: _flashError
                              ? BrandColors.error
                              : BrandColors.primary,
                          width: 2,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureText
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: BrandColors.textSecondary,
                        ),
                        onPressed: () {
                          setState(() => _obscureText = !_obscureText);
                        },
                        tooltip: _obscureText ? 'Show password' : 'Hide password',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Delay countdown message area
                SizedBox(
                  height: 20,
                  child: _countdown > 0
                      ? Text(
                          'Please wait ${_countdown}s before trying again',
                          style: const TextStyle(
                            fontSize: 14,
                            color: BrandColors.warning,
                          ),
                        )
                      : _errorMessage != null
                          ? Text(
                              _errorMessage!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: BrandColors.error,
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
                const SizedBox(height: 8),
                // Unlock button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _countdown > 0) ? null : _onSubmit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
