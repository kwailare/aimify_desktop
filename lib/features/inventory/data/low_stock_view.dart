import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../../warehouses/domain/warehouse.dart';
import 'warehouse_stock_repository.dart';
import '../domain/warehouse_stock.dart';

/// One (product, warehouse) pair that's at or below its reorder threshold.
class LowStockEntry {
  const LowStockEntry({required this.product, required this.warehouse, required this.stock});

  final Product product;
  final Warehouse warehouse;
  final WarehouseStock stock;
}

List<LowStockEntry> _joinLowStock(Ref ref) {
  final products = {for (final p in ref.watch(productsProvider)) p.id: p};
  final warehouses = {for (final w in ref.watch(warehousesProvider)) w.id: w};

  final result = <LowStockEntry>[];
  for (final row in ref.watch(warehouseStockProvider)) {
    if (!row.isLowStock) continue;
    final product = products[row.productId];
    final warehouse = warehouses[row.warehouseId];
    if (product == null || warehouse == null) continue;
    result.add(LowStockEntry(product: product, warehouse: warehouse, stock: row));
  }
  return result;
}

/// Used by the Inventory screen's alert banner — scoped to
/// [selectedWarehouseIdProvider], the same way that whole screen is.
final scopedLowStockProvider = Provider<List<LowStockEntry>>((ref) {
  final warehouseId = ref.watch(selectedWarehouseIdProvider);
  final all = _joinLowStock(ref);
  if (warehouseId == null) return all;
  return all.where((e) => e.warehouse.id == warehouseId).toList();
});

/// Used by the dashboard's watchlist — deliberately NOT scoped to
/// [selectedWarehouseIdProvider], since the dashboard is meant to show
/// everything at once regardless of whatever filter another screen left
/// selected.
final orgWideLowStockProvider = Provider<List<LowStockEntry>>(_joinLowStock);
