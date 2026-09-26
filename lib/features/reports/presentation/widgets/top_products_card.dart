import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/formatters.dart';
import '../../data/report_metrics.dart';
import 'report_card.dart';

/// The products tying up the most money on the shelves, at purchase cost.
class TopProductsCard extends ConsumerWidget {
  const TopProductsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final products = ref.watch(topProductsByValueProvider);

    if (products.isEmpty) {
      return const ReportCard(
        title: 'Most valuable stock',
        subtitle: 'Top products by value on hand, at purchase cost',
        child: Center(child: Text('No stock on hand yet.')),
      );
    }

    final top = products.first.stockValueAtCost;

    return ReportCard(
      title: 'Most valuable stock',
      subtitle: 'Top products by value on hand, at purchase cost',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final p in products)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${currencyFormat.format(p.stockValueAtCost)} · ${p.currentStock} ${p.unit}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: top <= 0 ? 0 : p.stockValueAtCost / top,
                      minHeight: 7,
                      backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
