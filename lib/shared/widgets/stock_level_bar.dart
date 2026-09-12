import 'package:flutter/material.dart';

/// Compact stock-level indicator: a number plus a small proportional bar,
/// so a low quantity is visible at a glance without reading every digit.
class StockLevelBar extends StatelessWidget {
  const StockLevelBar({
    super.key,
    required this.quantity,
    required this.referenceMax,
    required this.isLow,
  });

  final int quantity;

  /// The bar fills relative to this — typically a multiple of the reorder
  /// threshold, so "healthy" stock reads as a mostly-full bar rather than
  /// requiring the true theoretical maximum.
  final int referenceMax;
  final bool isLow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = referenceMax <= 0 ? 0.0 : (quantity / referenceMax).clamp(0.0, 1.0);
    final color = isLow ? theme.colorScheme.error : const Color(0xFF2F8F5B);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 46,
            height: 6,
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}
