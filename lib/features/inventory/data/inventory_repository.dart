import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/stock_movement.dart';
import 'warehouse_stock_repository.dart';

/// MOCK repository — in-memory stock movement log. No `/api/v1/inventory`
/// endpoint exists yet. Recording a movement here also nudges the matching
/// `WarehouseStock` row via [WarehouseStockNotifier.adjustStock], purely so
/// the two mock modules stay visually consistent with each other.
class InventoryNotifier extends Notifier<List<StockMovement>> {
  @override
  List<StockMovement> build() {
    final now = DateTime.now();
    return [
      StockMovement(
        id: 'm1',
        productId: 'p1',
        productName: '50kg Bag of Rice',
        warehouseId: 'w1',
        warehouseName: 'Lagos Main Warehouse',
        type: StockMovementType.stockIn,
        quantity: 20,
        reason: 'Purchase delivery — SAMPLE-PO-1001',
        date: now.subtract(const Duration(days: 4)),
        resultingStock: 42,
      ),
      StockMovement(
        id: 'm2',
        productId: 'p2',
        productName: '25L Vegetable Oil',
        warehouseId: 'w1',
        warehouseName: 'Lagos Main Warehouse',
        type: StockMovementType.stockOut,
        quantity: 12,
        reason: 'Dispatched to retail partner',
        date: now.subtract(const Duration(days: 2)),
        resultingStock: 8,
      ),
      StockMovement(
        id: 'm3',
        productId: 'p4',
        productName: '1kg Sugar Pack',
        warehouseId: 'w1',
        warehouseName: 'Lagos Main Warehouse',
        type: StockMovementType.adjustment,
        quantity: 3,
        reason: 'Damaged stock write-off',
        date: now.subtract(const Duration(hours: 20)),
        resultingStock: 5,
      ),
      StockMovement(
        id: 'm4',
        productId: 'p1',
        productName: '50kg Bag of Rice',
        warehouseId: 'w2',
        warehouseName: 'Abuja Depot',
        type: StockMovementType.stockOut,
        quantity: 15,
        reason: 'Dispatched to retail partner',
        date: now.subtract(const Duration(days: 1)),
        resultingStock: 10,
      ),
    ];
  }

  void addMovement({
    required String productId,
    required String productName,
    required String warehouseId,
    required String warehouseName,
    required StockMovementType type,
    required int quantity,
    required String reason,
  }) {
    final stockNotifier = ref.read(warehouseStockProvider.notifier);
    final delta = quantity * type.signMultiplier;
    stockNotifier.adjustStock(productId, warehouseId, delta);

    final updatedStock = stockNotifier.stockOf(productId, warehouseId);

    state = [
      StockMovement(
        id: 'm${DateTime.now().microsecondsSinceEpoch}',
        productId: productId,
        productName: productName,
        warehouseId: warehouseId,
        warehouseName: warehouseName,
        type: type,
        quantity: quantity,
        reason: reason,
        date: DateTime.now(),
        resultingStock: updatedStock?.quantity ?? 0,
      ),
      ...state,
    ];
  }
}

final inventoryProvider = NotifierProvider<InventoryNotifier, List<StockMovement>>(
  InventoryNotifier.new,
);
