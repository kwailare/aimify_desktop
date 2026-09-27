import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/offline/outbox.dart';
import '../../shared/utils/formatters.dart';
import '../inventory/domain/stock_movement.dart';
import '../products/data/products_repository.dart';
import 'sync_engine.dart';

/// Everything saved on this computer that hasn't reached the server yet —
/// changes still waiting for a good connection, and any the server refused
/// (a duplicate SKU, a role or plan limit...), which the person can retry or
/// discard. Nothing recorded offline disappears without being seen here.
class PendingChangesDialog extends ConsumerWidget {
  const PendingChangesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ops = ref.watch(outboxOpsProvider);
    final syncing = ref.watch(syncEngineProvider).syncing;
    final names = {for (final p in ref.watch(productListProvider)) p.id: p.name};

    return AlertDialog(
      title: const Text('Changes waiting to sync'),
      content: SizedBox(
        width: 520,
        child: ops.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Everything is synced. Nothing is waiting.'),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final op in ops)
                      _OpTile(op: op, description: describeOp(op, names), theme: theme),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (ops.any((o) => !o.failed))
          ElevatedButton.icon(
            onPressed: syncing ? null : () => ref.read(syncEngineProvider.notifier).syncNow(),
            icon: syncing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 18),
            label: Text(syncing ? 'Syncing…' : 'Sync now'),
          ),
      ],
    );
  }
}

/// A short, plain description of one queued change.
String describeOp(OutboxOp op, Map<String, String> productNames) {
  String product(String? id) =>
      (id == null ? null : productNames[id]) ?? 'a product';

  switch (op.kind) {
    case OpKind.movement:
      final quantity = (op.payload['quantity'] as num).toInt();
      final type = StockMovementTypeX.fromApi(op.payload['type'] as String);
      return '${type.label} ${quantity > 0 ? '+' : ''}$quantity · ${product(op.payload['productId'] as String?)}';
    case OpKind.productCreate:
      final input = op.payload['input'] as Map;
      return 'New product · ${input['name']} (${input['sku']})';
    case OpKind.productUpdate:
      final input = op.payload['input'] as Map;
      return 'Edit product · ${input['name']}';
    case OpKind.productArchive:
      return 'Archive · ${product(op.payload['id'] as String?)}';
  }
}

class _OpTile extends ConsumerWidget {
  const _OpTile({required this.op, required this.description, required this.theme});

  final OutboxOp op;
  final String description;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outbox = ref.read(outboxProvider.notifier);
    final failed = op.failed;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: failed ? theme.colorScheme.error.withValues(alpha: 0.06) : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: failed
              ? theme.colorScheme.error.withValues(alpha: 0.35)
              : theme.colorScheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.schedule,
            size: 18,
            color: failed ? theme.colorScheme.error : theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  'Recorded ${dateFormat.format(op.createdAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                if (failed) ...[
                  const SizedBox(height: 4),
                  Text(op.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12.5)),
                ] else
                  Text(
                    'Waiting for a good connection',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
          if (failed) ...[
            TextButton(
              onPressed: () async {
                await outbox.replace(op.copyWith(clearError: true));
                await ref.read(syncEngineProvider.notifier).syncNow();
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () => outbox.removeWhere(
                // Discarding a product that never reached the server also
                // discards the changes that were waiting on it.
                (o) =>
                    o.id == op.id ||
                    (op.kind == OpKind.productCreate &&
                        (o.payload['productId'] == op.localProductId ||
                            o.payload['id'] == op.localProductId)),
              ),
              child: const Text('Discard'),
            ),
          ],
        ],
      ),
    );
  }
}
