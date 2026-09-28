import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/offline/connection.dart';
import '../../shared/offline/outbox.dart';
import 'pending_changes_dialog.dart';
import 'sync_engine.dart';

/// A one-line connection and sync status for the sidebar: a coloured dot,
/// what it means, and how many changes are waiting. Tapping it opens the
/// list of waiting changes.
class SyncStatusTile extends ConsumerWidget {
  const SyncStatusTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final quality = ref.watch(connectionProvider);
    final pending = ref.watch(pendingCountProvider);
    final failed = ref.watch(failedOpsProvider).length;
    final syncing = ref.watch(syncEngineProvider).syncing;

    final (color, label) = switch (quality) {
      ConnectionQuality.good => (
          const Color(0xFF2F8F5B),
          syncing ? 'Syncing…' : (pending > 0 ? 'Online' : 'Online · synced'),
        ),
      ConnectionQuality.poor => (theme.colorScheme.secondary, 'Poor connection'),
      ConnectionQuality.offline => (theme.colorScheme.error, 'Offline'),
    };
    final extra = [
      if (pending > 0) '$pending waiting',
      if (failed > 0) '$failed refused',
    ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showDialog(context: context, builder: (_) => const PendingChangesDialog()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                extra.isEmpty ? label : '$label · $extra',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
