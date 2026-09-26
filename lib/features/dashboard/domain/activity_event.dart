import 'package:flutter/material.dart' show IconData;

import '../../../shared/widgets/status_pill.dart';

/// A single row in the dashboard's "Recent activity" feed — a stock
/// movement from the real ledger, prepared for display.
class ActivityEvent {
  const ActivityEvent({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.icon,
    required this.tone,
  });

  final DateTime date;
  final String title;
  final String subtitle;
  final String amountLabel;
  final IconData icon;
  final StatusTone tone;
}
