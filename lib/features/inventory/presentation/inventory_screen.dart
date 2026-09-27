import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/stock_level_bar.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_movement.dart';
import 'stock_movement_dialog.dart';

enum _View { levels, history }

enum _TypeFilter { all, stockIn, stockOut, adjustment, count }

extension on _TypeFilter {
  String get label => switch (this) {
        _TypeFilter.all => 'All types',
        _TypeFilter.stockIn => 'Stock in',
        _TypeFilter.stockOut => 'Stock out',
        _TypeFilter.adjustment => 'Adjustment',
        _TypeFilter.count => 'Stock count',
      };

  StockMovementType? get asMovementType => switch (this) {
        _TypeFilter.all => null,
        _TypeFilter.stockIn => StockMovementType.stockIn,
        _TypeFilter.stockOut => StockMovementType.stockOut,
        _TypeFilter.adjustment => StockMovementType.adjustment,
        _TypeFilter.count => StockMovementType.count,
      };
}

/// Live stock: what's on hand for every product, the low/out-of-stock
/// alerts from `/api/v1/alerts/stock`, and the movement ledger from
/// `/api/v1/inventory/movements` (latest 100, newest first).
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  _View _view = _View.levels;
  _TypeFilter _typeFilter = _TypeFilter.all;
  bool _sortNewestFirst = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _record({String? productId}) {
    showDialog(
      context: context,
      builder: (_) => StockMovementDialog(initialProductId: productId),
    );
  }

  Future<void> _reload() async {
    await Future.wait([
      ref.read(productsProvider.notifier).refresh(),
      ref.read(movementsProvider.notifier).refresh(),
      ref.read(stockAlertsProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = ref.watch(productListProvider);
    final productsState = ref.watch(productsProvider);
    final movementsState = ref.watch(movementsProvider);
    final movements = ref.watch(movementListProvider);
    final alerts = ref.watch(stockAlertListProvider);
    final warehouses = ref.watch(warehouseListProvider);
    final myId = ref.watch(sessionUserIdProvider);

    final canRecordAnything = hasPermission(ref, Permissions.stockOut) ||
        hasPermission(ref, Permissions.stockAdjust);

    final productById = {for (final p in products) p.id: p};
    final warehouseName = {for (final w in warehouses) w.id: w.name};
    final showWarehouse = warehouses.length > 1;

    final stockInTotal = movements
        .where((m) => m.quantity > 0)
        .fold(0, (sum, m) => sum + m.quantity);
    final stockOutTotal = movements
        .where((m) => m.quantity < 0)
        .fold(0, (sum, m) => sum + m.quantity.abs());
    final unitsOnHand = products.fold(0, (sum, p) => sum + p.currentStock);

    final query = _search.toLowerCase();

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Inventory',
              subtitle: 'Live stock levels and every movement that changed them',
              actions: [
                OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
                Tooltip(
                  message: canRecordAnything ? '' : "Your role can't record stock movements",
                  child: ElevatedButton.icon(
                    onPressed: canRecordAnything ? () => _record() : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Record movement'),
                  ),
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
              itemCount: 4,
              itemBuilder: (context, index) => switch (index) {
                0 => StatCard(
                    label: 'Units on hand',
                    value: '$unitsOnHand',
                    caption: 'Across ${products.length} product(s)',
                    icon: Icons.inventory_2_outlined,
                  ),
                1 => StatCard(
                    label: 'Received',
                    value: '$stockInTotal',
                    caption: 'Units in, latest ${movements.length} movements',
                    icon: Icons.arrow_downward_rounded,
                    accentColor: const Color(0xFF2F8F5B),
                  ),
                2 => StatCard(
                    label: 'Dispatched',
                    value: '$stockOutTotal',
                    caption: 'Units out, latest ${movements.length} movements',
                    icon: Icons.arrow_upward_rounded,
                    accentColor: theme.colorScheme.error,
                  ),
                _ => StatCard(
                    label: 'Stock alerts',
                    value: '${alerts.total}',
                    caption: '${alerts.outOfStock.length} out · ${alerts.lowStock.length} low',
                    icon: Icons.warning_amber_outlined,
                    accentColor: alerts.total > 0 ? theme.colorScheme.error : null,
                  ),
              },
            ),
            const SizedBox(height: 20),
            if (!alerts.isEmpty) ...[
              _AlertBanner(alerts: alerts),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<_View>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _View.levels, label: Text('Stock levels')),
                    ButtonSegment(value: _View.history, label: Text('Movement history')),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
                ToolbarSearchField(
                  controller: _searchController,
                  hintText: _view == _View.levels
                      ? 'Search products…'
                      : 'Search by product or reason…',
                  onChanged: (value) => setState(() => _search = value),
                ),
                if (_view == _View.history) ...[
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
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (_view == _View.levels)
              _buildLevels(theme, products, productsState, query, canRecordAnything)
            else
              _buildHistory(
                theme,
                movements,
                movementsState,
                productById,
                warehouseName,
                showWarehouse,
                myId,
                query,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevels(
    ThemeData theme,
    List<Product> products,
    AsyncValue<List<Product>> state,
    String query,
    bool canRecord,
  ) {
    if (state.isLoading && !state.hasValue) return const LoadingPanel(label: 'Loading stock…');
    if (state.hasError && !state.hasValue) {
      return ErrorRetryCard(
        error: state.error!,
        onRetry: () => ref.read(productsProvider.notifier).refresh(),
      );
    }

    // Most urgent first: out of stock, then low, then everything else.
    int urgency(Product p) => p.isOutOfStock ? 0 : (p.isLowStock ? 1 : 2);
    final rows = products
        .where((p) => query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            p.sku.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
        final byUrgency = urgency(a).compareTo(urgency(b));
        return byUrgency != 0 ? byUrgency : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (rows.isEmpty) {
      return _EmptyState(
        icon: query.isNotEmpty ? Icons.search_off : Icons.inventory_2_outlined,
        message: query.isNotEmpty
            ? 'No products match your search.'
            : 'No products yet. Add products first, then record stock in.',
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            theme.colorScheme.onSurface.withValues(alpha: 0.03),
          ),
          columns: const [
            DataColumn(label: Text('Product')),
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('On hand'), numeric: true),
            DataColumn(label: Text('Reorder level'), numeric: true),
            DataColumn(label: Text('Value at cost'), numeric: true),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) {
                    return theme.colorScheme.primary.withValues(alpha: 0.06);
                  }
                  return i.isOdd ? theme.colorScheme.onSurface.withValues(alpha: 0.025) : null;
                }),
                cells: [
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(rows[i].name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(Text(rows[i].sku)),
                  DataCell(
                    StockLevelBar(
                      quantity: rows[i].currentStock,
                      referenceMax: rows[i].maxStock ??
                          [rows[i].minStock * 3, rows[i].currentStock, 1]
                              .reduce((a, b) => a > b ? a : b),
                      isLow: rows[i].isLowStock || rows[i].isOutOfStock,
                    ),
                  ),
                  DataCell(Text(rows[i].minStock == 0 ? '—' : '${rows[i].minStock}')),
                  DataCell(Text(currencyFormat.format(rows[i].stockValueAtCost))),
                  DataCell(
                    rows[i].isOutOfStock
                        ? const StatusPill(label: 'Out of stock', tone: StatusTone.negative)
                        : rows[i].isLowStock
                            ? const StatusPill(label: 'Low stock', tone: StatusTone.warning)
                            : const StatusPill(label: 'In stock', tone: StatusTone.positive),
                  ),
                  DataCell(
                    TextButton(
                      onPressed: canRecord ? () => _record(productId: rows[i].id) : null,
                      child: const Text('Record'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory(
    ThemeData theme,
    List<StockMovement> all,
    AsyncValue<List<StockMovement>> state,
    Map<String, Product> productById,
    Map<String, String> warehouseName,
    bool showWarehouse,
    String? myId,
    String query,
  ) {
    if (state.isLoading && !state.hasValue) {
      return const LoadingPanel(label: 'Loading movements…');
    }
    if (state.hasError && !state.hasValue) {
      return ErrorRetryCard(
        error: state.error!,
        onRetry: () => ref.read(movementsProvider.notifier).refresh(),
      );
    }

    String productName(StockMovement m) => productById[m.productId]?.name ?? 'Archived product';

    final rows = all.where((m) {
      if (_typeFilter.asMovementType != null && m.type != _typeFilter.asMovementType) return false;
      if (query.isEmpty) return true;
      return productName(m).toLowerCase().contains(query) ||
          (m.reason?.toLowerCase().contains(query) ?? false);
    }).toList()
      ..sort((a, b) =>
          _sortNewestFirst ? b.createdAt.compareTo(a.createdAt) : a.createdAt.compareTo(b.createdAt));

    if (rows.isEmpty) {
      return _EmptyState(
        icon: (query.isNotEmpty || _typeFilter != _TypeFilter.all)
            ? Icons.search_off
            : Icons.receipt_long_outlined,
        message: (query.isNotEmpty || _typeFilter != _TypeFilter.all)
            ? 'No movements match your search or filter.'
            : 'No stock movements recorded yet.',
      );
    }

    return Card(
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
            if (showWarehouse) const DataColumn(label: Text('Warehouse')),
            const DataColumn(label: Text('Type')),
            const DataColumn(label: Text('Change'), numeric: true),
            const DataColumn(label: Text('Stock'), numeric: true),
            const DataColumn(label: Text('Reason')),
            const DataColumn(label: Text('By')),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.hovered)) {
                    return theme.colorScheme.primary.withValues(alpha: 0.06);
                  }
                  return i.isOdd ? theme.colorScheme.onSurface.withValues(alpha: 0.025) : null;
                }),
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(dateFormat.format(rows[i].createdAt)),
                        if (rows[i].isPending) ...[
                          const SizedBox(width: 8),
                          const StatusPill(label: 'Pending sync', tone: StatusTone.neutral),
                        ],
                      ],
                    ),
                  ),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(productName(rows[i]), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  if (showWarehouse)
                    DataCell(Text(warehouseName[rows[i].warehouseId] ?? 'Disabled warehouse')),
                  DataCell(_MovementTypePill(type: rows[i].type)),
                  DataCell(
                    Text(
                      '${rows[i].quantity > 0 ? '+' : ''}${rows[i].quantity}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: rows[i].quantity < 0 ? theme.colorScheme.error : const Color(0xFF2F8F5B),
                      ),
                    ),
                  ),
                  DataCell(Text('${rows[i].previousStock} → ${rows[i].newStock}')),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(rows[i].reason ?? '—', overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    Text(
                      rows[i].userId == null
                          ? '—'
                          : rows[i].userId == myId
                              ? 'You'
                              : 'Team member',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.alerts});

  final StockAlerts alerts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String names(List<Product> list) => list.map((p) => p.name).join(' · ');

    return Card(
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
                  if (alerts.outOfStock.isNotEmpty) ...[
                    Text(
                      '${alerts.outOfStock.length} product(s) out of stock',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      names(alerts.outOfStock),
                      style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ],
                  if (alerts.outOfStock.isNotEmpty && alerts.lowStock.isNotEmpty)
                    const SizedBox(height: 10),
                  if (alerts.lowStock.isNotEmpty) ...[
                    Text(
                      '${alerts.lowStock.length} product(s) low on stock',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      names(alerts.lowStock),
                      style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
      StockMovementType.count => StatusTone.neutral,
    };
    final icon = switch (type) {
      StockMovementType.stockIn => Icons.arrow_downward_rounded,
      StockMovementType.stockOut => Icons.arrow_upward_rounded,
      StockMovementType.adjustment => Icons.tune_rounded,
      StockMovementType.count => Icons.fact_check_outlined,
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
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

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
              Icon(icon, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                message,
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
