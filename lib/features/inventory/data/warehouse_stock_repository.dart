import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/warehouse_stock.dart';

/// MOCK repository — in-memory only. No `/api/v1/warehouse-stock` endpoint
/// exists (there's no inventory backend at all yet). This is the seam that
/// makes warehouses genuinely independent: a product with no row here for
/// a given warehouse simply isn't stocked there.
///
/// Seeded on purpose so the same product is low in one warehouse and fine
/// in another (rice, oil, sugar), and so two products each exist in only
/// one of the two seed warehouses (water only in Lagos, detergent only in
/// Abuja) — a concrete demonstration of per-warehouse independence rather
/// than a single shared stock number re-labeled per location.
class WarehouseStockNotifier extends Notifier<List<WarehouseStock>> {
  @override
  List<WarehouseStock> build() => const [
        WarehouseStock(productId: 'p1', warehouseId: 'w1', quantity: 42, lowStockThreshold: 15),
        WarehouseStock(productId: 'p1', warehouseId: 'w2', quantity: 10, lowStockThreshold: 15),
        WarehouseStock(productId: 'p2', warehouseId: 'w1', quantity: 8, lowStockThreshold: 10),
        WarehouseStock(productId: 'p2', warehouseId: 'w2', quantity: 30, lowStockThreshold: 10),
        WarehouseStock(productId: 'p3', warehouseId: 'w1', quantity: 130, lowStockThreshold: 30),
        WarehouseStock(productId: 'p4', warehouseId: 'w1', quantity: 5, lowStockThreshold: 20),
        WarehouseStock(productId: 'p4', warehouseId: 'w2', quantity: 40, lowStockThreshold: 20),
        WarehouseStock(productId: 'p5', warehouseId: 'w2', quantity: 24, lowStockThreshold: 8),
      ];

  WarehouseStock? stockOf(String productId, String warehouseId) {
    for (final row in state) {
      if (row.productId == productId && row.warehouseId == warehouseId) return row;
    }
    return null;
  }

  /// Creates the stock row if a product is being stocked into a warehouse
  /// for the first time, otherwise replaces the existing row.
  void setStock(WarehouseStock stock) {
    final exists = stockOf(stock.productId, stock.warehouseId) != null;
    state = [
      for (final row in state)
        if (row.productId == stock.productId && row.warehouseId == stock.warehouseId) stock else row,
      if (!exists) stock,
    ];
  }

  /// Applies a stock-in (+) / stock-out (-) / adjustment (+/-) delta,
  /// clamped at zero. Creates a row (starting from 0) if this product
  /// wasn't previously stocked at this warehouse.
  void adjustStock(String productId, String warehouseId, int delta) {
    final current = stockOf(productId, warehouseId);
    final newQuantity = ((current?.quantity ?? 0) + delta).clamp(0, 1 << 31);
    setStock(
      WarehouseStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: newQuantity,
        lowStockThreshold: current?.lowStockThreshold ?? 5,
      ),
    );
  }

  void removeWarehouse(String warehouseId) =>
      state = state.where((row) => row.warehouseId != warehouseId).toList();

  /// Cleans up stock rows left behind when a product is deleted from the
  /// catalog — called alongside `ProductsNotifier.removeProduct` so a
  /// removed product doesn't leave orphaned rows here.
  void removeProduct(String productId) =>
      state = state.where((row) => row.productId != productId).toList();
}

final warehouseStockProvider = NotifierProvider<WarehouseStockNotifier, List<WarehouseStock>>(
  WarehouseStockNotifier.new,
);
