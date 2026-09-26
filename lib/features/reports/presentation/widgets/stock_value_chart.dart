import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/formatters.dart';
import '../../data/report_metrics.dart';
import 'report_card.dart';

const _costColor = Color(0xFFD88B00);
const _retailColor = Color(0xFF6C63FF);

/// Stock value by category, at purchase cost next to selling price.
class StockValueChart extends ConsumerWidget {
  const StockValueChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final values = ref.watch(categoryValuesProvider).take(6).toList();

    if (values.isEmpty) {
      return const ReportCard(
        title: 'Stock value by category',
        subtitle: 'At purchase cost and at selling price',
        child: Center(child: Text('No stock on hand yet.')),
      );
    }

    final maxY = values.fold(1.0, (m, v) {
      final local = v.atCost > v.atRetail ? v.atCost : v.atRetail;
      return local > m ? local : m;
    });

    return ReportCard(
      title: 'Stock value by category',
      subtitle: 'At purchase cost and at selling price',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _LegendDot(color: _costColor, label: 'At cost'),
              _LegendDot(color: _retailColor, label: 'At selling price'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: maxY * 1.2,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                      currencyFormat.format(rod.toY),
                      TextStyle(color: rod.color, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= values.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            values[index].category,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < values.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: values[i].atCost,
                          color: _costColor,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: values[i].atRetail,
                          color: _retailColor,
                          width: 14,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
