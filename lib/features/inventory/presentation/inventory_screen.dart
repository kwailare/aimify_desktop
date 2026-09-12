import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../../shared/widgets/warehouse/warehouse_selector.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/inventory_repository.dart';
import '../data/low_stock_view.dart';
import '../domain/stock_movement.dart';
import 'stock_movement_dialog.dart';

enum _TypeFilter { all, stockIn, stockOut, adjustment }

extension on _TypeFilter {
  String get label => switch (this) {
        _TypeFilter.all => 'All types',
        _TypeFilter.stockIn => 'Stock in',
        _TypeFilter.stockOut => 'Stock out',
        _TypeFilter.adjustment => 'Adjustment',
      };

  StockMovementType? get asMovementType => switch (this) {
        _TypeFilter.all => null,
        _TypeFilter.stockIn => StockMovementType.stockIn,
        _TypeFilter.stockOut => StockMovementType.stockOut,
        _TypeFilter.adjustment => StockMovementType.adjustment,
      };
}

/// UI-only for now: reads from the MOCK [inventoryProvider] and
/// [scopedLowStockProvider]. See those files for what a real API swap
/// would need. This is also where a staff member's stock-out action would
/// live once staff sign-in exists — see `selectedWarehouseIdProvider`.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  _TypeFilter _typeFilter = _TypeFilter.all;
  bool _sortNewestFirst = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warehouseId = ref.watch(selectedWarehouseIdProvider);
    final isAllWarehouses = warehouseId == null;

    final scoped = ref.watch(inventoryProvider).where((m) {
      return isAllWarehouses || m.warehouseId == warehouseId;
    }).toList();

    final lowStock = ref.watch(scopedLowStockProvider);

    var movements = scoped.where((m) {
      if (_typeFilter.asMovementType != null && m.type != _typeFilter.asMovementType) return false;
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return m.productName.toLowerCase().contains(q) || m.reason.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => _sortNewestFirst ? b.date.compareTo(a.date) : a.date.compareTo(b.date));

    final stockInTotal = scoped
        .where((m) => m.type == StockMovementType.stockIn)
        .fold(0, (sum, m) => sum + m.quantity);
    final stockOutTotal = scoped
        .where((m) => m.type == StockMovementType.stockOut)
        .fold(0, (sum, m) => sum + m.quantity);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Inventory',
              subtitle: 'Stock levels and movement history, per warehouse',
              badge: const MockDataBadge(),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const StockMovementDialog(),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Record movement'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisExtent: 156,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: 3,
              itemBuilder: (context, index) => switch (index) {
                0 => StatCard(
                    label: 'Movements in scope',
                    value: '${scoped.length}',
                    icon: Icons.receipt_long_outlined,
                  ),
                1 => StatCard(
                    label: 'Stock in',
                    value: '$stockInTotal',
                    caption: 'Units received',
                    icon: Icons.arrow_downward_rounded,
                    accentColor: const Color(0xFF2F8F5B),
                  ),
                _ => StatCard(
                    label: 'Stock out',
                    value: '$stockOutTotal',
                    caption: 'Units dispatched',
                    icon: Icons.arrow_upward_rounded,
                    accentColor: theme.colorScheme.error,
                  ),
              },
            ),
            const SizedBox(height: 20),
            // A single Wrap for the whole toolbar, `WarehouseSelector`
            // included — see the matching comment in products_screen.dart
            // for why `Row(Expanded(Wrap(...)), WarehouseSelector)`
            // overflows at narrow widths (the selector's own natural width
            // has nothing bounding it as a fixed Row sibling) and a single
            // Wrap doesn't have that failure mode.
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToolbarSearchField(
                  controller: _searchController,
                  hintText: 'Search by product or reason…',
                  onChanged: (value) => setState(() => _search = value),
                ),
                for (final filter in _TypeFilter.values)
                  _FilterChip(
                    label: filter.label,
                    selected: _typeFilter == filter,
                    onTap: () => setState(() => _typeFilter = filter),
                  ),
                IconButton(
                  tooltip: _sortNewestFirst ? 'Newest first' : 'Oldest first',
                  onPressed: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
                  icon: Icon(
                    _sortNewestFirst ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 18,
                  ),
                ),
                const WarehouseSelector(),
              ],
            ),
            const SizedBox(height: 16),
            if (lowStock.isNotEmpty) ...[
              Card(
                color: theme.colorScheme.error.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${lowStock.length} item(s) low on stock',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lowStock
                                  .map((e) => isAllWarehouses
                                      ? '${e.product.name} (${e.warehouse.name})'
                                      : e.product.name)
                                  .join(' · '),
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            movements.isEmpty
                ? _EmptyState(hasFilters: _search.isNotEmpty || _typeFilter != _TypeFilter.all)
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          theme.colorScheme.onSurface.withValues(alpha: 0.03),
                        ),
                        columns: [
                          const DataColumn(label: Text('Date')),
                          const DataColumn(label: Text('Product')),
                          if (isAllWarehouses) const DataColumn(label: Text('Warehouse')),
                          const DataColumn(label: Text('Type')),
                          const DataColumn(label: Text('Qty'), numeric: true),
                          const DataColumn(label: Text('Reason')),
                          const DataColumn(label: Text('Resulting stock'), numeric: true),
                        ],
                        rows: [
                          for (var i = 0; i < movements.length; i++)
                            _buildRow(movements[i], i, isAllWarehouses, theme),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  DataRow _buildRow(StockMovement movement, int index, bool isAllWarehouses, ThemeData theme) {
    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return theme.colorScheme.primary.withValues(alpha: 0.06);
        }
        return index.isOdd ? theme.colorScheme.onSurface.withValues(alpha: 0.025) : null;
      }),
      cells: [
        DataCell(Text(dateFormat.format(movement.date))),
        DataCell(Text(movement.productName)),
        if (isAllWarehouses) DataCell(Text(movement.warehouseName)),
        DataCell(_MovementTypePill(type: movement.type)),
        DataCell(Text('${movement.quantity}')),
        DataCell(Text(movement.reason)),
        DataCell(Text('${movement.resultingStock}')),
      ],
    );
  }
}

class _MovementTypePill extends StatelessWidget {
  const _MovementTypePill({required this.type});

  final StockMovementType type;

  @override
  Widget build(BuildContext context) {
    final tone = switch (type) {
      StockMovementType.stockIn => StatusTone.positive,
      StockMovementType.stockOut => StatusTone.negative,
      StockMovementType.adjustment => StatusTone.warning,
    };
    final icon = switch (type) {
      StockMovementType.stockIn => Icons.arrow_downward_rounded,
      StockMovementType.stockOut => Icons.arrow_upward_rounded,
      StockMovementType.adjustment => Icons.tune_rounded,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 5),
        StatusPill(label: type.label, tone: tone),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.onSurface.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasFilters ? Icons.search_off : Icons.receipt_long_outlined,
                size: 40,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                hasFilters
                    ? 'No movements match your search or filter.'
                    : 'No stock movements recorded in this warehouse yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
