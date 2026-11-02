import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/async_state.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../data/business_summary.dart';

const _salesColor = Color(0xFF2F8F5B);
const _profitColor = Color(0xFFC9800C);
const _purchasesColor = Color(0xFF3A6EA5);
const _expensesColor = Color(0xFFD1453B);

/// Short money for chart axes: 1.2M, 450k.
String _compact(double v) => NumberFormat.compact().format(v);

/// The business for a chosen period, against the one before: sales and
/// profit, purchases, expenses, what is owed both ways, and charts — the
/// sales trend, money in vs out, top sellers and customers, and debt and
/// warehouses. Only what the role may see is shown (the server leaves the
/// rest out).
class BusinessOverview extends ConsumerWidget {
  const BusinessOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final state = ref.watch(businessSummaryProvider(period));
    final summary = state.valueOrNull;

    // Roles that see no money figures get nothing here.
    // (An error can carry the empty value from before sign-in; show it.)
    if (!state.isLoading && !state.hasError && (summary == null || !summary.hasMoney)) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Business overview',
          subtitle: 'Sales, profit, spending and debts for the period',
          actions: [
            DropdownMenu<DashboardPeriod>(
              key: const Key('dashboard-period'),
              width: 170,
              initialSelection: period,
              leadingIcon: const Icon(Icons.date_range_outlined, size: 18),
              dropdownMenuEntries: [for (final p in DashboardPeriod.values) DropdownMenuEntry(value: p, label: p.label)],
              onSelected: (p) {
                if (p != null) ref.read(dashboardPeriodProvider.notifier).state = p;
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.isLoading && summary == null)
          const LoadingPanel(label: 'Working out the figures…')
        else if (state.hasError && summary == null)
          ErrorRetryCard(error: state.error!, onRetry: () => ref.invalidate(businessSummaryProvider(period)))
        else if (summary != null) ...[
          _Kpis(summary: summary),
          const SizedBox(height: 16),
          _ChartsGrid(summary: summary),
        ],
        const SizedBox(height: 28),
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.summary});

  final BusinessSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary.sales;
    final versus = summary.period.versus;
    final cards = <Widget>[
      if (s != null)
        _Kpi(
          key: const Key('kpi-sales'),
          label: 'Sales',
          value: s.total,
          caption: '${s.count} sale${s.count == 1 ? '' : 's'}',
          change: s.change,
          versus: versus,
          color: _salesColor,
          icon: Icons.point_of_sale_outlined,
        ),
      if (s != null)
        _Kpi(
          key: const Key('kpi-gross'),
          label: 'Gross profit',
          value: s.grossProfit,
          caption: s.margin == null ? 'Sales less what the goods cost' : '${s.margin!.toStringAsFixed(1)}% margin',
          change: s.grossProfitChange,
          versus: versus,
          color: _profitColor,
          icon: Icons.trending_up,
        ),
      if (summary.netProfit != null)
        _Kpi(
          key: const Key('kpi-net'),
          label: 'Net profit',
          value: summary.netProfit!,
          caption: 'Gross profit less expenses',
          change: summary.netProfitChange,
          versus: versus,
          color: summary.netProfit! < 0 ? theme.colorScheme.error : _profitColor,
          icon: Icons.account_balance_outlined,
        ),
      if (summary.expenses != null)
        _Kpi(
          key: const Key('kpi-expenses'),
          label: 'Expenses',
          value: summary.expenses!.total,
          caption: '${summary.expenses!.count} recorded',
          change: summary.expenses!.change,
          versus: versus,
          upIsBad: true,
          color: _expensesColor,
          icon: Icons.receipt_long_outlined,
        ),
      if (summary.purchases != null)
        _Kpi(
          key: const Key('kpi-purchases'),
          label: 'Purchases',
          value: summary.purchases!.total,
          caption: '${summary.purchases!.count} ordered',
          change: summary.purchases!.change,
          versus: versus,
          neutral: true,
          color: _purchasesColor,
          icon: Icons.shopping_cart_outlined,
        ),
      if (summary.receivables != null)
        _Kpi(
          key: const Key('kpi-receivables'),
          label: 'Customers owe you',
          value: summary.receivables!.owed,
          caption: summary.receivables!.overdue > 0
              ? '${currencyFormat.format(summary.receivables!.overdue)} overdue'
              : 'Nothing overdue',
          alert: summary.receivables!.overdue > 0,
          color: _salesColor,
          icon: Icons.call_received,
        ),
      if (summary.payables != null)
        _Kpi(
          key: const Key('kpi-payables'),
          label: 'You owe suppliers',
          value: summary.payables!.owed,
          caption: summary.payables!.overdue > 0
              ? '${currencyFormat.format(summary.payables!.overdue)} overdue'
              : 'Nothing overdue',
          alert: summary.payables!.overdue > 0,
          color: _purchasesColor,
          icon: Icons.call_made,
        ),
    ];
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: 138,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      children: cards,
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
    required this.icon,
    this.change,
    this.versus,
    this.upIsBad = false,
    this.neutral = false,
    this.alert = false,
  });

  final String label;
  final double value;
  final String caption;
  final Color color;
  final IconData icon;
  final double? change;
  final String? versus;
  final bool upIsBad;
  final bool neutral;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final c = change;
    final good = c == null ? null : (upIsBad ? c < 0 : c > 0);
    final changeColor = neutral || c == null || c == 0
        ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
        : (good! ? _salesColor : theme.colorScheme.error);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: muted?.copyWith(fontWeight: FontWeight.w700))),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                currencyFormat.format(value),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: value < 0 ? theme.colorScheme.error : theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: alert ? TextStyle(color: theme.colorScheme.error, fontSize: 12, fontWeight: FontWeight.w600) : muted,
            ),
            if (versus != null)
              Text(
                c == null ? 'Nothing $versus to compare' : '${c > 0 ? '▲' : (c < 0 ? '▼' : '')} ${c.abs().toStringAsFixed(1)}% $versus',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: changeColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChartsGrid extends StatelessWidget {
  const _ChartsGrid({required this.summary});

  final BusinessSummary summary;

  @override
  Widget build(BuildContext context) {
    final charts = <Widget>[
      if (summary.sales != null) _SalesTrendCard(summary: summary),
      if ([summary.sales, summary.purchases, summary.expenses].where((x) => x != null).length >= 2) _MoneyFlowCard(summary: summary),
      if (summary.sales != null) _TopSellersCard(sales: summary.sales!),
      if (summary.receivables != null || summary.payables != null || summary.stock != null) _DebtWarehousesCard(summary: summary),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [for (final c in charts) SizedBox(width: width, height: 330, child: c)],
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({super.key, required this.title, required this.subtitle, required this.child, this.legend = const []});

  final String title;
  final String subtitle;
  final Widget child;
  final List<(Color, String)> legend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            if (legend.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                children: [
                  for (final (color, label) in legend)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Every day (or month) of the period, filled with zeros where nothing
/// happened, so lines and bars line up.
List<DateTime> _buckets(BusinessSummary s) {
  final (from, to, _, _) = s.period.ranges(DateTime.now());
  final out = <DateTime>[];
  var d = from;
  final end = s.period == DashboardPeriod.lastMonth || s.period == DashboardPeriod.year ? to : DateTime.now();
  while (d.isBefore(end) || out.isEmpty) {
    out.add(d);
    d = s.bucket == 'month' ? DateTime(d.year, d.month + 1) : DateTime(d.year, d.month, d.day + 1);
    if (!d.isBefore(to)) break;
  }
  return out;
}

String _bucketLabel(BusinessSummary s, DateTime d) =>
    s.bucket == 'month' ? DateFormat('MMM').format(d) : DateFormat(s.period == DashboardPeriod.week ? 'EEE' : 'd MMM').format(d);

Widget _bottomTitles(BuildContext context, BusinessSummary s, List<DateTime> buckets, double value) {
  final i = value.toInt();
  if (i < 0 || i >= buckets.length || value != i.toDouble()) return const SizedBox.shrink();
  final step = (buckets.length / 7).ceil().clamp(1, 100);
  if (i % step != 0 && i != buckets.length - 1) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(_bucketLabel(s, buckets[i]), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10)),
  );
}

FlTitlesData _titles(BuildContext context, BusinessSummary s, List<DateTime> buckets) => FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (value, meta) => Text(
            _compact(value),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 9),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: 26,
          getTitlesWidget: (value, meta) => _bottomTitles(context, s, buckets, value),
        ),
      ),
    );

class _SalesTrendCard extends StatelessWidget {
  const _SalesTrendCard({required this.summary});

  final BusinessSummary summary;

  @override
  Widget build(BuildContext context) {
    final sales = summary.sales!;
    final buckets = _buckets(summary);
    final byBucket = {for (final t in sales.trend) t.bucket: t};
    final points = [for (final b in buckets) byBucket[b] ?? TrendPoint(b, 0, 0)];
    final maxY = points.fold(0.0, (m, p) => [m, p.value, p.second].reduce((a, b) => a > b ? a : b));
    return _ChartCard(
      key: const Key('chart-sales-trend'),
      title: 'Sales trend',
      subtitle: '${summary.period.label} · by ${summary.bucket}',
      legend: const [(_salesColor, 'Sales'), (_profitColor, 'Gross profit')],
      child: sales.count == 0
          ? const Center(child: Text('No sales in this period yet.'))
          : LineChart(
              LineChartData(
                minY: [0.0, ...points.map((p) => p.second)].reduce((a, b) => a < b ? a : b),
                maxY: maxY <= 0 ? 1 : maxY * 1.15,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: _titles(context, summary, buckets),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${_bucketLabel(summary, buckets[s.x.toInt()])}\n${currencyFormat.format(s.y)}',
                          TextStyle(color: s.bar.color, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  for (final (color, get) in [(_salesColor, (TrendPoint p) => p.value), (_profitColor, (TrendPoint p) => p.second)])
                    LineChartBarData(
                      spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), get(points[i]))],
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: color,
                      barWidth: 3,
                      dotData: FlDotData(show: points.length <= 14),
                      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
                    ),
                ],
              ),
            ),
    );
  }
}

class _MoneyFlowCard extends StatelessWidget {
  const _MoneyFlowCard({required this.summary});

  final BusinessSummary summary;

  @override
  Widget build(BuildContext context) {
    final buckets = _buckets(summary);
    Map<DateTime, double> index(List<TrendPoint>? t) => {for (final p in t ?? const <TrendPoint>[]) p.bucket: p.value};
    final series = [
      if (summary.sales != null) (_salesColor, 'Sales', index(summary.sales!.trend)),
      if (summary.purchases != null) (_purchasesColor, 'Purchases', index(summary.purchases!.trend)),
      if (summary.expenses != null) (_expensesColor, 'Expenses', index(summary.expenses!.trend)),
    ];
    final maxY = [
      for (final b in buckets)
        for (final (_, _, values) in series) values[b] ?? 0,
    ].fold(0.0, (m, v) => v > m ? v : m);
    final rodWidth = (buckets.length <= 7 ? 10.0 : (buckets.length <= 14 ? 6.0 : 3.0));
    return _ChartCard(
      key: const Key('chart-money-flow'),
      title: 'Money in vs out',
      subtitle: '${summary.period.label} · by ${summary.bucket}',
      legend: [for (final (color, label, _) in series) (color, label)],
      child: maxY == 0
          ? const Center(child: Text('Nothing recorded in this period yet.'))
          : BarChart(
              BarChartData(
                maxY: maxY * 1.15,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: _titles(context, summary, buckets),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                      '${series[ri].$2} ${_bucketLabel(summary, buckets[group.x])}\n${currencyFormat.format(rod.toY)}',
                      TextStyle(color: series[ri].$1, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < buckets.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 2,
                      barRods: [
                        for (final (color, _, values) in series)
                          BarChartRodData(toY: values[buckets[i]] ?? 0, color: color, width: rodWidth, borderRadius: BorderRadius.circular(2)),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}

class _TopSellersCard extends StatelessWidget {
  const _TopSellersCard({required this.sales});

  final SalesSummary sales;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final top = sales.topProducts.isEmpty ? 1.0 : sales.topProducts.first.revenue;
    return _ChartCard(
      key: const Key('chart-top-sellers'),
      title: 'Top sellers',
      subtitle: 'Products by sales, and the best customers',
      child: sales.count == 0
          ? const Center(child: Text('No sales in this period yet.'))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in sales.topProducts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text(currencyFormat.format(p.revenue)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          LinearProgressIndicator(
                            value: top <= 0 ? 0 : p.revenue / top,
                            color: _salesColor,
                            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                          ),
                          Text('${p.units} ${p.unit} · ${currencyFormat.format(p.grossProfit)} gross profit', style: muted),
                        ],
                      ),
                    ),
                  if (sales.topCustomers.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Top customers', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                    for (final c in sales.topCustomers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis)),
                            Text('${c.count} sale${c.count == 1 ? '' : 's'} · ', style: muted),
                            Text(currencyFormat.format(c.total)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _DebtWarehousesCard extends StatelessWidget {
  const _DebtWarehousesCard({required this.summary});

  final BusinessSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final debts = [
      if (summary.receivables != null) ('Customers owe you', summary.receivables!, _salesColor),
      if (summary.payables != null) ('You owe suppliers', summary.payables!, _purchasesColor),
    ];
    final biggest = debts.fold(1.0, (m, d) => d.$2.owed > m ? d.$2.owed : m);
    final salesBy = {for (final w in summary.sales?.byWarehouse ?? const []) w.warehouseId: w.total};
    final stockBy = summary.stock?.byWarehouse ?? const [];
    final warehouseIds = {...stockBy.map((w) => w.warehouseId), ...salesBy.keys};
    String nameOf(String? id) =>
        stockBy.where((w) => w.warehouseId == id).firstOrNull?.name ??
        summary.sales?.byWarehouse.where((w) => w.warehouseId == id).firstOrNull?.name ??
        'Warehouse';

    return _ChartCard(
      key: const Key('chart-debt-warehouses'),
      title: 'Debt & warehouses',
      subtitle: 'What is owed now, and each warehouse',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (label, d, color) in debts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(currencyFormat.format(d.owed)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 10,
                        child: Stack(
                          children: [
                            Container(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
                            FractionallySizedBox(widthFactor: (d.owed / biggest).clamp(0, 1), child: Container(color: color)),
                            FractionallySizedBox(
                              widthFactor: (d.overdue / biggest).clamp(0, 1),
                              child: Container(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      d.overdue > 0 ? '${currencyFormat.format(d.overdue)} overdue (red)' : 'Nothing overdue',
                      style: d.overdue > 0 ? TextStyle(color: theme.colorScheme.error, fontSize: 12) : muted,
                    ),
                  ],
                ),
              ),
            if (warehouseIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text('Warehouse', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800))),
                  if (summary.sales != null)
                    SizedBox(width: 110, child: Text('Sales', textAlign: TextAlign.end, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800))),
                  if (summary.stock != null)
                    SizedBox(width: 120, child: Text('Stock value', textAlign: TextAlign.end, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800))),
                ],
              ),
              for (final id in warehouseIds)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(nameOf(id), overflow: TextOverflow.ellipsis)),
                      if (summary.sales != null)
                        SizedBox(width: 110, child: Text(currencyFormat.format(salesBy[id] ?? 0), textAlign: TextAlign.end)),
                      if (summary.stock != null)
                        SizedBox(
                          width: 120,
                          child: Text(
                            currencyFormat.format(stockBy.where((w) => w.warehouseId == id).firstOrNull?.valueAtCost ?? 0),
                            textAlign: TextAlign.end,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
