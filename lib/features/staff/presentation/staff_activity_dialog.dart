import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../data/staff_activity_repository.dart';
import '../domain/staff.dart';
import '../domain/staff_activity.dart';

/// Admin's view into one staff member's activity — calls
/// [visibleActivities] with that staff member's id, the exact same
/// function a real staff session would call with its own id to see only
/// its own activity.
class StaffActivityDialog extends ConsumerWidget {
  const StaffActivityDialog({super.key, required this.staff});

  final Staff staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activities = visibleActivities(
      ref.watch(staffActivityProvider),
      viewerStaffId: staff.id,
    )..sort((a, b) => b.date.compareTo(a.date));

    return AlertDialog(
      title: Text('${staff.name}\'s activity'),
      content: SizedBox(
        width: 420,
        child: activities.isEmpty
            ? const Text('No activity recorded yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final activity in activities)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activity.kind.label,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  activity.detail,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            dateFormat.format(activity.date),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
