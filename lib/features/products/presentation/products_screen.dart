import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/category_tag.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/stock_level_bar.dart';
import '../../../shared/widgets/manage_billing_link.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../data/products_repository.dart';
import '../domain/product.dart';
import 'product_form_dialog.dart';
import 'widgets/catalog_manager_dialog.dart';

enum _SortField { name, category, purchasePrice, sellingPrice, stock }

/// The product catalog, live from `/api/v1/products`. Create/edit need
/// `products.write`, archiving needs `products.archive`, and adding is also
/// blocked once the plan's product cap is reached (archiving frees a slot).
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
    final productsState = ref.watch(productsProvider);
    final all = ref.watch(productListProvider);

    final canWrite = hasPermission(ref, Permissions.productsWrite);
    final canArchive = hasPermission(ref, Permissions.productsArchive);
    final me = ref.watch(authControllerProvider).valueOrNull;
    final plan = me?.plan;
    final atProductCap = ref.watch(productSlotsFullProvider);
    final isOwner = me?.role == 'Owner';

    var subtitle = '${all.length} active product(s)';
    if (plan?.limits.products != null) {
      subtitle += ' · plan: ${plan!.usage.products}/${plan.limits.products} products used';
    }

    final categories = <String>{
      for (final p in all)
        if (p.category != null) p.category!,
    }.toList()
      ..sort();
    if (_categoryFilter != null && !categories.contains(_categoryFilter)) {
      _categoryFilter = null;
    }

    final query = _search.toLowerCase();
    var entries = all.where((p) {
      if (_categoryFilter != null && p.category != _categoryFilter) return false;
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.sku.toLowerCase().contains(query) ||
          (p.brand?.toLowerCase().contains(query) ?? false) ||
          (p.barcode?.toLowerCase().contains(query) ?? false);
    }).toList();

    int compare(Product a, Product b) {
      final cmp = switch (_sortField) {
        _SortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _SortField.category => (a.category ?? '').compareTo(b.category ?? ''),
        _SortField.purchasePrice => a.purchasePrice.compareTo(b.purchasePrice),
        _SortField.sellingPrice => a.sellingPrice.compareTo(b.sellingPrice),
        _SortField.stock => a.currentStock.compareTo(b.currentStock),
      };
      return _sortAscending ? cmp : -cmp;
    }

    entries = entries..sort(compare);

    final stockValue = all.fold(0.0, (sum, p) => sum + p.stockValueAtCost);
    final attentionCount = all.where((p) => p.isLowStock || p.isOutOfStock).length;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Products',
              subtitle: subtitle,
              actions: [
                OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const CatalogManagerDialog(),
                  ),
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: const Text('Categories & units'),
                ),
                if (atProductCap && isOwner) const ManageBillingLink(),
                Tooltip(
                  message: !canWrite
                      ? "Your role can't add products"
                      : atProductCap
                          ? 'Your plan has reached its product limit — archive one to free a slot'
                          : '',
                  child: ElevatedButton.icon(
                    onPressed: (!canWrite || atProductCap)
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (_) => const ProductFormDialog(),
                            ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add product'),
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
              itemCount: 3,
              itemBuilder: (context, index) => switch (index) {
                0 => StatCard(
                    label: 'Products',
                    value: '${all.length}',
                    icon: Icons.inventory_2_outlined,
                  ),
                1 => StatCard(
                    label: 'Stock value',
                    value: currencyFormat.format(stockValue),
                    caption: 'On hand, at purchase cost',
                    icon: Icons.payments_outlined,
                  ),
                _ => StatCard(
                    label: 'Needs attention',
                    value: '$attentionCount',
                    caption: 'Low or out of stock',
                    icon: Icons.warning_amber_outlined,
                    accentColor: attentionCount > 0 ? theme.colorScheme.error : null,
                  ),
              },
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToolbarSearchField(
                  controller: _searchController,
                  hintText: 'Search name, SKU, brand or barcode…',
                  width: 300,
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
              ],
            ),
            const SizedBox(height: 16),
            if (productsState.isLoading && !productsState.hasValue)
              const LoadingPanel(label: 'Loading products…')
            else if (productsState.hasError && !productsState.hasValue)
              ErrorRetryCard(
                error: productsState.error!,
                onRetry: () => ref.read(productsProvider.notifier).refresh(),
              )
            else if (entries.isEmpty)
              _EmptyState(
                hasFilters: _search.isNotEmpty || _categoryFilter != null,
                canAdd: canWrite && !atProductCap,
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 64,
                    headingRowColor: WidgetStateProperty.all(
                      theme.colorScheme.onSurface.withValues(alpha: 0.03),
                    ),
                    columns: [
                      DataColumn(
                        label: _SortableHeader(
                          label: 'Product',
                          active: _sortField == _SortField.name,
                          ascending: _sortAscending,
                          onTap: () => _onSort(_SortField.name),
                        ),
                      ),
                      const DataColumn(label: Text('SKU')),
                      DataColumn(
                        label: _SortableHeader(
                          label: 'Category',
                          active: _sortField == _SortField.category,
                          ascending: _sortAscending,
                          onTap: () => _onSort(_SortField.category),
                        ),
                      ),
                      const DataColumn(label: Text('Unit')),
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
                      const DataColumn(label: Text('Status')),
                      const DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (var i = 0; i < entries.length; i++)
                        _buildRow(context, entries[i], i, theme,
                            canWrite: canWrite, canArchive: canArchive),
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
    Product product,
    int index,
    ThemeData theme, {
    required bool canWrite,
    required bool canArchive,
  }) {
    final reference = product.maxStock ??
        [product.minStock * 3, product.currentStock, 1].reduce((a, b) => a > b ? a : b);

    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return theme.colorScheme.primary.withValues(alpha: 0.06);
        }
        return index.isOdd ? theme.colorScheme.onSurface.withValues(alpha: 0.025) : null;
      }),
      cells: [
        DataCell(_ProductCell(product: product)),
        DataCell(Text(product.sku)),
        DataCell(
          product.category == null
              ? const Text('—')
              : CategoryTag(category: product.category!),
        ),
        DataCell(Text(product.unit)),
        DataCell(Text(currencyFormat.format(product.purchasePrice))),
        DataCell(
          hasTax
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(currencyFormat.format(product.sellingPrice)),
                    Text(
                      '${currencyFormat.format(priceWithTax(product.sellingPrice))} incl. $orgTaxName',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                )
              : Text(currencyFormat.format(product.sellingPrice)),
        ),
        DataCell(
          StockLevelBar(
            quantity: product.currentStock,
            referenceMax: reference,
            isLow: product.isLowStock || product.isOutOfStock,
          ),
        ),
        DataCell(
          product.isPending
              ? const StatusPill(label: 'Pending sync', tone: StatusTone.neutral)
              : product.isOutOfStock
              ? const StatusPill(label: 'Out of stock', tone: StatusTone.negative)
              : product.isLowStock
                  ? const StatusPill(label: 'Low stock', tone: StatusTone.warning)
                  : const StatusPill(label: 'In stock', tone: StatusTone.positive),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: canWrite ? 'Edit' : "Your role can't edit products",
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: !canWrite
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) => ProductFormDialog(product: product),
                        ),
              ),
              IconButton(
                tooltip: canArchive ? 'Archive' : "Your role can't archive products",
                icon: const Icon(Icons.archive_outlined, size: 18),
                onPressed: !canArchive ? null : () => _confirmArchive(context, product),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmArchive(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive product?'),
        content: Text(
          '${product.name} will disappear from the product list. Its stock history is '
          'kept and its SKU stays reserved. Archiving frees one product slot on your plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                final outcome = await ref.read(productsProvider.notifier).archive(product.id);
                if (outcome.queued && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Saved on this computer — it will sync when the connection is good.',
                        ),
                      ),
                    );
                }
              } catch (e) {
                if (context.mounted) showErrorSnack(context, e);
              }
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}

class _ProductCell extends StatelessWidget {
  const _ProductCell({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 38,
              height: 38,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              alignment: Alignment.center,
              child: product.imageUrl == null
                  ? Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    )
                  : Image.network(
                      product.imageUrl!,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 18),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (product.brand != null)
                  Text(
                    product.brand!,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
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
            color: selected
                ? chipColor.withValues(alpha: 0.5)
                : theme.colorScheme.onSurface.withValues(alpha: 0.15),
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
  const _EmptyState({required this.hasFilters, required this.canAdd});

  final bool hasFilters;
  final bool canAdd;

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
                    : canAdd
                        ? 'No products yet. Use "Add product" to create your first one.'
                        : 'No products yet.',
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
