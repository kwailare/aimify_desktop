import 'package:flutter/material.dart';

/// Small chip that must appear on every screen backed by fake/placeholder
/// data, so it's never ambiguous to a user (or to us, reading the code
/// later) which screens are wired to the real API and which aren't.
///
/// Per the project's ground rules: mock data should look obviously like
/// sample data, not something that could be mistaken for a working backend.
class MockDataBadge extends StatelessWidget {
  const MockDataBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message:
          'This screen shows sample data for UI preview.\n'
          'No backend exists yet for this module — see docs/desktop-api.md.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 13, color: scheme.error),
            const SizedBox(width: 5),
            Text(
              'Sample data',
              style: TextStyle(
                color: scheme.error,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
