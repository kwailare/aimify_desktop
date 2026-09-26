import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/services/authed_api.dart';
import '../../../shared/widgets/aimify_wordmark.dart';
import 'auth_controller.dart';
import 'widgets/login_brand_panel.dart';

/// Real, network-backed login screen — calls `POST /api/v1/auth/login` via
/// [AuthController.login]. On success, the router's redirect (see
/// `core/router/app_router.dart`) takes the user to the dashboard.
///
/// Handles two-factor authentication: a correct password on an account with
/// 2FA on gets a `two_factor_required` error with no token, so this screen
/// swaps to a 6-digit-code step and resubmits with `code` once entered.
///
/// Split-screen layout above [_wideBreakpoint]: a dark illustrated brand
/// panel ([LoginBrandPanel]) paired with a glass-morphism form card. Below
/// that width the brand panel drops out and the form becomes the whole
/// screen, still on the same warm gradient backdrop.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _needsTwoFactor = false;
  String? _errorMessage;

  static const _wideBreakpoint = 900.0;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _entrance.forward();

    // A session that ended on its own (revoked from the website, removed
    // from the team, ...) lands here with a short explanation, shown once.
    final endedMessage = ref.read(sessionEndedMessageProvider);
    if (endedMessage != null) {
      _errorMessage = endedMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(sessionEndedMessageProvider.notifier).state = null;
      });
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _backToCredentials() {
    setState(() {
      _needsTwoFactor = false;
      _codeController.clear();
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (!_needsTwoFactor) {
      if (!_formKey.currentState!.validate()) return;
    } else if (_codeController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Enter your 6-digit code, or a backup code');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            code: _needsTwoFactor ? _codeController.text.trim() : null,
          );
    } on ApiException catch (e) {
      if (e.isTwoFactorRequired) {
        setState(() => _needsTwoFactor = true);
      } else if (e.isRateLimited) {
        // Per docs/desktop-api.md: wrong passwords/codes are rate limited.
        // Never auto-retry — just tell the person to wait and let them
        // decide when to try again.
        setState(() => _errorMessage = 'Too many attempts. Try again in a few minutes.');
      } else {
        setState(() => _errorMessage = e.message);
      }
    } catch (_) {
      setState(
        () => _errorMessage =
            'Could not reach the Aimify server. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -0.9),
            radius: 1.4,
            colors: isDark
                ? [const Color(0xFF241C0E), const Color(0xFF171717)]
                : [const Color(0xFFFFF3DA), const Color(0xFFFDF7EC)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= _wideBreakpoint;
            final formPanel = Center(
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: _LoginFormCard(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      codeController: _codeController,
                      obscurePassword: _obscurePassword,
                      onToggleObscure: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      isSubmitting: _isSubmitting,
                      errorMessage: _errorMessage,
                      onSubmit: _submit,
                      showCompactBrand: !isWide,
                      needsTwoFactor: _needsTwoFactor,
                      onBackToCredentials: _backToCredentials,
                    ),
                  ),
                ),
              ),
            );

            if (!isWide) return formPanel;

            return Row(
              children: [
                const Expanded(flex: 5, child: LoginBrandPanel()),
                Expanded(flex: 4, child: formPanel),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginFormCard extends StatelessWidget {
  const _LoginFormCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.codeController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onSubmit,
    required this.showCompactBrand,
    required this.needsTwoFactor,
    required this.onBackToCredentials,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController codeController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final bool showCompactBrand;
  final bool needsTwoFactor;
  final VoidCallback onBackToCredentials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gold = isDark ? const Color(0xFFF2B233) : const Color(0xFFD88B00);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCompactBrand) ...[
            Center(child: AimifyWordmark(fontSize: 26, inkColor: theme.textTheme.bodyLarge?.color)),
            const SizedBox(height: 24),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.55 : 0.72),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: gold.withValues(alpha: 0.22)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                      blurRadius: 48,
                      offset: const Offset(0, 24),
                    ),
                  ],
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        needsTwoFactor ? 'VERIFICATION REQUIRED' : 'WELCOME BACK',
                        style: TextStyle(
                          color: gold,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        needsTwoFactor
                            ? 'Enter your authentication code'
                            : 'Sign in to your warehouse',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (needsTwoFactor) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Enter the 6-digit code from your authenticator app, or one of '
                          'your backup codes.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (!needsTwoFactor) ...[
                        _BrandTextField(
                          controller: emailController,
                          label: 'Email',
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter your email address';
                            }
                            if (!value.contains('@')) return 'Enter a valid email address';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _BrandTextField(
                          controller: passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => onSubmit(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                            onPressed: onToggleObscure,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter your password';
                            }
                            return null;
                          },
                        ),
                      ] else
                        _BrandTextField(
                          controller: codeController,
                          label: '6-digit code or backup code',
                          icon: Icons.security_outlined,
                          keyboardType: TextInputType.text,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          onFieldSubmitted: (_) => onSubmit(),
                        ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 18,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: TextStyle(color: theme.colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      _GradientSubmitButton(
                        isBusy: isSubmitting,
                        onPressed: onSubmit,
                        label: needsTwoFactor ? 'Verify' : 'Sign in',
                      ),
                      const SizedBox(height: 20),
                      if (needsTwoFactor)
                        Center(
                          child: TextButton(
                            onPressed: isSubmitting ? null : onBackToCredentials,
                            child: const Text('Back to sign in'),
                          ),
                        )
                      else ...[
                        Text(
                          "Don't have an account? Sign up at the Aimify website first, "
                          'then come back here to sign in.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandTextField extends StatelessWidget {
  const _BrandTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.suffixIcon,
    this.onFieldSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final Widget? suffixIcon;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gold = isDark ? const Color(0xFFF2B233) : const Color(0xFFD88B00);

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: theme.colorScheme.surface.withValues(alpha: isDark ? 0.35 : 0.65),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: gold, width: 1.6),
        ),
      ),
    );
  }
}

/// Pill submit button with a hover-driven gradient sweep — a small nod to
/// the `.hero-primary:hover` treatment on aimify-web, made possible here by
/// a real desktop cursor (there's no touch-equivalent, so this is purely a
/// pointer/desktop enhancement, not something the mobile phase can reuse).
class _GradientSubmitButton extends StatefulWidget {
  const _GradientSubmitButton({
    required this.isBusy,
    required this.onPressed,
    required this.label,
  });

  final bool isBusy;
  final VoidCallback onPressed;
  final String label;

  @override
  State<_GradientSubmitButton> createState() => _GradientSubmitButtonState();
}

class _GradientSubmitButtonState extends State<_GradientSubmitButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.brightness == Brightness.dark
        ? const Color(0xFFF8F7F3)
        : const Color(0xFF242424);
    const goldVivid = Color(0xFFFF9D0A);
    const amberBright = Color(0xFFFFC94D);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isBusy ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: _hovering ? [goldVivid, amberBright] : [ink, ink],
            ),
            boxShadow: _hovering
                ? [BoxShadow(color: goldVivid.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))]
                : [],
          ),
          alignment: Alignment.center,
          child: widget.isBusy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: theme.scaffoldBackgroundColor,
                  ),
                )
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: _hovering ? Colors.white : theme.scaffoldBackgroundColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
        ),
      ),
    );
  }
}
