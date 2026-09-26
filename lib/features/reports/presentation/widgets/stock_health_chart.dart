import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/report_metrics.dart';
import 'report_card.dart';

const _healthyColor = Color(0xFF2F8F5B);
const _lowColor = Color(0xFFF2B233);
const _outColor = Color(0xFFD1453B);

/// How many products are healthy, low, or out of stock.
class StockHealthChart extends ConsumerWidget {
  const StockHealthChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final health = ref.watch(stockHealthProvider);

    if (health.total == 0) {
      return const ReportCard(
        title: 'Stock health',
        subtitle: 'Products by stock status',
        child: Center(child: Text('No products yet.')),
      );
    }

    Widget legend(Color color, String label, int count) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Text('$count', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        );

    return ReportCard(
      title: 'Stock health',
      subtitle: 'Products by stock status',
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 46,
                sections: [
                  if (health.healthy > 0)
                    PieChartSectionData(
                      value: health.healthy.toDouble(),
                      color: _healthyColor,
                      radius: 26,
                      showTitle: false,
                    ),
                  if (health.low > 0)
                    PieChartSectionData(
                      value: health.low.toDouble(),
                      color: _lowColor,
                      radius: 26,
                      showTitle: false,
                    ),
                  if (health.out > 0)
                    PieChartSectionData(
                      value: health.out.toDouble(),
                      color: _outColor,
                      radius: 26,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 170,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${health.total}',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text('products', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                legend(_healthyColor, 'In stock', health.healthy),
                legend(_lowColor, 'Low stock', health.low),
                legend(_outColor, 'Out of stock', health.out),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
