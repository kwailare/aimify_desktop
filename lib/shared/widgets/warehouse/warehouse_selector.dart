import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/warehouses/data/warehouses_repository.dart';

/// Dropdown for filtering a screen to one warehouse, or "All warehouses."
/// Drives [selectedWarehouseIdProvider], which every warehouse-scoped
/// screen (Products, Inventory, Suppliers, Purchases, Reports) reads from.
///
/// This is an admin-facing stand-in for what will eventually be automatic
/// once staff sign-in exists: a staff member would see their one assigned
/// warehouse here, fixed, instead of a free-choice dropdown.
class WarehouseSelector extends ConsumerWidget {
  const WarehouseSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehousesProvider);
    final rawSelected = ref.watch(selectedWarehouseIdProvider);
    final theme = Theme.of(context);

    // Defensive: `DropdownButton` crashes if `value` doesn't exactly match
    // one of `items` — fall back to "All warehouses" rather than propagate
    // a stale id (e.g. a warehouse removed elsewhere) into a hard crash.
    final selected =
        warehouses.any((w) => w.id == rawSelected) ? rawSelected : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(maxWidth: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.expand_more, size: 18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          // The button itself always shows single-line, ellipsized text
          // (long warehouse names shouldn't force this control wider than
          // its 200px cap) — the open menu below still shows each item's
          // full name via the plain `items` list.
          selectedItemBuilder: (context) => [
            const Text('All warehouses', overflow: TextOverflow.ellipsis),
            for (final warehouse in warehouses)
              Text(warehouse.name, overflow: TextOverflow.ellipsis),
          ],
          items: [
            const DropdownMenuItem(value: null, child: Text('All warehouses')),
            for (final warehouse in warehouses)
              DropdownMenuItem(value: warehouse.id, child: Text(warehouse.name)),
          ],
          onChanged: (value) => ref.read(selectedWarehouseIdProvider.notifier).state = value,
        ),
      ),
    );
  }
}
