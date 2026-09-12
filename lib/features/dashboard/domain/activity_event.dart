import 'package:flutter/material.dart' show IconData;

import '../../../shared/widgets/status_pill.dart';

enum ActivityKind { purchase, stockMovement }

/// A single row in the dashboard's "Recent activity" feed — a normalized
/// view over purchases and stock movements so they can be merged into one
/// chronological timeline. Built from the same MOCK module data as
/// everything else on the dashboard; see `dashboard_metrics.dart`.
class ActivityEvent {
  const ActivityEvent({
    required this.kind,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.icon,
    required this.tone,
  });

  final ActivityKind kind;
  final DateTime date;
  final String title;
  final String subtitle;
  final String amountLabel;
  final IconData icon;
  final StatusTone tone;
}
