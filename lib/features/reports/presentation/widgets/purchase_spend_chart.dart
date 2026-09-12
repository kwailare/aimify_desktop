import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/formatters.dart';
import '../../data/report_metrics.dart';
import 'report_card.dart';

/// Total purchase spend per warehouse, all-time across seed data.
class PurchaseSpendChart extends ConsumerWidget {
  const PurchaseSpendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber = isDark ? const Color(0xFFFFC95C) : const Color(0xFFF2B233);
    final slices = ref.watch(purchaseSpendByWarehouseProvider);
    final maxValue = slices.fold(0.0, (m, s) => s.value > m ? s.value : m);

    return ReportCard(
      title: 'Purchase spend by warehouse',
      subtitle: 'Total cost of purchase orders on file',
      child: slices.isEmpty
          ? const Center(child: Text('No warehouses yet'))
          : BarChart(
              BarChartData(
                maxY: maxValue == 0 ? 10 : maxValue * 1.2,
                barGroups: [
                  for (var i = 0; i < slices.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: slices[i].value,
                          color: amber,
                          width: 34,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ],
                    ),
                ],
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      getTitlesWidget: (value, meta) => Text(
                        currencyFormat.format(value),
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= slices.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            slices[index].warehouseName,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
