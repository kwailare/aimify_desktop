import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/staff.dart';

/// MOCK repository — in-memory only. No staff/user-management endpoint
/// exists on aimify-web yet; this whole module is admin-side UI over local
/// state, per the "skip staff login for now" scope decision.
class StaffNotifier extends Notifier<List<Staff>> {
  @override
  List<Staff> build() => const [
        Staff(id: 'st1', name: 'Musa Danladi', email: 'musa@sample.aimify.local', warehouseId: 'w1'),
        Staff(id: 'st2', name: 'Amaka Eze', email: 'amaka@sample.aimify.local', warehouseId: 'w2'),
      ];

  void addStaff(Staff staff) => state = [...state, staff];

  void removeStaff(String id) => state = state.where((s) => s.id != id).toList();
}

final staffProvider = NotifierProvider<StaffNotifier, List<Staff>>(StaffNotifier.new);
