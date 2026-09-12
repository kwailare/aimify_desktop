import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../inventory/data/warehouse_stock_repository.dart';
import '../../purchases/data/purchases_repository.dart';
import '../../staff/data/staff_repository.dart';
import '../../suppliers/data/suppliers_repository.dart';
import '../data/warehouses_repository.dart';
import '../domain/warehouse.dart';
import 'warehouse_form_dialog.dart';

/// UI-only for now: reads from the MOCK [warehousesProvider]. Every other
/// module (Products' stock, Inventory, Suppliers, Purchases, Staff) points
/// at a warehouse by id, so removing one here checks those first rather
/// than silently orphaning records.
class WarehousesScreen extends ConsumerWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehousesProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Warehouses',
              subtitle: '${warehouses.length} independent stock location(s)',
              badge: const MockDataBadge(),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const WarehouseFormDialog(),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add warehouse'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisExtent: 176,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: warehouses.length,
                itemBuilder: (context, index) => _WarehouseCard(warehouse: warehouses[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseCard extends ConsumerWidget {
  const _WarehouseCard({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stockedProductCount = ref
        .watch(warehouseStockProvider)
        .where((row) => row.warehouseId == warehouse.id)
        .length;
    final staffCount =
        ref.watch(staffProvider).where((s) => s.warehouseId == warehouse.id).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    warehouse.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove warehouse',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _confirmRemove(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              warehouse.location,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$stockedProductCount product(s) stocked',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people_outline, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$staffCount staff assigned',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref) {
    final blockers = <String>[];

    final staffHere = ref.read(staffProvider).where((s) => s.warehouseId == warehouse.id).length;
    if (staffHere > 0) blockers.add('$staffHere staff member(s) are assigned here');

    final stockHere =
        ref.read(warehouseStockProvider).where((r) => r.warehouseId == warehouse.id).length;
    if (stockHere > 0) blockers.add('$stockHere product(s) still have stock here');

    final suppliersHere =
        ref.read(suppliersProvider).where((s) => s.warehouseId == warehouse.id).length;
    if (suppliersHere > 0) blockers.add('$suppliersHere supplier(s) are linked here');

    final purchasesHere =
        ref.read(purchasesProvider).where((p) => p.warehouseId == warehouse.id).length;
    if (purchasesHere > 0) blockers.add('$purchasesHere purchase order(s) reference it');

    if (blockers.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Can't remove this warehouse yet"),
          content: Text(
            "${warehouse.name} still has:\n\n"
            '${blockers.map((b) => '• $b').join('\n')}\n\n'
            'Reassign or clear these first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove warehouse?'),
        content: Text('${warehouse.name} has nothing linked to it and can be safely removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(warehousesProvider.notifier).removeWarehouse(warehouse.id);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
