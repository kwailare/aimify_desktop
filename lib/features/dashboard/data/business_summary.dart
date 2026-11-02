import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../parties/data/parties_repository.dart';
import '../../purchases/data/purchases_repository.dart';
import '../../sales/data/sales_repository.dart';

/// The dashboard's period, in local time, with the one it is compared to.
enum DashboardPeriod { today, week, month, lastMonth, year }

extension DashboardPeriodX on DashboardPeriod {
  String get label => switch (this) {
        DashboardPeriod.today => 'Today',
        DashboardPeriod.week => 'This week',
        DashboardPeriod.month => 'This month',
        DashboardPeriod.lastMonth => 'Last month',
        DashboardPeriod.year => 'This year',
      };

  /// What the comparison is called on the cards.
  String get versus => switch (this) {
        DashboardPeriod.today => 'vs yesterday',
        DashboardPeriod.week => 'vs last week',
        DashboardPeriod.month => 'vs last month',
        DashboardPeriod.lastMonth => 'vs the month before',
        DashboardPeriod.year => 'vs last year',
      };

  /// (from, to, compareFrom, compareTo), local, `to` exclusive.
  (DateTime, DateTime, DateTime, DateTime) ranges(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      DashboardPeriod.today => (today, today.add(const Duration(days: 1)), today.subtract(const Duration(days: 1)), today),
      DashboardPeriod.week => () {
          final start = today.subtract(Duration(days: today.weekday - 1));
          return (start, start.add(const Duration(days: 7)), start.subtract(const Duration(days: 7)), start);
        }(),
      DashboardPeriod.month => (
          DateTime(now.year, now.month),
          DateTime(now.year, now.month + 1),
          DateTime(now.year, now.month - 1),
          DateTime(now.year, now.month),
        ),
      DashboardPeriod.lastMonth => (
          DateTime(now.year, now.month - 1),
          DateTime(now.year, now.month),
          DateTime(now.year, now.month - 2),
          DateTime(now.year, now.month - 1),
        ),
      DashboardPeriod.year => (DateTime(now.year), DateTime(now.year + 1), DateTime(now.year - 1), DateTime(now.year)),
    };
  }

  String get bucket => this == DashboardPeriod.year ? 'month' : 'day';
}

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _dn(Object? v) => (v as num?)?.toDouble();
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
List<Map<String, dynamic>> _rows(Object? v) =>
    [for (final row in (v as List<dynamic>? ?? const [])) Map<String, dynamic>.from(row as Map)];

class TrendPoint {
  const TrendPoint(this.bucket, this.value, [this.second = 0]);

  /// The first day of the day or month, local.
  final DateTime bucket;
  final double value;

  /// Sales: the gross profit for the same bucket.
  final double second;
}

DateTime _bucket(Object? v) => DateTime.parse(v as String);

class SalesSummary {
  const SalesSummary({
    required this.total,
    required this.count,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    this.margin,
    required this.previousTotal,
    required this.previousGrossProfit,
    this.change,
    this.grossProfitChange,
    this.trend = const [],
    this.topProducts = const [],
    this.topCustomers = const [],
    this.byWarehouse = const [],
  });

  final double total;
  final int count;
  final double revenue;
  final double cogs;
  final double grossProfit;
  final double? margin;
  final double previousTotal;
  final double previousGrossProfit;
  final double? change;
  final double? grossProfitChange;
  final List<TrendPoint> trend;
  final List<({String name, String unit, int units, double revenue, double grossProfit})> topProducts;
  final List<({String name, double total, int count})> topCustomers;
  final List<({String? warehouseId, String name, double total})> byWarehouse;

  factory SalesSummary.fromJson(Map<String, dynamic> j) {
    final previous = Map<String, dynamic>.from(j['previous'] as Map? ?? const {});
    return SalesSummary(
      total: _d(j['total']),
      count: _i(j['count']),
      revenue: _d(j['revenue']),
      cogs: _d(j['cogs']),
      grossProfit: _d(j['grossProfit']),
      margin: _dn(j['margin']),
      previousTotal: _d(previous['total']),
      previousGrossProfit: _d(previous['grossProfit']),
      change: _dn(j['change']),
      grossProfitChange: _dn(j['grossProfitChange']),
      trend: [for (final t in _rows(j['trend'])) TrendPoint(_bucket(t['bucket']), _d(t['sales']), _d(t['grossProfit']))],
      topProducts: [
        for (final p in _rows(j['topProducts']))
          (
            name: p['name'] as String? ?? '',
            unit: p['unit'] as String? ?? '',
            units: _i(p['units']),
            revenue: _d(p['revenue']),
            grossProfit: _d(p['grossProfit']),
          ),
      ],
      topCustomers: [
        for (final c in _rows(j['topCustomers'])) (name: c['name'] as String? ?? '', total: _d(c['total']), count: _i(c['count'])),
      ],
      byWarehouse: [
        for (final w in _rows(j['byWarehouse']))
          (warehouseId: w['warehouseId'] as String?, name: w['name'] as String? ?? '', total: _d(w['total'])),
      ],
    );
  }
}

/// Purchases or expenses: a total, the earlier one, the change and the trend.
class MoneySummary {
  const MoneySummary({required this.total, required this.count, required this.previous, this.change, this.trend = const [], this.byCategory = const []});

  final double total;
  final int count;
  final double previous;
  final double? change;
  final List<TrendPoint> trend;

  /// Expenses only.
  final List<({String name, double total})> byCategory;

  factory MoneySummary.fromJson(Map<String, dynamic> j) => MoneySummary(
        total: _d(j['total']),
        count: _i(j['count']),
        previous: _d((j['previous'] as Map?)?['total']),
        change: _dn(j['change']),
        trend: [for (final t in _rows(j['trend'])) TrendPoint(_bucket(t['bucket']), _d(t['total']))],
        byCategory: [for (final c in _rows(j['byCategory'])) (name: c['name'] as String? ?? '', total: _d(c['total']))],
      );
}

class DebtSummary {
  const DebtSummary({required this.owed, required this.overdue, required this.parties});

  final double owed;
  final double overdue;
  final int parties;

  factory DebtSummary.fromJson(Map<String, dynamic> j) =>
      DebtSummary(owed: _d(j['owed']), overdue: _d(j['overdue']), parties: _i(j['parties']));
}

class StockSummary {
  const StockSummary({required this.valueAtCost, required this.valueAtRetail, this.byWarehouse = const []});

  final double valueAtCost;
  final double valueAtRetail;
  final List<({String? warehouseId, String name, int units, double valueAtCost})> byWarehouse;

  factory StockSummary.fromJson(Map<String, dynamic> j) => StockSummary(
        valueAtCost: _d(j['valueAtCost']),
        valueAtRetail: _d(j['valueAtRetail']),
        byWarehouse: [
          for (final w in _rows(j['byWarehouse']))
            (warehouseId: w['warehouseId'] as String?, name: w['name'] as String? ?? '', units: _i(w['units']), valueAtCost: _d(w['valueAtCost'])),
        ],
      );
}

/// `GET /api/v1/dashboard`: only the sections this role may see are set.
class BusinessSummary {
  const BusinessSummary({
    required this.period,
    required this.bucket,
    this.sales,
    this.purchases,
    this.expenses,
    this.netProfit,
    this.netProfitPrevious,
    this.netProfitChange,
    this.receivables,
    this.payables,
    this.stock,
  });

  final DashboardPeriod period;

  /// 'day' or 'month'.
  final String bucket;
  final SalesSummary? sales;
  final MoneySummary? purchases;
  final MoneySummary? expenses;
  final double? netProfit;
  final double? netProfitPrevious;
  final double? netProfitChange;
  final DebtSummary? receivables;
  final DebtSummary? payables;
  final StockSummary? stock;

  bool get hasMoney => sales != null || purchases != null || expenses != null || receivables != null || payables != null;

  /// Without the sections [holds] says no to. The server already leaves
  /// them out; this covers a copy saved offline for someone else.
  BusinessSummary onlyWhat(bool Function(String permission) holds) {
    final canSales = holds('sales.view');
    final canExpenses = holds('expenses.view');
    return BusinessSummary(
      period: period,
      bucket: bucket,
      sales: canSales ? sales : null,
      purchases: holds('purchases.view') ? purchases : null,
      expenses: canExpenses ? expenses : null,
      netProfit: canSales && canExpenses ? netProfit : null,
      netProfitPrevious: canSales && canExpenses ? netProfitPrevious : null,
      netProfitChange: canSales && canExpenses ? netProfitChange : null,
      receivables: holds('customers.view') ? receivables : null,
      payables: holds('suppliers.view') ? payables : null,
      stock: holds('products.view') ? stock : null,
    );
  }

  factory BusinessSummary.fromJson(DashboardPeriod period, Map<String, dynamic> j) {
    Map<String, dynamic>? section(String key) => j[key] == null ? null : Map<String, dynamic>.from(j[key] as Map);
    final net = section('netProfit');
    return BusinessSummary(
      period: period,
      bucket: j['bucket'] as String? ?? 'day',
      sales: section('sales') == null ? null : SalesSummary.fromJson(section('sales')!),
      purchases: section('purchases') == null ? null : MoneySummary.fromJson(section('purchases')!),
      expenses: section('expenses') == null ? null : MoneySummary.fromJson(section('expenses')!),
      netProfit: net == null ? null : _d(net['value']),
      netProfitPrevious: net == null ? null : _d(net['previous']),
      netProfitChange: net == null ? null : _dn(net['change']),
      receivables: section('receivables') == null ? null : DebtSummary.fromJson(section('receivables')!),
      payables: section('payables') == null ? null : DebtSummary.fromJson(section('payables')!),
      stock: section('stock') == null ? null : StockSummary.fromJson(section('stock')!),
    );
  }
}

class BusinessSummaryRepository {
  BusinessSummaryRepository(this._api);

  final AuthedApi _api;

  /// Falls back to the last saved copy of the same period offline.
  Future<BusinessSummary> fetch(DashboardPeriod period, {DateTime? now}) async {
    final (from, to, compareFrom, compareTo) = period.ranges(now ?? DateTime.now());
    String iso(DateTime d) => Uri.encodeQueryComponent(d.toUtc().toIso8601String());
    final tz = (now ?? DateTime.now()).timeZoneOffset.inMinutes;
    final json = await _api.get(
      '${ApiConstants.dashboard}?from=${iso(from)}&to=${iso(to)}&compareFrom=${iso(compareFrom)}'
      '&compareTo=${iso(compareTo)}&bucket=${period.bucket}&tz=$tz',
      cacheKey: 'dashboard_${period.name}',
    );
    return BusinessSummary.fromJson(period, json);
  }
}

final businessSummaryRepositoryProvider = Provider<BusinessSummaryRepository>(
  (ref) => BusinessSummaryRepository(ref.watch(authedApiProvider)),
);

/// The period the dashboard shows.
final dashboardPeriodProvider = StateProvider<DashboardPeriod>((ref) => DashboardPeriod.month);

/// The summary for [DashboardPeriod]; re-read when sales, purchases,
/// expenses or payments change (not when the sale and expense lists first
/// load, which would ask twice).
final businessSummaryProvider = FutureProvider.autoDispose.family<BusinessSummary?, DashboardPeriod>((ref, period) async {
  if (ref.watch(sessionUserIdProvider) == null) return null;
  void onChange<T>(AsyncValue<T>? previous, AsyncValue<T> next) {
    if (previous?.hasValue == true && next.hasValue && !identical(previous!.value, next.value)) ref.invalidateSelf();
  }

  ref.listen(salesProvider, onChange);
  ref.listen(expensesProvider, onChange);
  ref.watch(purchasesChangedProvider);
  ref.watch(debtsChangedProvider);
  final held = {
    for (final p in const ['sales.view', 'purchases.view', 'expenses.view', 'customers.view', 'suppliers.view', 'products.view'])
      p: ref.watch(holdsPermissionProvider(p)),
  };
  final summary = await ref.watch(businessSummaryRepositoryProvider).fetch(period);
  return summary.onlyWhat((p) => held[p] ?? false);
});
