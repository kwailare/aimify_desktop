import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../inventory/data/inventory_repository.dart';
import '../../../products/domain/product.dart';

/// Out-of-stock products first, then low-stock ones, straight from
/// `GET /api/v1/alerts/stock`.
class LowStockWatchlistCard extends ConsumerWidget {
  const LowStockWatchlistCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final alerts = ref.watch(stockAlertListProvider);
    final rows = [
      ...alerts.outOfStock,
      ...([...alerts.lowStock]
        ..sort((a, b) => (a.currentStock / a.minStock).compareTo(b.currentStock / b.minStock))),
    ];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stock alerts',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Reorder before these run out',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nothing is low or out of stock right now.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              _WatchlistRow(product: rows[i], index: i),
              if (i != rows.length - 1) const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({required this.product, required this.index});

  final Product product;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = product.minStock <= 0
        ? 0.0
        : (product.currentStock / product.minStock).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              product.isOutOfStock
                  ? 'Out of stock'
                  : '${product.currentStock} / ${product.minStock}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: product.isOutOfStock
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: product.isOutOfStock ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: Duration(milliseconds: 500 + index * 100),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(
                ratio < 0.34 ? theme.colorScheme.error : const Color(0xFFF2B233),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
