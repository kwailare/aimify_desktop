import 'package:flutter/material.dart';

import '../utils/friendly_error.dart';

/// What a screen shows in place of its content when the first load is
/// still running.
class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 14),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A load failure, in plain words, with a retry — never raw JSON.
class ErrorRetryCard extends StatelessWidget {
  const ErrorRetryCard({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.error.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.error),
            const SizedBox(width: 14),
            Expanded(child: Text(friendlyError(error))),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a failure as a snackbar — for actions (archive, disable, record)
/// that have no inline place to put an error.
void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(friendlyError(error))));
}
