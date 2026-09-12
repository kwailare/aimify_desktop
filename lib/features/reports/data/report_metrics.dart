import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/data/inventory_repository.dart';
import '../../inventory/data/warehouse_stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../../products/data/products_repository.dart';
import '../../purchases/data/purchases_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';

/// Chart-ready aggregates for the Reports screen. All derived from the
/// same MOCK module data as the rest of the app (products, warehouse
/// stock, inventory movements, purchases) — see each module's
/// `data/*_repository.dart` for the real-API swap-in seam.

class WarehouseValueSlice {
  const WarehouseValueSlice({required this.warehouseName, required this.value});
  final String warehouseName;
  final double value;
}

/// Inventory value (at purchase cost) per warehouse — org-wide regardless
/// of the admin's current warehouse filter, since the point of a report is
/// to compare locations against each other.
final inventoryValueByWarehouseProvider = Provider<List<WarehouseValueSlice>>((ref) {
  final warehouses = ref.watch(warehousesProvider);
  final products = {for (final p in ref.watch(productsProvider)) p.id: p};
  final stock = ref.watch(warehouseStockProvider);

  return [
    for (final warehouse in warehouses)
      WarehouseValueSlice(
        warehouseName: warehouse.name,
        value: stock
            .where((row) => row.warehouseId == warehouse.id)
            .fold(0.0, (sum, row) {
              final product = products[row.productId];
              if (product == null) return sum;
              return sum + row.quantity * product.purchasePrice;
            }),
      ),
  ];
});

class DailyMovementVolume {
  const DailyMovementVolume({required this.date, required this.stockIn, required this.stockOut});
  final DateTime date;
  final int stockIn;
  final int stockOut;
}

/// Stock-in vs stock-out quantity for each of the last 7 days, org-wide.
final movementVolumeLast7DaysProvider = Provider<List<DailyMovementVolume>>((ref) {
  final movements = ref.watch(inventoryProvider);
  final today = DateTime.now();

  return List.generate(7, (i) {
    final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i));
    final sameDay = movements.where((m) =>
        m.date.year == day.year && m.date.month == day.month && m.date.day == day.day);
    return DailyMovementVolume(
      date: day,
      stockIn: sameDay
          .where((m) => m.type == StockMovementType.stockIn)
          .fold(0, (sum, m) => sum + m.quantity),
      stockOut: sameDay
          .where((m) => m.type == StockMovementType.stockOut)
          .fold(0, (sum, m) => sum + m.quantity),
    );
  });
});

class WarehouseCount {
  const WarehouseCount({required this.warehouseName, required this.count});
  final String warehouseName;
  final int count;
}

/// Count of low-stock (product, warehouse) pairs per warehouse.
final lowStockByWarehouseProvider = Provider<List<WarehouseCount>>((ref) {
  final warehouses = ref.watch(warehousesProvider);
  final stock = ref.watch(warehouseStockProvider);

  return [
    for (final warehouse in warehouses)
      WarehouseCount(
        warehouseName: warehouse.name,
        count: stock.where((row) => row.warehouseId == warehouse.id && row.isLowStock).length,
      ),
  ];
});

/// Total purchase spend per warehouse (all-time, across the seeded
/// purchase orders).
final purchaseSpendByWarehouseProvider = Provider<List<WarehouseValueSlice>>((ref) {
  final warehouses = ref.watch(warehousesProvider);
  final purchases = ref.watch(purchasesProvider);

  return [
    for (final warehouse in warehouses)
      WarehouseValueSlice(
        warehouseName: warehouse.name,
        value: purchases
            .where((p) => p.warehouseId == warehouse.id)
            .fold(0.0, (sum, p) => sum + p.totalCost),
      ),
  ];
});
