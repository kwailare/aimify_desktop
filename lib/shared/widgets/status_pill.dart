import 'package:flutter/material.dart';

enum StatusTone { positive, warning, negative, neutral }

/// Small rounded label for statuses like payment/stock/subscription state
/// ("Paid", "Low stock", "Overdue", "Trial").
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color color = switch (tone) {
      StatusTone.positive => const Color(0xFF2F8F5B),
      StatusTone.warning => scheme.secondary,
      StatusTone.negative => scheme.error,
      StatusTone.neutral => scheme.onSurface.withValues(alpha: 0.55),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
