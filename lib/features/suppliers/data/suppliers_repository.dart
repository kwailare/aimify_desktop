import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../warehouses/data/warehouses_repository.dart';
import '../domain/supplier.dart';

/// MOCK repository — in-memory only. No `/api/v1/suppliers` endpoint yet.
class SuppliersNotifier extends Notifier<List<Supplier>> {
  @override
  List<Supplier> build() => const [
        Supplier(
          id: 's1',
          name: 'SAMPLE Golden Grains Distributors',
          contactPerson: 'Musa Ibrahim',
          phone: '+234 802 555 0101',
          productsSupplied: ['50kg Bag of Rice', '1kg Sugar Pack'],
          balanceOwed: 145000,
          warehouseId: 'w1',
        ),
        Supplier(
          id: 's2',
          name: 'SAMPLE Coastal Oils Ltd',
          contactPerson: 'Ifeoma Chukwu',
          phone: '+234 803 555 0102',
          productsSupplied: ['25L Vegetable Oil'],
          balanceOwed: 0,
          warehouseId: 'w1',
        ),
        Supplier(
          id: 's3',
          name: 'SAMPLE PureSpring Beverages',
          contactPerson: 'Tunde Bakare',
          phone: '+234 805 555 0103',
          productsSupplied: ['Carton of Bottled Water (24pk)'],
          balanceOwed: 32000,
          warehouseId: 'w1',
        ),
        Supplier(
          id: 's4',
          name: 'SAMPLE Northern Foods Supply Co.',
          contactPerson: 'Aisha Bello',
          phone: '+234 806 555 0104',
          productsSupplied: ['1kg Sugar Pack', 'Carton of Detergent (12pk)'],
          balanceOwed: 58000,
          warehouseId: 'w2',
        ),
      ];

  void addSupplier(Supplier supplier) => state = [...state, supplier];

  /// Records a payment made to a supplier — used by the Credits & Debts
  /// screen. Clamped so it can't go negative.
  void recordPayment(String supplierId, double amount) {
    state = [
      for (final supplier in state)
        if (supplier.id == supplierId)
          supplier.copyWith(balanceOwed: (supplier.balanceOwed - amount).clamp(0, double.infinity))
        else
          supplier,
    ];
  }
}

final suppliersProvider = NotifierProvider<SuppliersNotifier, List<Supplier>>(
  SuppliersNotifier.new,
);

/// Suppliers scoped to [selectedWarehouseIdProvider] — the mechanism a
/// future staff session would use, locked to their one warehouse.
final scopedSuppliersProvider = Provider<List<Supplier>>((ref) {
  final warehouseId = ref.watch(selectedWarehouseIdProvider);
  final suppliers = ref.watch(suppliersProvider);
  if (warehouseId == null) return suppliers;
  return suppliers.where((s) => s.warehouseId == warehouseId).toList();
});
