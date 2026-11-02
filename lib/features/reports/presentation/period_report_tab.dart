import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../documents/document_preview.dart';
import '../../documents/report_documents.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../products/data/products_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/period_reports.dart';
import '../data/report_document.dart';

const _good = Color(0xFF2F8F5B);

/// How many rows a table shows before "Show all".
const _pageRows = 200;

/// A filter the report can be narrowed by: the query name, what it's called,
/// and the choices (value, label).
class _Filter {
  const _Filter(this.key, this.label, this.all, this.options, {this.search = false});

  final String key;
  final String label;
  final String all;
  final List<(String, String)> options;
  final bool search;
}

/// One period report (sales, purchases, profit & loss or stock history):
/// the period and filters, Print / PDF and Excel, the headline figures and
/// one table at a time.
class PeriodReportTab extends ConsumerStatefulWidget {
  const PeriodReportTab({super.key, required this.kind});

  final ReportKind kind;

  @override
  ConsumerState<PeriodReportTab> createState() => _PeriodReportTabState();
}

class _PeriodReportTabState extends ConsumerState<PeriodReportTab> {
  int _section = 0;
  bool _showAll = false;
  List<Person> _people = const [];

  ReportKind get kind => widget.kind;

  List<_Filter> _filters() {
    final warehouses = _Filter('warehouseId', 'Warehouse', 'All warehouses', [
      for (final w in ref.watch(warehouseListProvider)) (w.id, w.isActive ? w.name : '${w.name} (disabled)'),
    ]);
    final products = _Filter('productId', 'Product', 'All products', [
      for (final p in ref.watch(productListProvider)) (p.id, '${p.name} (${p.sku})'),
    ], search: true);
    final people = _Filter('userId', kind == ReportKind.sales ? 'Sold by' : 'Recorded by', 'Everyone', [
      for (final p in _people) (p.id, p.name),
    ]);
    return switch (kind) {
      ReportKind.sales => [
        warehouses,
        _Filter('customerId', 'Customer', 'All customers', [
          ('walk-in', 'Walk-in customers'),
          for (final c in ref.watch(partyListProvider(PartyType.customer))) (c.id, c.name),
        ], search: true),
        people,
        products,
      ],
      ReportKind.purchases => [
        _Filter('supplierId', 'Supplier', 'All suppliers', [
          for (final s in ref.watch(partyListProvider(PartyType.supplier))) (s.id, s.name),
        ], search: true),
        warehouses,
        products,
      ],
      ReportKind.profitLoss => [warehouses],
      ReportKind.stockMovements => [
        warehouses,
        products,
        const _Filter('type', 'Type', 'All types', [
          ('stock_in', 'Stock in'),
          ('stock_out', 'Stock out'),
          ('adjustment', 'Adjustment'),
          ('count', 'Stock count'),
        ]),
        const _Filter('source', 'From', 'Anything', [
          ('sale', 'Sales'),
          ('purchase', 'Purchases'),
          ('manual', 'Recorded by hand'),
        ]),
        people,
      ],
    };
  }

  Future<void> _pickRange(ReportPreset preset) async {
    final now = DateTime.now();
    if (preset != ReportPreset.custom) {
      ref.read(reportRangeProvider.notifier).state = ReportRange.of(preset, now);
      return;
    }
    final current = ref.read(reportRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: current.from, end: current.lastDay),
      helpText: 'Report period',
    );
    if (picked == null) return;
    if (picked.end.difference(picked.start).inDays > 731) {
      if (mounted) _say('A report can cover at most two years.');
      return;
    }
    ref.read(reportRangeProvider.notifier).state = ReportRange.custom(picked.start, picked.end);
  }

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _setFilter(String key, String? value) {
    final next = {...ref.read(reportFiltersProvider(kind))};
    if (value == null || value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    ref.read(reportFiltersProvider(kind).notifier).state = next;
    setState(() => _showAll = false);
  }

  Future<void> _excel(ReportDocument doc) async {
    try {
      final bytes = Uint8List.fromList(buildReportExcel(doc));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${doc.title.toLowerCase()}',
        fileName: '${doc.fileStem}.xlsx',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      if (mounted) _say('${doc.title} saved to $path');
    } catch (e) {
      if (mounted) _say("Couldn't save the report: ${friendlyError(e)}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final range = ref.watch(reportRangeProvider);
    final chosen = ref.watch(reportFiltersProvider(kind));
    final query = ReportQuery(kind, range, chosen);
    final filters = _filters();

    // The report for this query, and its document.
    final (AsyncValue<Object?> state, ReportDocument? Function(List<(String, String)>) toDocument) = switch (kind) {
      ReportKind.sales => () {
        final s = ref.watch(salesReportProvider(query));
        return (s, (List<(String, String)> f) => s.valueOrNull == null ? null : salesDocument(s.valueOrNull!, f));
      }(),
      ReportKind.purchases => () {
        final s = ref.watch(purchasesReportProvider(query));
        return (s, (List<(String, String)> f) => s.valueOrNull == null ? null : purchasesDocument(s.valueOrNull!, f));
      }(),
      ReportKind.profitLoss => () {
        final s = ref.watch(profitLossReportProvider(query));
        return (s, (List<(String, String)> f) => s.valueOrNull == null ? null : profitLossDocument(s.valueOrNull!, f));
      }(),
      ReportKind.stockMovements => () {
        final s = ref.watch(stockMovementsReportProvider(query));
        return (
          s,
          (List<(String, String)> f) => s.valueOrNull == null ? null : stockMovementsDocument(s.valueOrNull!, f),
        );
      }(),
    };
    final people = switch (state.valueOrNull) {
      SalesReport r => r.people,
      StockMovementsReport r => r.people,
      _ => null,
    };
    if (people != null && people.isNotEmpty && !identical(people, _people)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _people = people);
      });
    }
    final filterLabels = [
      for (final f in filters)
        if (chosen[f.key] != null) (f.label, f.options.where((o) => o.$1 == chosen[f.key]).firstOrNull?.$2 ?? '—'),
    ];
    final doc = toDocument(filterLabels);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownMenu<ReportPreset>(
              key: const Key('report-range'),
              width: 190,
              label: const Text('Period'),
              initialSelection: range.preset,
              leadingIcon: const Icon(Icons.date_range_outlined, size: 18),
              dropdownMenuEntries: [for (final p in ReportPreset.values) DropdownMenuEntry(value: p, label: p.label)],
              onSelected: (p) {
                if (p != null) _pickRange(p);
              },
            ),
            for (final f in filters)
              DropdownMenu<String>(
                key: Key('filter-${f.key}'),
                width: 210,
                label: Text(f.label),
                initialSelection: chosen[f.key] ?? '',
                enableFilter: f.search,
                requestFocusOnTap: f.search,
                menuHeight: 360,
                dropdownMenuEntries: [
                  DropdownMenuEntry(value: '', label: f.all),
                  for (final (value, label) in f.options) DropdownMenuEntry(value: value, label: label),
                ],
                onSelected: (v) => _setFilter(f.key, v),
              ),
            if (chosen.isNotEmpty)
              TextButton.icon(
                key: const Key('report-clear-filters'),
                onPressed: () {
                  ref.read(reportFiltersProvider(kind).notifier).state = const {};
                  setState(() => _showAll = false);
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Clear filters'),
              ),
            OutlinedButton.icon(
              key: const Key('report-pdf'),
              onPressed: doc == null
                  ? null
                  : () => ref
                        .read(documentOpenerProvider)
                        .open(
                          context,
                          ref,
                          title: doc.title,
                          fileName: '${doc.fileStem}.pdf',
                          build: (kit) => buildReportPdf(kit, doc),
                        ),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print / PDF'),
            ),
            OutlinedButton.icon(
              key: const Key('report-excel'),
              onPressed: doc == null ? null : () => _excel(doc),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Excel'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(range.dates, key: const Key('report-dates'), style: muted),
        const SizedBox(height: 16),
        if (doc == null && state.hasError)
          ErrorRetryCard(error: state.error!, onRetry: () => ref.invalidate(reportJsonProvider(query)))
        else if (doc == null)
          const LoadingPanel(label: 'Working out the report…')
        else ...[
          if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
          _Kpis(kpis: doc.kpis),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, s) in doc.sections.indexed)
                ChoiceChip(
                  key: Key('section-$i'),
                  label: Text(s.title),
                  selected: i == _section.clamp(0, doc.sections.length - 1),
                  onSelected: (_) => setState(() {
                    _section = i;
                    _showAll = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ReportTable(
            section: doc.sections[_section.clamp(0, doc.sections.length - 1)],
            showAll: _showAll,
            onShowAll: () => setState(() => _showAll = true),
          ),
          if (doc.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final n in doc.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(n, style: muted),
              ),
          ],
        ],
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.kpis});

  final List<ReportKpi> kpis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 122,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      children: [
        for (final k in kpis)
          Card(
            key: Key('kpi-${k.label}'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.label, style: muted?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      k.value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: switch (k.tone) {
                          KpiTone.bad => theme.colorScheme.error,
                          KpiTone.good => _good,
                          KpiTone.neutral => theme.colorScheme.onSurface,
                        },
                      ),
                    ),
                  ),
                  if (k.caption != null) ...[
                    const SizedBox(height: 2),
                    Text(k.caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.section, required this.showAll, required this.onShowAll});

  final ReportSection section;
  final bool showAll;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = section;
    if (s.rows.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(child: Text(s.emptyText, key: const Key('report-empty'))),
        ),
      );
    }
    final shown = showAll ? s.rows : s.rows.take(_pageRows).toList();
    final bold = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800);
    DataRow row(List<Object?> cells, {bool strong = false}) => DataRow(
      cells: [
        for (final (i, v) in cells.indexed)
          DataCell(Text(formatCell(v, s.columns[i].kind), style: strong ? bold : null)),
      ],
    );
    return Card(
      key: const Key('report-table'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingTextStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                  columnSpacing: 22,
                  dataRowMinHeight: 38,
                  dataRowMaxHeight: 44,
                  columns: [for (final c in s.columns) DataColumn(label: Text(c.label), numeric: c.numeric)],
                  rows: [
                    for (final (i, cells) in shown.indexed) row(cells, strong: s.strongRows.contains(i)),
                    if (s.footer != null && shown.length == s.rows.length) row(s.footer!, strong: true),
                  ],
                ),
              ),
            ),
          ),
          if (shown.length < s.rows.length)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Showing ${shown.length} of ${s.rows.length} rows. Print or export to see them all, or',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(key: const Key('report-show-all'), onPressed: onShowAll, child: const Text('Show all')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
