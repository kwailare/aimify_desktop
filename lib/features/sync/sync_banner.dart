import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/offline/connection.dart';
import '../../shared/offline/outbox.dart';
import '../auth/presentation/auth_controller.dart';
import 'pending_changes_dialog.dart';
import 'sync_engine.dart';

/// Tells the person, across the top of every screen, when the app is not
/// running against a healthy connection — and what that means for their
/// work: changes are saved on this computer and sync by themselves.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = ref.watch(connectionProvider);
    final pending = ref.watch(pendingCountProvider);
    final failed = ref.watch(failedOpsProvider).length;
    final syncing = ref.watch(syncEngineProvider).syncing;
    final staleSince = ref.watch(staleSinceProvider);
    final signedIn = ref.watch(sessionUserIdProvider) != null;
    if (!signedIn) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final saved = staleSince == null
        ? ''
        : ' Showing saved data from ${DateFormat.Hm().format(staleSince)}.';
    final waiting = pending == 0 ? '' : ' $pending change(s) waiting.';

    final banners = <Widget>[
      if (failed > 0)
        _Banner(
          color: scheme.error,
          icon: Icons.error_outline,
          text: '$failed change(s) could not be synced — the server refused them.',
          action: 'Review',
          onAction: () => showDialog(context: context, builder: (_) => const PendingChangesDialog()),
        ),
      if (quality == ConnectionQuality.offline)
        _Banner(
          color: scheme.error,
          icon: Icons.wifi_off_rounded,
          text: "You're offline. Changes are saved on this computer and sync automatically "
              'when the connection is back.$waiting$saved',
          action: 'Try again',
          onAction: () => ref.read(syncEngineProvider.notifier).syncNow(),
        )
      else if (quality == ConnectionQuality.poor)
        _Banner(
          color: scheme.secondary,
          icon: Icons.network_wifi_1_bar_rounded,
          text: 'Poor connection. Changes are saved on this computer and sync when it '
              'improves.$waiting$saved',
          action: 'Try again',
          onAction: () => ref.read(syncEngineProvider.notifier).syncNow(),
        )
      else if (syncing || pending > 0)
        _Banner(
          color: scheme.primary,
          icon: Icons.sync_rounded,
          text: 'Syncing $pending change(s)…',
          busy: true,
        ),
    ];

    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: banners);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
    this.busy = false,
  });

  final Color color;
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      ),
    );
  }
}
