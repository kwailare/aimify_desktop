import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/report_metrics.dart';
import 'report_card.dart';

const _stockInColor = Color(0xFF2F8F5B);
const _stockOutColor = Color(0xFFD1453B);

/// Stock-in vs stock-out quantity over the last 7 days, as two lines.
class MovementTrendChart extends ConsumerWidget {
  const MovementTrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final days = ref.watch(movementVolumeLast7DaysProvider);
    final dayLabel = DateFormat('E');

    final maxY = days.fold(1.0, (m, d) {
      final localMax = d.stockIn > d.stockOut ? d.stockIn : d.stockOut;
      return localMax > m ? localMax.toDouble() : m;
    });

    return ReportCard(
      title: 'Stock movement, last 7 days',
      subtitle: 'Units moved in vs out, across every warehouse',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LegendDot(color: _stockInColor, label: 'Stock in'),
              const SizedBox(width: 16),
              _LegendDot(color: _stockOutColor, label: 'Stock out'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.25,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= days.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            dayLabel.format(days[index].date),
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), days[i].stockIn.toDouble()),
                    ],
                    isCurved: true,
                    color: _stockInColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: _stockInColor.withValues(alpha: 0.08)),
                  ),
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < days.length; i++) FlSpot(i.toDouble(), days[i].stockOut.toDouble()),
                    ],
                    isCurved: true,
                    color: _stockOutColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: _stockOutColor.withValues(alpha: 0.08)),
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
