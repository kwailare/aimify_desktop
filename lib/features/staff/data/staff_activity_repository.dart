import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/staff_activity.dart';

/// MOCK repository — in-memory only. Seeded so each staff member has a
/// plausible activity trail to demonstrate the permission model below.
class StaffActivityNotifier extends Notifier<List<StaffActivity>> {
  @override
  List<StaffActivity> build() {
    final now = DateTime.now();
    return [
      StaffActivity(
        id: 'sa1',
        staffId: 'st1',
        kind: StaffActivityKind.stockOut,
        detail: 'Dispatched 12x 25L Vegetable Oil from Lagos Main Warehouse',
        date: now.subtract(const Duration(hours: 3)),
      ),
      StaffActivity(
        id: 'sa2',
        staffId: 'st1',
        kind: StaffActivityKind.viewedSuppliers,
        detail: 'Opened the Suppliers page',
        date: now.subtract(const Duration(hours: 5)),
      ),
      StaffActivity(
        id: 'sa3',
        staffId: 'st2',
        kind: StaffActivityKind.stockOut,
        detail: 'Dispatched 15x 50kg Bag of Rice from Abuja Depot',
        date: now.subtract(const Duration(days: 1)),
      ),
      StaffActivity(
        id: 'sa4',
        staffId: 'st2',
        kind: StaffActivityKind.viewedProducts,
        detail: 'Opened the Products page',
        date: now.subtract(const Duration(days: 1, hours: 2)),
      ),
    ];
  }
}

final staffActivityProvider = NotifierProvider<StaffActivityNotifier, List<StaffActivity>>(
  StaffActivityNotifier.new,
);

/// The actual permission rule: an admin (`viewerStaffId == null`) sees
/// every staff member's activity; a staff session would only ever see its
/// own. This function is real and unit-testable even though there's no
/// staff-facing UI calling it with a non-null id yet — see
/// `docs/desktop-api.md` on why staff sign-in itself is out of scope.
List<StaffActivity> visibleActivities(
  List<StaffActivity> all, {
  required String? viewerStaffId,
}) {
  if (viewerStaffId == null) return all;
  return all.where((activity) => activity.staffId == viewerStaffId).toList();
}
