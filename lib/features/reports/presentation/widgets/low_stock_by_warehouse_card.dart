import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/report_metrics.dart';
import 'report_card.dart';

/// Low-stock item counts per warehouse, as proportional bars — a lighter
/// alternative to another axis-based chart, for visual variety on the
/// same screen.
class LowStockByWarehouseCard extends ConsumerWidget {
  const LowStockByWarehouseCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final counts = ref.watch(lowStockByWarehouseProvider);
    final maxCount = counts.fold(1, (m, c) => c.count > m ? c.count : m);

    return ReportCard(
      title: 'Low-stock items by warehouse',
      subtitle: 'At or below reorder threshold, right now',
      height: 220,
      child: counts.isEmpty
          ? const Center(child: Text('No warehouses yet'))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final entry in counts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            entry.warehouseName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: entry.count / maxCount),
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) => LinearProgressIndicator(
                                value: value,
                                minHeight: 10,
                                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation(
                                  entry.count == 0
                                      ? const Color(0xFF2F8F5B)
                                      : theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 24,
                          child: Text('${entry.count}', style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
