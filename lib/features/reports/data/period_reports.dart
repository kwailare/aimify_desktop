import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../parties/data/parties_repository.dart';
import '../../purchases/data/purchases_repository.dart';
import '../../sales/data/sales_repository.dart';

// The period reports (feature checklist step 14): sales, purchases, profit
// & loss with money in and out, and stock movement history, each for a
// period and narrowed by filters. The server works them out; see
// docs/desktop-api.md, "Reports for a period".

enum ReportPreset { today, thisWeek, thisMonth, lastMonth, thisQuarter, thisYear, last12Months, custom }

extension ReportPresetX on ReportPreset {
  String get label => switch (this) {
    ReportPreset.today => 'Today',
    ReportPreset.thisWeek => 'This week',
    ReportPreset.thisMonth => 'This month',
    ReportPreset.lastMonth => 'Last month',
    ReportPreset.thisQuarter => 'This quarter',
    ReportPreset.thisYear => 'This year',
    ReportPreset.last12Months => 'Last 12 months',
    ReportPreset.custom => 'Custom dates…',
  };
}

/// A report period in local time, [to] exclusive.
@immutable
class ReportRange {
  const ReportRange(this.preset, this.from, this.to);

  factory ReportRange.of(ReportPreset preset, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final (from, to) = switch (preset) {
      ReportPreset.today => (today, DateTime(now.year, now.month, now.day + 1)),
      ReportPreset.thisWeek => () {
        final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        return (monday, DateTime(monday.year, monday.month, monday.day + 7));
      }(),
      ReportPreset.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
      ReportPreset.thisQuarter => () {
        final first = ((now.month - 1) ~/ 3) * 3 + 1;
        return (DateTime(now.year, first), DateTime(now.year, first + 3));
      }(),
      ReportPreset.thisYear => (DateTime(now.year), DateTime(now.year + 1)),
      ReportPreset.last12Months => (DateTime(now.year, now.month - 11), DateTime(now.year, now.month + 1)),
      ReportPreset.thisMonth ||
      ReportPreset.custom => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
    };
    return ReportRange(preset, from, to);
  }

  /// From the first day to the last, both included.
  factory ReportRange.custom(DateTime first, DateTime last) => ReportRange(
    ReportPreset.custom,
    DateTime(first.year, first.month, first.day),
    DateTime(last.year, last.month, last.day + 1),
  );

  final ReportPreset preset;
  final DateTime from;
  final DateTime to;

  DateTime get lastDay => DateTime(to.year, to.month, to.day - 1);

  /// "1 Oct 2026 – 31 Oct 2026", or one day.
  String get dates {
    final f = DateFormat('d MMM yyyy');
    return lastDay == from ? f.format(from) : '${f.format(from)} – ${f.format(lastDay)}';
  }

  String get label => preset == ReportPreset.custom ? dates : preset.label;

  /// For file names: 2026-10 for a calendar month, else the two dates.
  String get slug {
    final d = DateFormat('yyyy-MM-dd');
    if (from.day == 1 && to == DateTime(from.year, from.month + 1)) return DateFormat('yyyy-MM').format(from);
    return '${d.format(from)}_${d.format(lastDay)}';
  }

  @override
  bool operator ==(Object other) =>
      other is ReportRange && other.from == from && other.to == to && other.preset == preset;

  @override
  int get hashCode => Object.hash(preset, from, to);
}

enum ReportKind { sales, purchases, profitLoss, stockMovements }

extension ReportKindX on ReportKind {
  String get title => switch (this) {
    ReportKind.sales => 'Sales report',
    ReportKind.purchases => 'Purchase report',
    ReportKind.profitLoss => 'Profit & loss',
    ReportKind.stockMovements => 'Stock movement history',
  };

  String get url => switch (this) {
    ReportKind.sales => ApiConstants.salesReport,
    ReportKind.purchases => ApiConstants.purchasesReport,
    ReportKind.profitLoss => ApiConstants.profitLossReport,
    ReportKind.stockMovements => ApiConstants.stockMovementsReport,
  };

  /// For file names.
  String get slug => switch (this) {
    ReportKind.sales => 'sales-report',
    ReportKind.purchases => 'purchase-report',
    ReportKind.profitLoss => 'profit-and-loss',
    ReportKind.stockMovements => 'stock-movements',
  };
}

/// One report's period and filters (filter name to value, as the server
/// takes them: `warehouseId`, `customerId`, `type`...).
@immutable
class ReportQuery {
  const ReportQuery(this.kind, this.range, [this.filters = const {}]);

  final ReportKind kind;
  final ReportRange range;
  final Map<String, String> filters;

  @override
  bool operator ==(Object other) =>
      other is ReportQuery && other.kind == kind && other.range == range && mapEquals(other.filters, filters);

  @override
  int get hashCode =>
      Object.hash(kind, range, Object.hashAllUnordered(filters.entries.map((e) => '${e.key}=${e.value}')));
}

// ---------------------------------------------------------------- JSON

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
String _s(Object? v) => v as String? ?? '';
List<Map<String, dynamic>> _rows(Object? v) => [
  for (final r in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(r as Map),
];
DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();

/// A day or month bucket (YYYY-MM-DD, local) as a date.
DateTime _bucket(Object? v) {
  final p = (v as String).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

typedef Person = ({String id, String name});

List<Person> _people(Object? v) => [for (final p in _rows(v)) (id: _s(p['id']), name: _s(p['name']))];

// ---------------------------------------------------------------- sales

/// Sales figures for the whole period or one group (a day, customer...).
class SalesFigures {
  const SalesFigures({
    this.id,
    this.name = '',
    this.bucket,
    required this.count,
    required this.units,
    required this.total,
    required this.paid,
    required this.outstanding,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    this.margin,
  });

  factory SalesFigures.fromJson(Map<String, dynamic> j, {String? idKey}) => SalesFigures(
    id: idKey == null ? null : j[idKey] as String?,
    name: _s(j['name']),
    bucket: j['bucket'] == null ? null : _bucket(j['bucket']),
    count: _i(j['count']),
    units: _i(j['units']),
    total: _d(j['total']),
    paid: _d(j['paid']),
    outstanding: _d(j['outstanding']),
    revenue: _d(j['revenue']),
    cogs: _d(j['cogs']),
    grossProfit: _d(j['grossProfit']),
    margin: _dn(j['margin']),
  );

  final String? id;
  final String name;
  final DateTime? bucket;
  final int count;
  final int units;

  /// What the sales came to, tax included.
  final double total;
  final double paid;
  final double outstanding;

  /// Goods after discounts, before tax.
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double? margin;
}

class ProductSales {
  const ProductSales({
    required this.productId,
    required this.name,
    required this.sku,
    required this.unit,
    required this.sales,
    required this.units,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    this.margin,
  });

  final String productId;
  final String name;
  final String sku;
  final String unit;
  final int sales;
  final int units;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double? margin;
}

class SaleRow {
  const SaleRow({
    required this.id,
    required this.reference,
    required this.saleDate,
    required this.customer,
    required this.warehouse,
    this.staff,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
    required this.outstanding,
  });

  final String id;
  final String reference;
  final DateTime saleDate;
  final String customer;
  final String warehouse;
  final String? staff;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double paid;
  final double outstanding;
}

class SalesReport {
  const SalesReport({
    required this.query,
    required this.bucket,
    required this.totals,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.averageSale,
    required this.voidedCount,
    required this.voidedTotal,
    this.byPeriod = const [],
    this.byProduct = const [],
    this.byCustomer = const [],
    this.byStaff = const [],
    this.byWarehouse = const [],
    this.sales = const [],
    this.truncated = false,
    this.people = const [],
  });

  factory SalesReport.fromJson(ReportQuery query, Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from(j['totals'] as Map);
    final voided = Map<String, dynamic>.from(j['voided'] as Map? ?? const {});
    return SalesReport(
      query: query,
      bucket: _s(j['bucket']),
      totals: SalesFigures.fromJson(t),
      subtotal: _d(t['subtotal']),
      discount: _d(t['discount']),
      tax: _d(t['tax']),
      averageSale: _d(t['averageSale']),
      voidedCount: _i(voided['count']),
      voidedTotal: _d(voided['total']),
      byPeriod: [for (final r in _rows(j['byPeriod'])) SalesFigures.fromJson(r)],
      byProduct: [
        for (final r in _rows(j['byProduct']))
          ProductSales(
            productId: _s(r['productId']),
            name: _s(r['name']),
            sku: _s(r['sku']),
            unit: _s(r['unit']),
            sales: _i(r['sales']),
            units: _i(r['units']),
            revenue: _d(r['revenue']),
            cogs: _d(r['cogs']),
            grossProfit: _d(r['grossProfit']),
            margin: _dn(r['margin']),
          ),
      ],
      byCustomer: [for (final r in _rows(j['byCustomer'])) SalesFigures.fromJson(r, idKey: 'customerId')],
      byStaff: [for (final r in _rows(j['byStaff'])) SalesFigures.fromJson(r, idKey: 'userId')],
      byWarehouse: [for (final r in _rows(j['byWarehouse'])) SalesFigures.fromJson(r, idKey: 'warehouseId')],
      sales: [
        for (final r in _rows(j['sales']))
          SaleRow(
            id: _s(r['id']),
            reference: _s(r['reference']),
            saleDate: _date(r['saleDate']),
            customer: _s(r['customer']),
            warehouse: _s(r['warehouse']),
            staff: r['staff'] as String?,
            subtotal: _d(r['subtotal']),
            discount: _d(r['discount']),
            tax: _d(r['tax']),
            total: _d(r['total']),
            paid: _d(r['paid']),
            outstanding: _d(r['outstanding']),
          ),
      ],
      truncated: j['truncated'] == true,
      people: _people(j['people']),
    );
  }

  final ReportQuery query;
  final String bucket;
  final SalesFigures totals;
  final double subtotal;
  final double discount;
  final double tax;
  final double averageSale;
  final int voidedCount;
  final double voidedTotal;
  final List<SalesFigures> byPeriod;
  final List<ProductSales> byProduct;
  final List<SalesFigures> byCustomer;
  final List<SalesFigures> byStaff;
  final List<SalesFigures> byWarehouse;
  final List<SaleRow> sales;
  final bool truncated;
  final List<Person> people;
}

// ------------------------------------------------------------ purchases

class PurchaseFigures {
  const PurchaseFigures({
    this.id,
    this.name = '',
    this.bucket,
    required this.count,
    required this.total,
    required this.paid,
    required this.unpaid,
    required this.unitsOrdered,
    required this.unitsReceived,
    required this.receivedValue,
  });

  factory PurchaseFigures.fromJson(Map<String, dynamic> j, {String? idKey}) => PurchaseFigures(
    id: idKey == null ? null : j[idKey] as String?,
    name: _s(j['name']),
    bucket: j['bucket'] == null ? null : _bucket(j['bucket']),
    count: _i(j['count']),
    total: _d(j['total']),
    paid: _d(j['paid']),
    unpaid: _d(j['unpaid']),
    unitsOrdered: _i(j['unitsOrdered']),
    unitsReceived: _i(j['unitsReceived']),
    receivedValue: _d(j['receivedValue']),
  );

  final String? id;
  final String name;
  final DateTime? bucket;
  final int count;
  final double total;
  final double paid;
  final double unpaid;
  final int unitsOrdered;
  final int unitsReceived;
  final double receivedValue;
}

class ProductPurchases {
  const ProductPurchases({
    required this.productId,
    required this.name,
    required this.sku,
    required this.unit,
    required this.purchases,
    required this.unitsOrdered,
    required this.unitsReceived,
    required this.orderedValue,
    required this.averageCost,
    required this.minCost,
    required this.maxCost,
  });

  final String productId;
  final String name;
  final String sku;
  final String unit;
  final int purchases;
  final int unitsOrdered;
  final int unitsReceived;
  final double orderedValue;
  final double averageCost;
  final double minCost;
  final double maxCost;
}

class PurchaseRow {
  const PurchaseRow({
    required this.id,
    required this.reference,
    required this.orderDate,
    required this.supplier,
    required this.warehouse,
    required this.status,
    required this.total,
    required this.paid,
    required this.unpaid,
  });

  final String id;
  final String reference;
  final DateTime orderDate;
  final String supplier;
  final String warehouse;
  final String status;
  final double total;
  final double paid;
  final double unpaid;
}

class PurchasesReport {
  const PurchasesReport({
    required this.query,
    required this.bucket,
    required this.totals,
    required this.orderedValue,
    this.byStatus = const [],
    this.byPeriod = const [],
    this.bySupplier = const [],
    this.byWarehouse = const [],
    this.byProduct = const [],
    this.purchases = const [],
    this.truncated = false,
  });

  factory PurchasesReport.fromJson(ReportQuery query, Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from(j['totals'] as Map);
    return PurchasesReport(
      query: query,
      bucket: _s(j['bucket']),
      totals: PurchaseFigures.fromJson(t),
      orderedValue: _d(t['orderedValue']),
      byStatus: [
        for (final r in _rows(j['byStatus'])) (status: _s(r['status']), count: _i(r['count']), total: _d(r['total'])),
      ],
      byPeriod: [for (final r in _rows(j['byPeriod'])) PurchaseFigures.fromJson(r)],
      bySupplier: [for (final r in _rows(j['bySupplier'])) PurchaseFigures.fromJson(r, idKey: 'supplierId')],
      byWarehouse: [for (final r in _rows(j['byWarehouse'])) PurchaseFigures.fromJson(r, idKey: 'warehouseId')],
      byProduct: [
        for (final r in _rows(j['byProduct']))
          ProductPurchases(
            productId: _s(r['productId']),
            name: _s(r['name']),
            sku: _s(r['sku']),
            unit: _s(r['unit']),
            purchases: _i(r['purchases']),
            unitsOrdered: _i(r['unitsOrdered']),
            unitsReceived: _i(r['unitsReceived']),
            orderedValue: _d(r['orderedValue']),
            averageCost: _d(r['averageCost']),
            minCost: _d(r['minCost']),
            maxCost: _d(r['maxCost']),
          ),
      ],
      purchases: [
        for (final r in _rows(j['purchases']))
          PurchaseRow(
            id: _s(r['id']),
            reference: _s(r['reference']),
            orderDate: _date(r['orderDate']),
            supplier: _s(r['supplier']),
            warehouse: _s(r['warehouse']),
            status: _s(r['status']),
            total: _d(r['total']),
            paid: _d(r['paid']),
            unpaid: _d(r['unpaid']),
          ),
      ],
      truncated: j['truncated'] == true,
    );
  }

  final ReportQuery query;
  final String bucket;
  final PurchaseFigures totals;
  final double orderedValue;
  final List<({String status, int count, double total})> byStatus;
  final List<PurchaseFigures> byPeriod;
  final List<PurchaseFigures> bySupplier;
  final List<PurchaseFigures> byWarehouse;
  final List<ProductPurchases> byProduct;
  final List<PurchaseRow> purchases;
  final bool truncated;
}

// -------------------------------------------------------- profit & loss

class ProfitLossPeriod {
  const ProfitLossPeriod({
    required this.bucket,
    required this.netSales,
    required this.cogs,
    required this.grossProfit,
    required this.expenses,
    required this.netProfit,
    required this.moneyIn,
    required this.moneyOut,
  });

  final DateTime bucket;
  final double netSales;
  final double cogs;
  final double grossProfit;
  final double expenses;
  final double netProfit;
  final double moneyIn;
  final double moneyOut;
}

class ProfitLossReport {
  const ProfitLossReport({
    required this.query,
    required this.bucket,
    required this.salesCount,
    required this.grossSales,
    required this.discounts,
    required this.netSales,
    required this.cogs,
    required this.grossProfit,
    this.grossMargin,
    required this.expenses,
    this.expensesByCategory = const [],
    required this.netProfit,
    this.netMargin,
    required this.taxCollected,
    required this.inFromSales,
    required this.inFromAccounts,
    required this.moneyIn,
    this.inByMethod = const [],
    required this.outOnPurchases,
    required this.outToSupplierAccounts,
    required this.outOnExpenses,
    required this.moneyOut,
    this.byPeriod = const [],
  });

  factory ProfitLossReport.fromJson(ReportQuery query, Map<String, dynamic> j) {
    final p = Map<String, dynamic>.from(j['profit'] as Map);
    final cash = Map<String, dynamic>.from(j['cash'] as Map);
    final cashIn = Map<String, dynamic>.from(cash['in'] as Map);
    final cashOut = Map<String, dynamic>.from(cash['out'] as Map);
    return ProfitLossReport(
      query: query,
      bucket: _s(j['bucket']),
      salesCount: _i(p['salesCount']),
      grossSales: _d(p['grossSales']),
      discounts: _d(p['discounts']),
      netSales: _d(p['netSales']),
      cogs: _d(p['cogs']),
      grossProfit: _d(p['grossProfit']),
      grossMargin: _dn(p['grossMargin']),
      expenses: _d(p['expenses']),
      expensesByCategory: [
        for (final c in _rows(p['expensesByCategory']))
          (name: _s(c['name']), total: _d(c['total']), count: _i(c['count'])),
      ],
      netProfit: _d(p['netProfit']),
      netMargin: _dn(p['netMargin']),
      taxCollected: _d(p['taxCollected']),
      inFromSales: _d(cashIn['sales']),
      inFromAccounts: _d(cashIn['customerAccounts']),
      moneyIn: _d(cashIn['total']),
      inByMethod: [for (final m in _rows(cashIn['byMethod'])) (method: _s(m['method']), total: _d(m['total']))],
      outOnPurchases: _d(cashOut['purchases']),
      outToSupplierAccounts: _d(cashOut['supplierAccounts']),
      outOnExpenses: _d(cashOut['expenses']),
      moneyOut: _d(cashOut['total']),
      byPeriod: [
        for (final r in _rows(j['byPeriod']))
          ProfitLossPeriod(
            bucket: _bucket(r['bucket']),
            netSales: _d(r['netSales']),
            cogs: _d(r['cogs']),
            grossProfit: _d(r['grossProfit']),
            expenses: _d(r['expenses']),
            netProfit: _d(r['netProfit']),
            moneyIn: _d(r['moneyIn']),
            moneyOut: _d(r['moneyOut']),
          ),
      ],
    );
  }

  final ReportQuery query;
  final String bucket;
  final int salesCount;
  final double grossSales;
  final double discounts;
  final double netSales;
  final double cogs;
  final double grossProfit;
  final double? grossMargin;
  final double expenses;
  final List<({String name, double total, int count})> expensesByCategory;
  final double netProfit;
  final double? netMargin;
  final double taxCollected;
  final double inFromSales;
  final double inFromAccounts;
  final double moneyIn;
  final List<({String method, double total})> inByMethod;
  final double outOnPurchases;
  final double outToSupplierAccounts;
  final double outOnExpenses;
  final double moneyOut;
  final List<ProfitLossPeriod> byPeriod;

  double get netCash => moneyIn - moneyOut;
}

// -------------------------------------------------------- stock history

typedef UnitsInOut = ({int count, int unitsIn, int unitsOut, int net});

UnitsInOut _inOut(Map<String, dynamic> j) =>
    (count: _i(j['count']), unitsIn: _i(j['unitsIn']), unitsOut: _i(j['unitsOut']), net: _i(j['net']));

class MovementRow {
  const MovementRow({
    required this.id,
    required this.createdAt,
    required this.type,
    required this.quantity,
    required this.previousStock,
    required this.newStock,
    this.reason,
    required this.product,
    required this.sku,
    required this.unit,
    required this.warehouse,
    this.user,
    required this.source,
    this.reference,
  });

  final String id;
  final DateTime createdAt;
  final String type;
  final int quantity;
  final int previousStock;
  final int newStock;
  final String? reason;
  final String product;
  final String sku;
  final String unit;
  final String warehouse;
  final String? user;

  /// manual, sale or purchase.
  final String source;

  /// The sale or purchase behind it (INV-0001, PO-0001).
  final String? reference;
}

class StockMovementsReport {
  const StockMovementsReport({
    required this.query,
    required this.totals,
    this.byType = const [],
    this.byProduct = const [],
    this.byUser = const [],
    this.movements = const [],
    this.truncated = false,
    this.people = const [],
  });

  factory StockMovementsReport.fromJson(ReportQuery query, Map<String, dynamic> j) => StockMovementsReport(
    query: query,
    totals: _inOut(Map<String, dynamic>.from(j['totals'] as Map)),
    byType: [for (final r in _rows(j['byType'])) (type: _s(r['type']), figures: _inOut(r))],
    byProduct: [
      for (final r in _rows(j['byProduct']))
        (name: _s(r['name']), sku: _s(r['sku']), unit: _s(r['unit']), figures: _inOut(r), netValue: _d(r['netValue'])),
    ],
    byUser: [for (final r in _rows(j['byUser'])) (name: _s(r['name']), figures: _inOut(r))],
    movements: [
      for (final r in _rows(j['movements']))
        MovementRow(
          id: _s(r['id']),
          createdAt: _date(r['createdAt']),
          type: _s(r['type']),
          quantity: _i(r['quantity']),
          previousStock: _i(r['previousStock']),
          newStock: _i(r['newStock']),
          reason: r['reason'] as String?,
          product: _s(r['product']),
          sku: _s(r['sku']),
          unit: _s(r['unit']),
          warehouse: _s(r['warehouse']),
          user: r['user'] as String?,
          source: _s(r['source']),
          reference: r['reference'] as String?,
        ),
    ],
    truncated: j['truncated'] == true,
    people: _people(j['people']),
  );

  final ReportQuery query;
  final UnitsInOut totals;
  final List<({String type, UnitsInOut figures})> byType;
  final List<({String name, String sku, String unit, UnitsInOut figures, double netValue})> byProduct;
  final List<({String name, UnitsInOut figures})> byUser;
  final List<MovementRow> movements;
  final bool truncated;
  final List<Person> people;
}

String movementTypeLabel(String type) => switch (type) {
  'stock_in' => 'Stock in',
  'stock_out' => 'Stock out',
  'adjustment' => 'Adjustment',
  'count' => 'Stock count',
  _ => type,
};

String movementSourceLabel(String source) => switch (source) {
  'sale' => 'Sale',
  'purchase' => 'Purchase',
  _ => 'Recorded by hand',
};

String purchaseStatusLabel(String status) => switch (status) {
  'pending' => 'Ordered',
  'partially_received' => 'Partly received',
  'received' => 'Received',
  _ => status,
};

// ---------------------------------------------------------- repository

class PeriodReportsRepository {
  PeriodReportsRepository(this._api);

  final AuthedApi _api;

  /// The report's JSON. Falls back to the last saved copy of the same query
  /// offline.
  Future<Map<String, dynamic>> fetch(ReportQuery q) {
    String iso(DateTime d) => d.toUtc().toIso8601String();
    final params = {
      'from': iso(q.range.from),
      'to': iso(q.range.to),
      'tz': '${q.range.from.timeZoneOffset.inMinutes}',
      // By month for anything longer than about two months.
      if (q.range.to.difference(q.range.from).inDays > 62) 'bucket': 'month',
      ...q.filters,
    };
    final url = Uri.parse(q.kind.url).replace(queryParameters: params);
    final key = [
      q.kind.slug,
      q.range.slug,
      for (final e in (q.filters.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) '${e.key}-${e.value}',
    ];
    return _api.get(url.toString(), cacheKey: 'report_${key.join('_')}');
  }
}

final periodReportsRepositoryProvider = Provider<PeriodReportsRepository>(
  (ref) => PeriodReportsRepository(ref.watch(authedApiProvider)),
);

/// Who may see each report: the same module permissions as the screens.
final canSeeReportProvider = Provider.family<bool, ReportKind>((ref, kind) {
  bool holds(String p) => ref.watch(holdsPermissionProvider(p));
  return switch (kind) {
    ReportKind.sales => holds(Permissions.salesView),
    ReportKind.purchases => holds(Permissions.purchasesView),
    ReportKind.profitLoss => holds(Permissions.salesView) && holds(Permissions.expensesView),
    ReportKind.stockMovements => holds(Permissions.stockView),
  };
});

/// The period the period reports show, shared by their tabs.
final reportRangeProvider = StateProvider<ReportRange>((ref) => ReportRange.of(ReportPreset.thisMonth, DateTime.now()));

/// Each report's filters.
final reportFiltersProvider = StateProvider.family<Map<String, String>, ReportKind>((ref, kind) => const {});

/// The report's JSON for [query], re-read when the records behind it change.
/// Invalidate it (not the parsed report) to fetch again.
final reportJsonProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, ReportQuery>((ref, q) async {
  if (ref.watch(sessionUserIdProvider) == null || !ref.watch(canSeeReportProvider(q.kind))) return null;
  void onChange<T>(AsyncValue<T>? previous, AsyncValue<T> next) {
    if (previous?.hasValue == true && next.hasValue && !identical(previous!.value, next.value)) ref.invalidateSelf();
  }

  switch (q.kind) {
    case ReportKind.sales:
      ref.listen(salesProvider, onChange);
      ref.watch(debtsChangedProvider);
    case ReportKind.purchases:
      ref.watch(purchasesChangedProvider);
    case ReportKind.profitLoss:
      ref.listen(salesProvider, onChange);
      ref.listen(expensesProvider, onChange);
      ref.watch(purchasesChangedProvider);
      ref.watch(debtsChangedProvider);
    case ReportKind.stockMovements:
      ref.listen(movementsProvider, onChange);
      ref.listen(salesProvider, onChange);
      ref.watch(purchasesChangedProvider);
  }
  return ref.watch(periodReportsRepositoryProvider).fetch(q);
});

final salesReportProvider = FutureProvider.autoDispose.family<SalesReport?, ReportQuery>((ref, q) async {
  final json = await ref.watch(reportJsonProvider(q).future);
  return json == null ? null : SalesReport.fromJson(q, json);
});

final purchasesReportProvider = FutureProvider.autoDispose.family<PurchasesReport?, ReportQuery>((ref, q) async {
  final json = await ref.watch(reportJsonProvider(q).future);
  return json == null ? null : PurchasesReport.fromJson(q, json);
});

final profitLossReportProvider = FutureProvider.autoDispose.family<ProfitLossReport?, ReportQuery>((ref, q) async {
  final json = await ref.watch(reportJsonProvider(q).future);
  return json == null ? null : ProfitLossReport.fromJson(q, json);
});

final stockMovementsReportProvider = FutureProvider.autoDispose.family<StockMovementsReport?, ReportQuery>((
  ref,
  q,
) async {
  final json = await ref.watch(reportJsonProvider(q).future);
  return json == null ? null : StockMovementsReport.fromJson(q, json);
});
