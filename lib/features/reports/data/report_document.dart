import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../../shared/utils/formatters.dart';
import '../../sales/domain/sale.dart';
import 'period_reports.dart';

// What a period report shows, printed or saved: headline figures and
// titled tables. The screen, the PDF and the spreadsheet are all built from
// one [ReportDocument], so they always agree.

enum ColumnKind { text, count, signed, money, percent, date, dateTime }

class ReportColumn {
  const ReportColumn(this.label, [this.kind = ColumnKind.text]);

  final String label;
  final ColumnKind kind;

  bool get numeric => kind != ColumnKind.text && kind != ColumnKind.date && kind != ColumnKind.dateTime;
}

class ReportSection {
  const ReportSection({
    required this.title,
    required this.columns,
    required this.rows,
    this.footer,
    this.strongRows = const {},
    this.emptyText = 'Nothing in this period.',
  });

  final String title;
  final List<ReportColumn> columns;

  /// Cells: String, int, double, DateTime or null, as the column's kind.
  final List<List<Object?>> rows;

  /// A totals row.
  final List<Object?>? footer;

  /// Rows to show in bold (statement subtotals).
  final Set<int> strongRows;
  final String emptyText;
}

enum KpiTone { neutral, good, bad }

class ReportKpi {
  const ReportKpi(this.label, this.value, {this.caption, this.tone = KpiTone.neutral});

  final String label;
  final String value;
  final String? caption;
  final KpiTone tone;
}

class ReportDocument {
  const ReportDocument({
    required this.kind,
    required this.range,
    this.filters = const [],
    this.kpis = const [],
    this.sections = const [],
    this.notes = const [],
  });

  final ReportKind kind;
  final ReportRange range;

  /// What it was narrowed to: (filter, chosen value).
  final List<(String, String)> filters;
  final List<ReportKpi> kpis;
  final List<ReportSection> sections;
  final List<String> notes;

  String get title => kind.title;

  /// For the file name, e.g. sales-report-2026-10.
  String get fileStem => '${kind.slug}-${range.slug}';
}

/// [value] shown in a column of [kind].
String formatCell(Object? value, ColumnKind kind) {
  if (value == null) return '';
  // Labels ("Total") can sit in any column.
  if (value is String) return value;
  return switch (kind) {
    ColumnKind.text => '$value',
    ColumnKind.count => NumberFormat.decimalPattern().format(value as num),
    ColumnKind.signed => '${(value as num) > 0 ? '+' : ''}${NumberFormat.decimalPattern().format(value)}',
    ColumnKind.money => currencyFormat.format(value as num),
    ColumnKind.percent => '${(value as num).toStringAsFixed(1)}%',
    ColumnKind.date => dateFormat.format(value as DateTime),
    ColumnKind.dateTime => dateTimeFormat.format(value as DateTime),
  };
}

String _money(double v) => currencyFormat.format(v);
String _count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';
String _margin(double? m) => m == null ? '' : '${m.toStringAsFixed(1)}% margin';
String _methodLabel(String method) =>
    SalePaymentMethod.values.where((m) => m.name == method).firstOrNull?.label ??
    (method == 'unspecified' ? 'Not given' : method);

String _periodColumn(String bucket) => bucket == 'month' ? 'Month' : 'Day';
Object _periodCell(DateTime d, String bucket) => bucket == 'month' ? DateFormat('MMMM yyyy').format(d) : d;
ColumnKind _periodKind(String bucket) => bucket == 'month' ? ColumnKind.text : ColumnKind.date;

// ---------------------------------------------------------------- sales

ReportDocument salesDocument(SalesReport r, List<(String, String)> filters) {
  final t = r.totals;
  final periodColumns = [
    ReportColumn(_periodColumn(r.bucket), _periodKind(r.bucket)),
    const ReportColumn('Sales', ColumnKind.count),
    const ReportColumn('Units', ColumnKind.count),
    const ReportColumn('Total', ColumnKind.money),
    const ReportColumn('Revenue', ColumnKind.money),
    const ReportColumn('Cost', ColumnKind.money),
    const ReportColumn('Gross profit', ColumnKind.money),
    const ReportColumn('Margin', ColumnKind.percent),
  ];
  List<Object?> figures(SalesFigures f, Object label) => [
    label,
    f.count,
    f.units,
    f.total,
    f.revenue,
    f.cogs,
    f.grossProfit,
    f.margin,
  ];
  final groupColumns = [
    const ReportColumn('Sales', ColumnKind.count),
    const ReportColumn('Total', ColumnKind.money),
    const ReportColumn('Paid', ColumnKind.money),
    const ReportColumn('Outstanding', ColumnKind.money),
    const ReportColumn('Revenue', ColumnKind.money),
    const ReportColumn('Gross profit', ColumnKind.money),
    const ReportColumn('Margin', ColumnKind.percent),
  ];
  List<Object?> group(SalesFigures f) => [
    f.name,
    f.count,
    f.total,
    f.paid,
    f.outstanding,
    f.revenue,
    f.grossProfit,
    f.margin,
  ];
  final groupFooter = <Object?>['Total', t.count, t.total, t.paid, t.outstanding, t.revenue, t.grossProfit, t.margin];

  return ReportDocument(
    kind: ReportKind.sales,
    range: r.query.range,
    filters: filters,
    kpis: [
      ReportKpi('Sales', _money(t.total), caption: '${_count(t.count, 'sale')} · ${_count(t.units, 'unit')}'),
      ReportKpi('Revenue', _money(t.revenue), caption: 'After discounts, before tax'),
      ReportKpi(
        'Gross profit',
        _money(t.grossProfit),
        caption: t.margin == null ? 'Revenue less cost of goods' : _margin(t.margin),
        tone: t.grossProfit < 0 ? KpiTone.bad : KpiTone.good,
      ),
      ReportKpi('Paid', _money(t.paid), caption: 'Of what these sales came to'),
      ReportKpi(
        'Outstanding',
        _money(t.outstanding),
        caption: 'Still owed on these sales',
        tone: t.outstanding > 0 ? KpiTone.bad : KpiTone.neutral,
      ),
      ReportKpi(
        'Average sale',
        _money(r.averageSale),
        caption: r.voidedCount == 0
            ? 'Nothing voided'
            : '${_count(r.voidedCount, 'voided sale')} (${_money(r.voidedTotal)}) not counted',
      ),
    ],
    sections: [
      ReportSection(
        title: 'By ${_periodColumn(r.bucket).toLowerCase()}',
        columns: periodColumns,
        rows: [for (final p in r.byPeriod) figures(p, _periodCell(p.bucket!, r.bucket))],
        footer: figures(t, 'Total'),
      ),
      ReportSection(
        title: 'By product',
        columns: const [
          ReportColumn('Product'),
          ReportColumn('SKU'),
          ReportColumn('Sales', ColumnKind.count),
          ReportColumn('Units', ColumnKind.count),
          ReportColumn('Revenue', ColumnKind.money),
          ReportColumn('Cost', ColumnKind.money),
          ReportColumn('Gross profit', ColumnKind.money),
          ReportColumn('Margin', ColumnKind.percent),
        ],
        rows: [
          for (final p in r.byProduct) [p.name, p.sku, p.sales, p.units, p.revenue, p.cogs, p.grossProfit, p.margin],
        ],
      ),
      ReportSection(
        title: 'By customer',
        columns: [const ReportColumn('Customer'), ...groupColumns],
        rows: [for (final c in r.byCustomer) group(c)],
        footer: groupFooter,
      ),
      ReportSection(
        title: 'By staff',
        columns: [const ReportColumn('Sold by'), ...groupColumns],
        rows: [for (final c in r.byStaff) group(c)],
        footer: groupFooter,
      ),
      ReportSection(
        title: 'By warehouse',
        columns: [const ReportColumn('Warehouse'), ...groupColumns],
        rows: [for (final c in r.byWarehouse) group(c)],
        footer: groupFooter,
      ),
      ReportSection(
        title: 'Sales',
        columns: const [
          ReportColumn('Ref.'),
          ReportColumn('Date', ColumnKind.date),
          ReportColumn('Customer'),
          ReportColumn('Warehouse'),
          ReportColumn('Sold by'),
          ReportColumn('Discount', ColumnKind.money),
          ReportColumn('Tax', ColumnKind.money),
          ReportColumn('Total', ColumnKind.money),
          ReportColumn('Paid', ColumnKind.money),
          ReportColumn('Outstanding', ColumnKind.money),
        ],
        rows: [
          for (final s in r.sales)
            [
              s.reference,
              s.saleDate,
              s.customer,
              s.warehouse,
              s.staff ?? '',
              s.discount,
              s.tax,
              s.total,
              s.paid,
              s.outstanding,
            ],
        ],
        footer: ['Total', null, null, null, null, r.discount, r.tax, t.total, t.paid, t.outstanding],
      ),
    ],
    notes: [
      if (r.query.filters.containsKey('productId'))
        'Revenue, cost and profit are for the chosen product (at its line prices); the money columns are the sales that include it.',
      if (r.truncated) 'Only the newest 1,000 sales are listed; the totals cover them all.',
    ],
  );
}

// ------------------------------------------------------------ purchases

ReportDocument purchasesDocument(PurchasesReport r, List<(String, String)> filters) {
  final t = r.totals;
  const figureColumns = [
    ReportColumn('Purchases', ColumnKind.count),
    ReportColumn('Total', ColumnKind.money),
    ReportColumn('Paid', ColumnKind.money),
    ReportColumn('Not yet paid', ColumnKind.money),
    ReportColumn('Units ordered', ColumnKind.count),
    ReportColumn('Units received', ColumnKind.count),
  ];
  List<Object?> figures(PurchaseFigures f, Object label) => [
    label,
    f.count,
    f.total,
    f.paid,
    f.unpaid,
    f.unitsOrdered,
    f.unitsReceived,
  ];
  final footer = figures(t, 'Total');
  return ReportDocument(
    kind: ReportKind.purchases,
    range: r.query.range,
    filters: filters,
    kpis: [
      ReportKpi('Purchases', _money(t.total), caption: _count(t.count, 'order')),
      ReportKpi('Paid', _money(t.paid), caption: 'Of what these orders came to'),
      ReportKpi('Not yet paid', _money(t.unpaid), tone: t.unpaid > 0 ? KpiTone.bad : KpiTone.neutral),
      ReportKpi(
        'Units ordered',
        NumberFormat.decimalPattern().format(t.unitsOrdered),
        caption: 'Worth ${_money(r.orderedValue)}',
      ),
      ReportKpi(
        'Units received',
        NumberFormat.decimalPattern().format(t.unitsReceived),
        caption: 'Worth ${_money(t.receivedValue)}',
      ),
    ],
    sections: [
      ReportSection(
        title: 'By ${_periodColumn(r.bucket).toLowerCase()}',
        columns: [ReportColumn(_periodColumn(r.bucket), _periodKind(r.bucket)), ...figureColumns],
        rows: [for (final p in r.byPeriod) figures(p, _periodCell(p.bucket!, r.bucket))],
        footer: footer,
      ),
      ReportSection(
        title: 'By supplier',
        columns: const [ReportColumn('Supplier'), ...figureColumns],
        rows: [for (final s in r.bySupplier) figures(s, s.name)],
        footer: footer,
      ),
      ReportSection(
        title: 'By product',
        columns: const [
          ReportColumn('Product'),
          ReportColumn('SKU'),
          ReportColumn('Purchases', ColumnKind.count),
          ReportColumn('Ordered', ColumnKind.count),
          ReportColumn('Received', ColumnKind.count),
          ReportColumn('Value', ColumnKind.money),
          ReportColumn('Average cost', ColumnKind.money),
          ReportColumn('Lowest', ColumnKind.money),
          ReportColumn('Highest', ColumnKind.money),
        ],
        rows: [
          for (final p in r.byProduct)
            [
              p.name,
              p.sku,
              p.purchases,
              p.unitsOrdered,
              p.unitsReceived,
              p.orderedValue,
              p.averageCost,
              p.minCost,
              p.maxCost,
            ],
        ],
      ),
      ReportSection(
        title: 'By warehouse',
        columns: const [ReportColumn('Warehouse'), ...figureColumns],
        rows: [for (final w in r.byWarehouse) figures(w, w.name)],
        footer: footer,
      ),
      ReportSection(
        title: 'By status',
        columns: const [
          ReportColumn('Status'),
          ReportColumn('Purchases', ColumnKind.count),
          ReportColumn('Total', ColumnKind.money),
        ],
        rows: [
          for (final s in r.byStatus) [purchaseStatusLabel(s.status), s.count, s.total],
        ],
        footer: ['Total', t.count, t.total],
      ),
      ReportSection(
        title: 'Purchases',
        columns: const [
          ReportColumn('Ref.'),
          ReportColumn('Ordered', ColumnKind.date),
          ReportColumn('Supplier'),
          ReportColumn('Warehouse'),
          ReportColumn('Status'),
          ReportColumn('Total', ColumnKind.money),
          ReportColumn('Paid', ColumnKind.money),
          ReportColumn('Not yet paid', ColumnKind.money),
        ],
        rows: [
          for (final p in r.purchases)
            [
              p.reference,
              p.orderDate,
              p.supplier,
              p.warehouse,
              purchaseStatusLabel(p.status),
              p.total,
              p.paid,
              p.unpaid,
            ],
        ],
        footer: ['Total', null, null, null, null, t.total, t.paid, t.unpaid],
      ),
    ],
    notes: [
      'Drafts and cancelled purchases are not counted. Purchases are dated by their order date.',
      if (r.truncated) 'Only the newest 1,000 purchases are listed; the totals cover them all.',
    ],
  );
}

// -------------------------------------------------------- profit & loss

ReportDocument profitLossDocument(ProfitLossReport r, List<(String, String)> filters) {
  double? share(double v) => r.netSales > 0 ? v / r.netSales * 100 : null;
  final statement = <List<Object?>>[
    ['Sales (goods, before tax)', r.grossSales, share(r.grossSales)],
    ['Less discounts', -r.discounts, share(-r.discounts)],
    ['Net sales', r.netSales, share(r.netSales)],
    ['Less cost of goods sold', -r.cogs, share(-r.cogs)],
    ['Gross profit', r.grossProfit, share(r.grossProfit)],
    for (final c in r.expensesByCategory) ['Less ${c.name}', -c.total, share(-c.total)],
    ['Total expenses', -r.expenses, share(-r.expenses)],
    ['Net profit', r.netProfit, share(r.netProfit)],
  ];
  final strong = {2, 4, statement.length - 1};
  return ReportDocument(
    kind: ReportKind.profitLoss,
    range: r.query.range,
    filters: filters,
    kpis: [
      ReportKpi(
        'Net sales',
        _money(r.netSales),
        caption: '${_count(r.salesCount, 'sale')}, after discounts, before tax',
      ),
      ReportKpi(
        'Gross profit',
        _money(r.grossProfit),
        caption: r.grossMargin == null ? 'Net sales less cost of goods' : _margin(r.grossMargin),
        tone: r.grossProfit < 0 ? KpiTone.bad : KpiTone.good,
      ),
      ReportKpi('Expenses', _money(r.expenses), caption: _count(r.expensesByCategory.length, 'category', 'categories')),
      ReportKpi(
        'Net profit',
        _money(r.netProfit),
        caption: r.netMargin == null
            ? (r.netProfit < 0 ? 'A loss' : 'Gross profit less expenses')
            : _margin(r.netMargin),
        tone: r.netProfit < 0 ? KpiTone.bad : KpiTone.good,
      ),
      ReportKpi('Money in', _money(r.moneyIn), caption: 'Received from customers'),
      ReportKpi('Money out', _money(r.moneyOut), caption: 'Paid to suppliers and on expenses'),
      ReportKpi(
        'Net cash',
        _money(r.netCash),
        caption: 'Money in less money out',
        tone: r.netCash < 0 ? KpiTone.bad : KpiTone.good,
      ),
    ],
    sections: [
      ReportSection(
        title: 'Profit and loss',
        columns: const [
          ReportColumn(''),
          ReportColumn('Amount', ColumnKind.money),
          ReportColumn('Of net sales', ColumnKind.percent),
        ],
        rows: statement,
        strongRows: strong,
      ),
      ReportSection(
        title: 'Money in and out',
        columns: const [ReportColumn(''), ReportColumn('Amount', ColumnKind.money)],
        rows: [
          ['Received on sales', r.inFromSales],
          if (!r.query.filters.containsKey('warehouseId')) ['Received on customer accounts', r.inFromAccounts],
          ['Money in', r.moneyIn],
          ['Paid on purchases', -r.outOnPurchases],
          if (!r.query.filters.containsKey('warehouseId')) ['Paid to supplier accounts', -r.outToSupplierAccounts],
          ['Expenses paid', -r.outOnExpenses],
          ['Money out', -r.moneyOut],
          ['Net cash', r.netCash],
        ],
        strongRows: {
          r.query.filters.containsKey('warehouseId') ? 1 : 2,
          r.query.filters.containsKey('warehouseId') ? 4 : 6,
          r.query.filters.containsKey('warehouseId') ? 5 : 7,
        },
      ),
      ReportSection(
        title: 'Money in by payment method',
        columns: const [ReportColumn('Paid by'), ReportColumn('Amount', ColumnKind.money)],
        rows: [
          for (final m in r.inByMethod) [_methodLabel(m.method), m.total],
        ],
        footer: ['Total', r.moneyIn],
      ),
      ReportSection(
        title: 'By ${_periodColumn(r.bucket).toLowerCase()}',
        columns: [
          ReportColumn(_periodColumn(r.bucket), _periodKind(r.bucket)),
          const ReportColumn('Net sales', ColumnKind.money),
          const ReportColumn('Cost', ColumnKind.money),
          const ReportColumn('Gross profit', ColumnKind.money),
          const ReportColumn('Expenses', ColumnKind.money),
          const ReportColumn('Net profit', ColumnKind.money),
          const ReportColumn('Money in', ColumnKind.money),
          const ReportColumn('Money out', ColumnKind.money),
        ],
        rows: [
          for (final p in r.byPeriod)
            [
              _periodCell(p.bucket, r.bucket),
              p.netSales,
              p.cogs,
              p.grossProfit,
              p.expenses,
              p.netProfit,
              p.moneyIn,
              p.moneyOut,
            ],
        ],
        footer: ['Total', r.netSales, r.cogs, r.grossProfit, r.expenses, r.netProfit, r.moneyIn, r.moneyOut],
      ),
    ],
    notes: [
      if (r.taxCollected > 0) '${_money(r.taxCollected)} tax collected on sales is not counted as income.',
      'Money in and out are payments recorded in the period, whatever the date of the sale or purchase.',
      if (r.query.filters.containsKey('warehouseId'))
        'For one warehouse, payments on customer and supplier accounts are left out (they are not tied to a warehouse), and only expenses recorded against it count.',
    ],
  );
}

// -------------------------------------------------------- stock history

ReportDocument stockMovementsDocument(StockMovementsReport r, List<(String, String)> filters) {
  final t = r.totals;
  const inOutColumns = [
    ReportColumn('Movements', ColumnKind.count),
    ReportColumn('Units in', ColumnKind.count),
    ReportColumn('Units out', ColumnKind.count),
    ReportColumn('Net', ColumnKind.signed),
  ];
  List<Object?> inOut(UnitsInOut f) => [f.count, f.unitsIn, f.unitsOut, f.net];
  return ReportDocument(
    kind: ReportKind.stockMovements,
    range: r.query.range,
    filters: filters,
    kpis: [
      ReportKpi('Movements', NumberFormat.decimalPattern().format(t.count)),
      ReportKpi('Units in', NumberFormat.decimalPattern().format(t.unitsIn), tone: KpiTone.good),
      ReportKpi(
        'Units out',
        NumberFormat.decimalPattern().format(t.unitsOut),
        tone: t.unitsOut > 0 ? KpiTone.bad : KpiTone.neutral,
      ),
      ReportKpi('Net change', formatCell(t.net, ColumnKind.signed)),
    ],
    sections: [
      ReportSection(
        title: 'Movements',
        columns: const [
          ReportColumn('When', ColumnKind.dateTime),
          ReportColumn('Type'),
          ReportColumn('Product'),
          ReportColumn('Warehouse'),
          ReportColumn('Change', ColumnKind.signed),
          ReportColumn('Before', ColumnKind.count),
          ReportColumn('After', ColumnKind.count),
          ReportColumn('By'),
          ReportColumn('From'),
          ReportColumn('Reason'),
        ],
        rows: [
          for (final m in r.movements)
            [
              m.createdAt,
              movementTypeLabel(m.type),
              m.product,
              m.warehouse,
              m.quantity,
              m.previousStock,
              m.newStock,
              m.user ?? '',
              m.reference ?? movementSourceLabel(m.source),
              m.reason ?? '',
            ],
        ],
      ),
      ReportSection(
        title: 'By product',
        columns: const [
          ReportColumn('Product'),
          ReportColumn('SKU'),
          ...inOutColumns,
          ReportColumn('Net value', ColumnKind.money),
        ],
        rows: [
          for (final p in r.byProduct) [p.name, p.sku, ...inOut(p.figures), p.netValue],
        ],
        footer: ['Total', null, ...inOut(t), r.byProduct.fold<double>(0, (a, p) => a + p.netValue)],
      ),
      ReportSection(
        title: 'By type',
        columns: const [ReportColumn('Type'), ...inOutColumns],
        rows: [
          for (final x in r.byType) [movementTypeLabel(x.type), ...inOut(x.figures)],
        ],
        footer: ['Total', ...inOut(t)],
      ),
      ReportSection(
        title: 'By person',
        columns: const [ReportColumn('Recorded by'), ...inOutColumns],
        rows: [
          for (final x in r.byUser) [x.name, ...inOut(x.figures)],
        ],
        footer: ['Total', ...inOut(t)],
      ),
    ],
    notes: [
      'Net value is the net change at each product\'s current purchase price.',
      if (r.truncated) 'Only the newest 2,000 movements are listed; the totals cover them all.',
    ],
  );
}

// ---------------------------------------------------------------- Excel

/// The report as a spreadsheet: a summary sheet (the headline figures,
/// filters and notes) and one sheet per table.
List<int> buildReportExcel(ReportDocument doc) {
  final book = Excel.createExcel();
  final summary = book[book.getDefaultSheet()!];
  summary.appendRow([TextCellValue(doc.title)]);
  summary.appendRow([TextCellValue('Period'), TextCellValue(doc.range.dates)]);
  for (final (label, value) in doc.filters) {
    summary.appendRow([TextCellValue(label), TextCellValue(value)]);
  }
  summary.appendRow([]);
  for (final k in doc.kpis) {
    summary.appendRow([TextCellValue(k.label), TextCellValue(k.value), TextCellValue(k.caption ?? '')]);
  }
  if (doc.notes.isNotEmpty) summary.appendRow([]);
  for (final n in doc.notes) {
    summary.appendRow([TextCellValue(n)]);
  }
  book.rename(book.getDefaultSheet()!, 'Summary');

  final used = <String>{'Summary'};
  for (final section in doc.sections) {
    // Sheet names: at most 31 characters, no duplicates.
    var name = section.title.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
    if (name.length > 31) name = name.substring(0, 31);
    while (!used.add(name)) {
      name = '${name.substring(0, name.length.clamp(0, 28))} ${used.length}';
    }
    final sheet = book[name];
    sheet.appendRow([for (final c in section.columns) TextCellValue(c.label)]);
    for (final row in [...section.rows, ?section.footer]) {
      sheet.appendRow([for (final (i, v) in row.indexed) _excelCell(v, section.columns[i].kind)]);
    }
  }
  return book.encode() ?? const [];
}

CellValue? _excelCell(Object? v, ColumnKind kind) {
  if (v == null) return null;
  if (v is DateTime) {
    return TextCellValue(DateFormat(kind == ColumnKind.dateTime ? 'yyyy-MM-dd HH:mm' : 'yyyy-MM-dd').format(v));
  }
  if (v is int) return IntCellValue(v);
  if (v is double) return DoubleCellValue(kind == ColumnKind.percent ? double.parse(v.toStringAsFixed(2)) : v);
  return TextCellValue('$v');
}
