import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/formatters.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/dashboard_metrics.dart';
import 'animated_counter_text.dart';

/// Asymmetric "bento" layout for the dashboard's headline numbers: one
/// large featured tile (inventory value, broken down by category) beside
/// three smaller metric tiles — a deliberately less generic shape than a
/// uniform grid of identical cards.
class MetricBentoGrid extends ConsumerWidget {
  const MetricBentoGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final plan = ref.watch(authControllerProvider).valueOrNull?.plan;
    final warehouseLimit = plan?.limits.warehouses;

    final smallCards = [
      _SmallMetricCard(
        label: 'Active warehouses',
        value: ref.watch(activeWarehouseCountProvider).toDouble(),
        format: (v) => v.round().toString(),
        caption: warehouseLimit == null
            ? 'Unlimited on your plan'
            : '$warehouseLimit allowed on your plan',
        icon: Icons.warehouse_outlined,
        accent: const Color(0xFF2F8F5B),
      ),
      _SmallMetricCard(
        label: 'Low-stock items',
        value: ref.watch(lowStockCountProvider).toDouble(),
        format: (v) => v.round().toString(),
        caption: 'At or below their reorder level',
        icon: Icons.warning_amber_outlined,
        accent: const Color(0xFFD88B00),
      ),
      _SmallMetricCard(
        label: 'Out of stock',
        value: ref.watch(outOfStockCountProvider).toDouble(),
        format: (v) => v.round().toString(),
        caption: 'Nothing left on hand',
        icon: Icons.remove_shopping_cart_outlined,
        accent: theme.colorScheme.error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;

        final featured = _FeaturedInventoryCard(value: ref.watch(inventoryValueProvider));

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              featured,
              const SizedBox(height: 16),
              for (final card in smallCards) ...[
                card,
                const SizedBox(height: 16),
              ],
            ]..removeLast(),
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: featured),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    for (final card in smallCards) ...[
                      Expanded(child: card),
                      if (card != smallCards.last) const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

const _categoryPalette = [
  Color(0xFFD88B00),
  Color(0xFFF2B233),
  Color(0xFF6C63FF),
  Color(0xFF2F8F5B),
  Color(0xFFD1453B),
  Color(0xFF4B4B4B),
];

class _FeaturedInventoryCard extends ConsumerWidget {
  const _FeaturedInventoryCard({required this.value});

  final double value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final byCategory = ref.watch(inventoryValueByCategoryProvider);
    final total = value == 0 ? 1 : value;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF241C0E), const Color(0xFF1E1E1E)]
              : [const Color(0xFFFFF3DA), Colors.white],
        ),
        border: Border.all(
          color: (isDark ? const Color(0xFFF2B233) : const Color(0xFFD88B00))
              .withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Inventory value',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AnimatedCounterText(
            value: value,
            format: (v) => currencyFormat.format(v),
            style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            'At purchase cost · ${currencyFormat.format(ref.watch(retailValueProvider))} at selling price',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          if (byCategory.isEmpty)
            Text(
              'No stock recorded yet — record a stock in to see your inventory value here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            )
          else
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (var i = 0; i < byCategory.length; i++)
                    Expanded(
                      flex: (byCategory[i].value / total * 1000).round().clamp(1, 1000),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 500 + i * 120),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Container(
                            color: _categoryPalette[i % _categoryPalette.length],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (var i = 0; i < byCategory.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _categoryPalette[i % _categoryPalette.length],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${byCategory[i].key} · ${(byCategory[i].value / total * 100).round()}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallMetricCard extends StatefulWidget {
  const _SmallMetricCard({
    required this.label,
    required this.value,
    required this.format,
    required this.caption,
    required this.icon,
    required this.accent,
  });

  final String label;
  final double value;
  final String Function(double) format;
  final String caption;
  final IconData icon;
  final Color accent;

  @override
  State<_SmallMetricCard> createState() => _SmallMetricCardState();
}

class _SmallMetricCardState extends State<_SmallMetricCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovering ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border(left: BorderSide(color: widget.accent, width: 4)),
          boxShadow: [
            BoxShadow(
              color: (_hovering ? widget.accent : Colors.black)
                  .withValues(alpha: _hovering ? 0.18 : 0.05),
              blurRadius: _hovering ? 20 : 8,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 16, color: widget.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedCounterText(
                value: widget.value,
                format: widget.format,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
