import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/category_tag.dart';
import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/stock_level_bar.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../../shared/widgets/warehouse/warehouse_selector.dart';
import '../../inventory/data/warehouse_stock_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/product_stock_view.dart';
import '../data/products_repository.dart';
import 'product_form_dialog.dart';
import 'widgets/bulk_import_dialog.dart';
import 'widgets/edit_product_dialog.dart';

enum _SortField { name, category, purchasePrice, sellingPrice, stock }

/// UI-only for now: reads from the MOCK [scopedProductsProvider], which
/// joins the product catalog with per-warehouse stock (see
/// `product_stock_view.dart`). Selecting one warehouse shows only what's
/// actually stocked there — not every catalog item with a zero — which is
/// the point: warehouses are independent, not shared numbers relabeled.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _categoryFilter;
  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allEntries = ref.watch(scopedProductsProvider);
    final isAllWarehouses = ref.watch(selectedWarehouseIdProvider) == null;

    final categories = <String>{for (final e in allEntries) e.product.category}.toList()..sort();
    if (_categoryFilter != null && !categories.contains(_categoryFilter)) {
      _categoryFilter = null;
    }

    var entries = allEntries.where((e) {
      if (_categoryFilter != null && e.product.category != _categoryFilter) return false;
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return e.product.name.toLowerCase().contains(q) || e.product.sku.toLowerCase().contains(q);
    }).toList();

    int compare(ProductWithStock a, ProductWithStock b) {
      final cmp = switch (_sortField) {
        _SortField.name => a.product.name.compareTo(b.product.name),
        _SortField.category => a.product.category.compareTo(b.product.category),
        _SortField.purchasePrice => a.product.purchasePrice.compareTo(b.product.purchasePrice),
        _SortField.sellingPrice => a.product.sellingPrice.compareTo(b.product.sellingPrice),
        _SortField.stock => a.totalQuantity.compareTo(b.totalQuantity),
      };
      return _sortAscending ? cmp : -cmp;
    }

    entries = entries.toList()..sort(compare);

    final totalValue = allEntries.fold(
      0.0,
      (sum, e) => sum + e.totalQuantity * e.product.purchasePrice,
    );
    final lowCount = allEntries.where((e) => e.isLowSomewhere).length;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Products',
              subtitle: '${allEntries.length} SKU(s) stocked in this scope',
              badge: const MockDataBadge(),
              actions: [
                OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const BulkImportDialog(),
                  ),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Import from Excel'),
                ),
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const ProductFormDialog(),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add product'),
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
                    label: 'SKUs in scope',
                    value: '${allEntries.length}',
                    icon: Icons.inventory_2_outlined,
                  ),
                1 => StatCard(
                    label: 'Catalog value in scope',
                    value: currencyFormat.format(totalValue),
                    caption: 'At purchase cost',
                    icon: Icons.payments_outlined,
                  ),
                _ => StatCard(
                    label: 'Low stock in scope',
                    value: '$lowCount',
                    icon: Icons.warning_amber_outlined,
                    accentColor: lowCount > 0 ? theme.colorScheme.error : null,
                  ),
              },
            ),
            const SizedBox(height: 20),
            // A single Wrap for the whole toolbar, `WarehouseSelector`
            // included — this used to pin the selector to the right via
            // `Row(Expanded(Wrap(...)), WarehouseSelector)`, but that Row
            // overflows the instant its non-flexible children (the
            // selector's own natural width, which varies with warehouse
            // name length) alone exceed what's left after page padding at
            // narrow widths. A Row's Expanded child can never overflow —
            // only its fixed siblings can — so the safest fix is to give
            // the selector nothing to overflow *out of*.
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToolbarSearchField(
                  controller: _searchController,
                  hintText: 'Search by name or SKU…',
                  onChanged: (value) => setState(() => _search = value),
                ),
                _CategoryChip(
                  label: 'All categories',
                  selected: _categoryFilter == null,
                  onTap: () => setState(() => _categoryFilter = null),
                ),
                for (final category in categories)
                  _CategoryChip(
                    label: category,
                    color: colorForCategory(category),
                    selected: _categoryFilter == category,
                    onTap: () => setState(() => _categoryFilter = category),
                  ),
                const WarehouseSelector(),
              ],
            ),
            const SizedBox(height: 16),
            entries.isEmpty
                ? _EmptyState(hasFilters: _search.isNotEmpty || _categoryFilter != null)
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          theme.colorScheme.onSurface.withValues(alpha: 0.03),
                        ),
                        columns: [
                          const DataColumn(label: Text('SKU')),
                          DataColumn(
                            label: _SortableHeader(
                              label: 'Name',
                              active: _sortField == _SortField.name,
                              ascending: _sortAscending,
                              onTap: () => _onSort(_SortField.name),
                            ),
                          ),
                          DataColumn(
                            label: _SortableHeader(
                              label: 'Category',
                              active: _sortField == _SortField.category,
                              ascending: _sortAscending,
                              onTap: () => _onSort(_SortField.category),
                            ),
                          ),
                          const DataColumn(label: Text('UoM')),
                          DataColumn(
                            label: _SortableHeader(
                              label: 'Purchase price',
                              active: _sortField == _SortField.purchasePrice,
                              ascending: _sortAscending,
                              onTap: () => _onSort(_SortField.purchasePrice),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: _SortableHeader(
                              label: 'Selling price',
                              active: _sortField == _SortField.sellingPrice,
                              ascending: _sortAscending,
                              onTap: () => _onSort(_SortField.sellingPrice),
                            ),
                            numeric: true,
                          ),
                          DataColumn(
                            label: _SortableHeader(
                              label: 'Stock',
                              active: _sortField == _SortField.stock,
                              ascending: _sortAscending,
                              onTap: () => _onSort(_SortField.stock),
                            ),
                            numeric: true,
                          ),
                          if (isAllWarehouses) const DataColumn(label: Text('In')),
                          const DataColumn(label: Text('Status')),
                          const DataColumn(label: Text('')),
                        ],
                        rows: [
                          for (var i = 0; i < entries.length; i++)
                            _buildRow(context, ref, entries[i], i, isAllWarehouses, theme),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  DataRow _buildRow(
    BuildContext context,
    WidgetRef ref,
    ProductWithStock entry,
    int index,
    bool isAllWarehouses,
    ThemeData theme,
  ) {
    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return theme.colorScheme.primary.withValues(alpha: 0.06);
        }
        return index.isOdd ? theme.colorScheme.onSurface.withValues(alpha: 0.025) : null;
      }),
      cells: [
        DataCell(Text(entry.product.sku)),
        DataCell(Text(entry.product.name)),
        DataCell(CategoryTag(category: entry.product.category)),
        DataCell(Text(entry.product.unitOfMeasure)),
        DataCell(Text(currencyFormat.format(entry.product.purchasePrice))),
        DataCell(Text(currencyFormat.format(entry.product.sellingPrice))),
        DataCell(
          StockLevelBar(
            quantity: entry.totalQuantity,
            referenceMax: entry.referenceThreshold * 3,
            isLow: entry.isLowSomewhere,
          ),
        ),
        if (isAllWarehouses) DataCell(Text('${entry.stockedWarehouseCount}')),
        DataCell(
          entry.isLowSomewhere
              ? const StatusPill(label: 'Low stock', tone: StatusTone.negative)
              : const StatusPill(label: 'In stock', tone: StatusTone.positive),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => EditProductDialog(product: entry.product),
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _confirmDelete(context, ref, entry),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ProductWithStock entry) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          '${entry.product.name} will be removed from the catalog and from every '
          "warehouse's stock. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(productsProvider.notifier).removeProduct(entry.product.id);
              ref.read(warehouseStockProvider.notifier).removeProduct(entry.product.id);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _SortableHeader extends StatelessWidget {
  const _SortableHeader({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? theme.colorScheme.primary : null;
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          if (active) ...[
            const SizedBox(width: 2),
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 13,
              color: color,
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipColor = color ?? theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? chipColor.withValues(alpha: 0.16) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? chipColor.withValues(alpha: 0.5) : theme.colorScheme.onSurface.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? chipColor : theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
                hasFilters ? Icons.search_off : Icons.inventory_2_outlined,
                size: 40,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                hasFilters
                    ? 'No products match your search or filter.'
                    : 'Nothing stocked in this warehouse yet.',
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
