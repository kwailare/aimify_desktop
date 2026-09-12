import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_info.dart';
import '../../../shared/widgets/aimify_wordmark.dart';

class _Credit {
  const _Credit(this.name, this.purpose);

  final String name;
  final String purpose;
}

const _packageCredits = [
  _Credit('Flutter', 'UI toolkit this app is built with'),
  _Credit('flutter_riverpod', 'State management and dependency injection'),
  _Credit('go_router', 'Declarative routing and the sidebar shell'),
  _Credit('flutter_secure_storage', 'OS-native secure storage for the auth token'),
  _Credit('google_fonts', 'Space Grotesk and Manrope, the Aimify brand typefaces'),
  _Credit('http', 'Networking against the aimify-web API'),
  _Credit('intl', 'Currency and date formatting'),
];

/// Standalone "About / Credits" page. Reachable from the login screen (for
/// signed-out visitors) and from the sidebar footer once signed in — see
/// `core/router/app_router.dart` for why it's exempt from the auth redirect.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('Credits'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AimifyWordmark(fontSize: 30)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Aimify Desktop · v${AppInfo.version}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Multi-tenant inventory and warehouse management for wholesalers, '
                  'distributors and retailers. This desktop app is the day-to-day product; '
                  'account signup, organizations and billing are handled on the Aimify website.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Built with', style: theme.textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final credit in _packageCredits)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  credit.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  credit.purpose,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '© ${DateTime.now().year} Aimify',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
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
