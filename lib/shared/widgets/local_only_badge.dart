import 'package:flutter/material.dart';

/// Marks a screen that has no backend yet.
///
/// Customers, suppliers, purchases, expenses and credit tracking don't have
/// endpoints in aimify-web (see "Things that are still not on the backend"
/// in `docs/desktop-api.md`). Those screens keep working on this computer
/// only — saved here and restored on the next launch, but never sent
/// anywhere or shared with the team — and this badge says so on every one
/// of them, so it is never ambiguous which screens are real.
class LocalOnlyBadge extends StatelessWidget {
  const LocalOnlyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message:
          'This module has no online backend yet.\n'
          'What you enter here is saved on this computer only. It is not '
          'sent to Aimify and not shared with your team.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.secondary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.secondary.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.laptop_outlined, size: 13, color: scheme.secondary),
            const SizedBox(width: 5),
            Text(
              'Local only',
              style: TextStyle(
                color: scheme.secondary,
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
