import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/staff_activity_repository.dart';
import '../data/staff_repository.dart';
import 'staff_activity_dialog.dart';
import 'staff_form_dialog.dart';

/// Admin-only staff directory. You (the real, subscribed aimify-web user)
/// are always the org's superuser — this screen is how you add staff and
/// assign each one to a warehouse. Tapping a row shows that staff member's
/// activity via [visibleActivities] — the same function that would scope a
/// real staff session down to just its own activity, once staff sign-in
/// exists (see `docs/desktop-api.md`).
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final staff = ref.watch(staffProvider);
    final warehouses = {for (final w in ref.watch(warehousesProvider)) w.id: w};
    final allActivity = ref.watch(staffActivityProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Staff',
              subtitle: '${staff.length} staff member(s) · tap a row to see their activity',
              badge: const MockDataBadge(),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const StaffFormDialog(),
                  ),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Add staff'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Staff sign-in isn't wired up yet — this manages who's assigned where and "
                    'what they can be expected to see, ready for once that exists.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Warehouse')),
                        DataColumn(label: Text('Activity'), numeric: true),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final member in staff)
                          DataRow(
                            onSelectChanged: (_) => showDialog(
                              context: context,
                              builder: (_) => StaffActivityDialog(staff: member),
                            ),
                            cells: [
                              DataCell(Text(member.name)),
                              DataCell(Text(member.email)),
                              DataCell(Text(warehouses[member.warehouseId]?.name ?? '—')),
                              DataCell(
                                Text(
                                  '${visibleActivities(allActivity, viewerStaffId: member.id).length}',
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: 'Remove staff',
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () =>
                                      ref.read(staffProvider.notifier).removeStaff(member.id),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
