import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/aimify_wordmark.dart';
import '../../auth/presentation/auth_controller.dart';

/// Shown instead of the app shell when the signed-in organization's
/// `subscriptionStatus` is `pending`, `expired`, `cancelled` or `suspended`
/// (see `Organization.isLocked` and "Subscription gating" in
/// `docs/desktop-api.md`). `trial`, `active` and `past_due` are NOT locked —
/// `past_due` just shows a warning banner elsewhere (see `dashboard_hero.dart`).
///
/// `/auth/login` and `/me` aren't gated server-side, so a locked-out person
/// can still sign in and see exactly why here, rather than a confusing
/// string of failed requests once they reach the real app.
class SubscriptionLockedScreen extends ConsumerWidget {
  const SubscriptionLockedScreen({super.key});

  static const _messages = {
    'pending': "Your subscription is still being set up. This usually clears up "
        "shortly — check the billing page for details, or try again in a moment.",
    'expired': 'Your free trial has ended. Subscribe on the Aimify website to keep '
        'using the desktop app.',
    'cancelled': 'Your subscription was cancelled. Resubscribe on the Aimify '
        'website to keep using the desktop app.',
    'suspended': 'Your account has been suspended. Check the billing page for '
        'details, or contact Aimify support.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(authControllerProvider).valueOrNull;
    final status = me?.organization?.subscriptionStatus ?? 'expired';
    final message = _messages[status] ?? _messages['expired']!;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AimifyWordmark(fontSize: 26),
                const SizedBox(height: 28),
                Icon(Icons.lock_clock_outlined, size: 44, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Your subscription needs attention',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(ApiConstants.billingUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open billing page'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.read(authControllerProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check again'),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
