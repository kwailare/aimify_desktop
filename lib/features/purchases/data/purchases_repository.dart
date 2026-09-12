import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../warehouses/data/warehouses_repository.dart';
import '../domain/purchase.dart';

/// MOCK repository — in-memory only. No `/api/v1/purchases` endpoint yet.
class PurchasesNotifier extends Notifier<List<Purchase>> {
  @override
  List<Purchase> build() {
    final now = DateTime.now();
    return [
      Purchase(
        id: 'SAMPLE-PO-1001',
        supplierName: 'SAMPLE Golden Grains Distributors',
        warehouseId: 'w1',
        warehouseName: 'Lagos Main Warehouse',
        date: now.subtract(const Duration(days: 4)),
        items: const [
          PurchaseLineItem(productName: '50kg Bag of Rice', quantity: 20, unitCost: 32000),
        ],
        paymentStatus: PaymentStatus.paid,
        amountPaid: 640000,
      ),
      Purchase(
        id: 'SAMPLE-PO-1002',
        supplierName: 'SAMPLE Coastal Oils Ltd',
        warehouseId: 'w1',
        warehouseName: 'Lagos Main Warehouse',
        date: now.subtract(const Duration(days: 2)),
        items: const [
          PurchaseLineItem(productName: '25L Vegetable Oil', quantity: 15, unitCost: 21000),
        ],
        paymentStatus: PaymentStatus.partial,
        amountPaid: 200000,
      ),
      Purchase(
        id: 'SAMPLE-PO-1003',
        supplierName: 'SAMPLE Northern Foods Supply Co.',
        warehouseId: 'w2',
        warehouseName: 'Abuja Depot',
        date: now.subtract(const Duration(days: 1)),
        items: const [
          PurchaseLineItem(productName: '1kg Sugar Pack', quantity: 40, unitCost: 1200),
        ],
        paymentStatus: PaymentStatus.unpaid,
        amountPaid: 0,
      ),
    ];
  }

  void addPurchase(Purchase purchase) => state = [purchase, ...state];
}

final purchasesProvider = NotifierProvider<PurchasesNotifier, List<Purchase>>(
  PurchasesNotifier.new,
);

/// Purchases scoped to [selectedWarehouseIdProvider].
final scopedPurchasesProvider = Provider<List<Purchase>>((ref) {
  final warehouseId = ref.watch(selectedWarehouseIdProvider);
  final purchases = ref.watch(purchasesProvider);
  if (warehouseId == null) return purchases;
  return purchases.where((p) => p.warehouseId == warehouseId).toList();
});
