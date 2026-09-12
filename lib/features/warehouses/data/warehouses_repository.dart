import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/warehouse.dart';

/// MOCK repository — in-memory only. No `/api/v1/warehouses` endpoint yet.
/// Referential-integrity checks (don't remove a warehouse that still has
/// staff or stock assigned to it) live in `warehouses_screen.dart`, which
/// can see the staff/inventory providers — this repository stays
/// single-purpose.
class WarehousesNotifier extends Notifier<List<Warehouse>> {
  @override
  List<Warehouse> build() => const [
        Warehouse(id: 'w1', name: 'Lagos Main Warehouse', location: 'Ikeja, Lagos'),
        Warehouse(id: 'w2', name: 'Abuja Depot', location: 'Garki, Abuja'),
      ];

  void addWarehouse(Warehouse warehouse) => state = [...state, warehouse];

  /// Removing a warehouse that's currently selected in
  /// [selectedWarehouseIdProvider] used to crash: every `WarehouseSelector`
  /// stays mounted (branches inside a `StatefulShellRoute.indexedStack`
  /// are never disposed, just hidden), and a `DropdownButton` throws if
  /// its `value` no longer matches any of its `items` — which is exactly
  /// what happens the instant the selected warehouse disappears from
  /// [state] on every one of those still-mounted dropdowns at once.
  void removeWarehouse(String id) {
    state = state.where((w) => w.id != id).toList();
    if (ref.read(selectedWarehouseIdProvider) == id) {
      ref.read(selectedWarehouseIdProvider.notifier).state = null;
    }
  }
}

final warehousesProvider = NotifierProvider<WarehousesNotifier, List<Warehouse>>(
  WarehousesNotifier.new,
);

/// The warehouse an admin has chosen to focus every scoped screen
/// (Products/Inventory/Suppliers/Purchases/Reports) on — `null` means "all
/// warehouses." This is also the mechanism a future staff session would
/// use, just locked to that staff member's one assigned warehouse instead
/// of being freely switchable — see `docs/desktop-api.md` notes on staff
/// login being out of scope for now.
final selectedWarehouseIdProvider = StateProvider<String?>((ref) => null);
