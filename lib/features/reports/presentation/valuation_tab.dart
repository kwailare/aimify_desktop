import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../products/data/products_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/valuation_report.dart';

enum _Grouping { products, categories, warehouses }

/// The inventory valuation report: stock on hand priced at each product's
/// current purchase and selling price, by product, category or warehouse,
/// narrowed by warehouse, category and search. Figures come from the server
/// (`GET /api/v1/reports/valuation`) so every screen agrees.
class ValuationTab extends ConsumerStatefulWidget {
  const ValuationTab({super.key});

  @override
  ConsumerState<ValuationTab> createState() => _ValuationTabState();
}

class _ValuationTabState extends ConsumerState<ValuationTab> {
  final _search = TextEditingController();
  String? _warehouseId;

  /// `null` = all categories, `''` = uncategorised.
  String? _category;
  _Grouping _grouping = _Grouping.products;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ValuationFilter get _filter => (warehouseId: _warehouseId, category: _category);

  String _percent(double? value) => value == null ? '—' : '${value.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!ref.watch(canSeeValuationProvider)) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Your role needs to see both products and stock to view the valuation.')),
        ),
      );
    }

    final warehouses = ref.watch(warehouseListProvider);
    final categories = {
      for (final p in ref.watch(productListProvider))
        if (p.category != null && p.category!.isNotEmpty) p.category!,
    }.toList()
      ..sort();
    final report = ref.watch(valuationReportProvider(_filter));

    final filters = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<String?>(
            key: const Key('valuation-warehouse'),
            initialValue: _warehouseId,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.warehouse_outlined, size: 18)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All warehouses')),
              for (final w in warehouses)
                DropdownMenuItem<String?>(
                  value: w.id,
                  child: Text(w.isActive ? w.name : '${w.name} (disabled)', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(() => _warehouseId = value),
          ),
        ),
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<String?>(
            key: const Key('valuation-category'),
            initialValue: _category,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.category_outlined, size: 18)),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
              const DropdownMenuItem<String?>(value: '', child: Text('Uncategorised')),
              for (final c in categories) DropdownMenuItem<String?>(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
        ),
        SegmentedButton<_Grouping>(
          key: const Key('valuation-grouping'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Grouping.products, label: Text('By product')),
            ButtonSegment(value: _Grouping.categories, label: Text('By category')),
            ButtonSegment(value: _Grouping.warehouses, label: Text('By warehouse')),
          ],
          selected: {_grouping},
          onSelectionChanged: (s) => setState(() => _grouping = s.first),
        ),
        if (_grouping == _Grouping.products)
          ToolbarSearchField(
            controller: _search,
            hintText: 'Search name or SKU…',
            onChanged: (_) => setState(() {}),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filters,
        const SizedBox(height: 16),
        report.when(
          loading: () => const LoadingPanel(label: 'Working out the valuation…'),
          error: (error, _) => ErrorRetryCard(
            error: error,
            onRetry: () => ref.invalidate(valuationReportProvider(_filter)),
          ),
          data: (data) => data == null ? const SizedBox.shrink() : _report(theme, data),
        ),
      ],
    );
  }

  Widget _report(ThemeData theme, ValuationReport report) {
    final t = report.totals;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'As of ${dateTimeFormat.format(report.asOf)} · valued at each product\'s current purchase and selling price',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Fixed height like the other screens' stat cards: aspect-ratio tiles
          // get too short for their text in narrower windows.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 320,
            mainAxisExtent: 156,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          children: [
            StatCard(
              label: 'Value at cost',
              value: currencyFormat.format(t.valueAtCost),
              caption: 'What the stock on hand cost',
              icon: Icons.payments_outlined,
            ),
            StatCard(
              label: 'Value at selling price',
              value: currencyFormat.format(t.valueAtRetail),
              caption: 'If every unit sold at its price',
              icon: Icons.sell_outlined,
              accentColor: const Color(0xFF6C63FF),
            ),
            StatCard(
              label: 'Potential margin',
              value: currencyFormat.format(t.margin),
              caption: '${_percent(t.marginPercent)} of selling value',
              icon: Icons.trending_up,
              accentColor: const Color(0xFF2F8F5B),
            ),
            StatCard(
              label: 'Units on hand',
              value: '${t.units}',
              caption: 'Across ${t.products} product${t.products == 1 ? '' : 's'}',
              icon: Icons.inventory_2_outlined,
            ),
          ],
        ),
        if (report.negativeStockCount > 0 || report.noCostCount > 0) ...[
          const SizedBox(height: 16),
          Container(
            key: const Key('valuation-warnings'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFB7791F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFB7791F)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    [
                      if (report.negativeStockCount > 0)
                        '${report.negativeStockCount} product${report.negativeStockCount == 1 ? ' has' : 's have'} '
                            'stock below zero in a warehouse — record a count to correct it.',
                      if (report.noCostCount > 0)
                        '${report.noCostCount} product${report.noCostCount == 1 ? ' has' : 's have'} no purchase '
                            'price, so ${report.noCostCount == 1 ? 'it adds' : 'they add'} nothing to the value at cost.',
                    ].join(' '),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        switch (_grouping) {
          _Grouping.products => _productTable(theme, report),
          _Grouping.categories => _groupTable(theme, report.byCategory, 'Category', t),
          _Grouping.warehouses => _groupTable(theme, report.byWarehouse, 'Warehouse', t),
        },
      ],
    );
  }

  Widget _table(ThemeData theme, List<DataColumn> columns, List<DataRow> rows) => Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(theme.colorScheme.onSurface.withValues(alpha: 0.03)),
            columns: columns,
            rows: rows,
          ),
        ),
      );

  DataRow _totalRow(String label, ValuationTotals t, {int leading = 0}) {
    const bold = TextStyle(fontWeight: FontWeight.w800);
    return DataRow(
      cells: [
        const DataCell(Text('Total', style: bold)),
        for (var i = 0; i < leading; i++) const DataCell(Text('')),
        DataCell(Text('${t.units}', style: bold)),
        if (label == 'product') ...[const DataCell(Text('')), const DataCell(Text(''))],
        DataCell(Text(currencyFormat.format(t.valueAtCost), style: bold)),
        DataCell(Text(currencyFormat.format(t.valueAtRetail), style: bold)),
        DataCell(Text(currencyFormat.format(t.margin), style: bold)),
        DataCell(Text(_percent(t.marginPercent), style: bold)),
      ],
    );
  }

  Widget _productTable(ThemeData theme, ValuationReport report) {
    final query = _search.text.trim().toLowerCase();
    final rows = report.byProduct
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query))
        .toList();
    if (report.byProduct.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No stock on hand to value.'))),
      );
    }
    final shown = query.isEmpty
        ? report.totals
        : ValuationTotals(
            products: rows.length,
            units: rows.fold(0, (s, r) => s + r.quantity),
            valueAtCost: rows.fold(0.0, (s, r) => s + r.valueAtCost),
            valueAtRetail: rows.fold(0.0, (s, r) => s + r.valueAtRetail),
            margin: rows.fold(0.0, (s, r) => s + r.margin),
            marginPercent: () {
              final retail = rows.fold(0.0, (s, r) => s + r.valueAtRetail);
              final margin = rows.fold(0.0, (s, r) => s + r.margin);
              return retail > 0 ? margin / retail * 100 : null;
            }(),
          );

    return _table(
      theme,
      const [
        DataColumn(label: Text('Product')),
        DataColumn(label: Text('Category')),
        DataColumn(label: Text('On hand'), numeric: true),
        DataColumn(label: Text('Cost price'), numeric: true),
        DataColumn(label: Text('Selling price'), numeric: true),
        DataColumn(label: Text('Value at cost'), numeric: true),
        DataColumn(label: Text('Value at selling price'), numeric: true),
        DataColumn(label: Text('Margin'), numeric: true),
        DataColumn(label: Text('Margin %'), numeric: true),
      ],
      [
        for (final r in rows)
          DataRow(
            key: ValueKey('valuation-${r.productId}'),
            cells: [
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text('${r.name} · ${r.sku}', overflow: TextOverflow.ellipsis),
                    ),
                    if (r.flags.contains(ValuationFlag.negativeStock)) ...[
                      const SizedBox(width: 6),
                      const StatusPill(label: 'Below zero', tone: StatusTone.negative),
                    ],
                    if (r.flags.contains(ValuationFlag.noCost)) ...[
                      const SizedBox(width: 6),
                      const StatusPill(label: 'No cost', tone: StatusTone.warning),
                    ],
                    if (r.flags.contains(ValuationFlag.archived)) ...[
                      const SizedBox(width: 6),
                      const StatusPill(label: 'Archived', tone: StatusTone.neutral),
                    ],
                  ],
                ),
              ),
              DataCell(Text(r.category ?? '—')),
              DataCell(Text('${r.quantity} ${r.unit}')),
              DataCell(Text(currencyFormat.format(r.unitCost))),
              DataCell(Text(currencyFormat.format(r.unitPrice))),
              DataCell(Text(currencyFormat.format(r.valueAtCost))),
              DataCell(Text(currencyFormat.format(r.valueAtRetail))),
              DataCell(Text(currencyFormat.format(r.margin))),
              DataCell(Text(_percent(r.valueAtRetail > 0 ? r.margin / r.valueAtRetail * 100 : null))),
            ],
          ),
        _totalRow('product', shown, leading: 1),
      ],
    );
  }

  Widget _groupTable(ThemeData theme, List<ValuationGroupRow> groups, String label, ValuationTotals total) {
    if (groups.isEmpty) {
      return const Card(
        child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No stock on hand to value.'))),
      );
    }
    return _table(
      theme,
      [
        DataColumn(label: Text(label)),
        const DataColumn(label: Text('Products'), numeric: true),
        const DataColumn(label: Text('On hand'), numeric: true),
        const DataColumn(label: Text('Value at cost'), numeric: true),
        const DataColumn(label: Text('Value at selling price'), numeric: true),
        const DataColumn(label: Text('Margin'), numeric: true),
        const DataColumn(label: Text('Margin %'), numeric: true),
      ],
      [
        for (final g in groups)
          DataRow(
            key: ValueKey('valuation-group-${g.id ?? 'none'}'),
            cells: [
              DataCell(Text(g.label)),
              DataCell(Text('${g.totals.products}')),
              DataCell(Text('${g.totals.units}')),
              DataCell(Text(currencyFormat.format(g.totals.valueAtCost))),
              DataCell(Text(currencyFormat.format(g.totals.valueAtRetail))),
              DataCell(Text(currencyFormat.format(g.totals.margin))),
              DataCell(Text(_percent(g.totals.marginPercent))),
            ],
          ),
        DataRow(
              cells: [
            const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
            DataCell(Text('${total.products}', style: const TextStyle(fontWeight: FontWeight.w800))),
            DataCell(Text('${total.units}', style: const TextStyle(fontWeight: FontWeight.w800))),
            DataCell(Text(currencyFormat.format(total.valueAtCost), style: const TextStyle(fontWeight: FontWeight.w800))),
            DataCell(Text(currencyFormat.format(total.valueAtRetail), style: const TextStyle(fontWeight: FontWeight.w800))),
            DataCell(Text(currencyFormat.format(total.margin), style: const TextStyle(fontWeight: FontWeight.w800))),
            DataCell(Text(_percent(total.marginPercent), style: const TextStyle(fontWeight: FontWeight.w800))),
          ],
        ),
      ],
    );
  }
}
