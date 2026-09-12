import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/data/warehouse_stock_repository.dart';
import '../../inventory/domain/warehouse_stock.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../domain/product.dart';
import 'products_repository.dart';

/// A catalog [product] joined with its stock for the current
/// [selectedWarehouseIdProvider] scope — either one warehouse's exact
/// on-hand quantity, or, in "all warehouses" mode, the total across every
/// warehouse that actually stocks it.
class ProductWithStock {
  const ProductWithStock({
    required this.product,
    required this.totalQuantity,
    required this.referenceThreshold,
    required this.isLowSomewhere,
    required this.stockedWarehouseCount,
  });

  final Product product;
  final int totalQuantity;

  /// Reorder threshold to compare [totalQuantity] against for display (a
  /// progress bar, say) — the selected warehouse's own threshold, or the
  /// sum of every warehouse's threshold in "all warehouses" mode, matching
  /// how [totalQuantity] itself is summed.
  final int referenceThreshold;

  /// True if low relative to threshold in the selected warehouse, or (in
  /// "all warehouses" mode) low in at least one warehouse that stocks it.
  final bool isLowSomewhere;

  /// How many warehouses actually carry this product — 0 means it exists
  /// in the catalog but isn't stocked anywhere yet.
  final int stockedWarehouseCount;
}

/// Products scoped to [selectedWarehouseIdProvider]. When a specific
/// warehouse is selected, products not stocked there are left out
/// entirely — the concrete expression of warehouses being independent
/// rather than sharing one stock number under different labels.
final scopedProductsProvider = Provider<List<ProductWithStock>>((ref) {
  final products = ref.watch(productsProvider);
  final allStock = ref.watch(warehouseStockProvider);
  final warehouseId = ref.watch(selectedWarehouseIdProvider);

  final result = <ProductWithStock>[];
  for (final product in products) {
    final rows = allStock.where((row) => row.productId == product.id);

    if (warehouseId == null) {
      final relevant = rows.toList();
      if (relevant.isEmpty) continue;
      result.add(
        ProductWithStock(
          product: product,
          totalQuantity: relevant.fold(0, (sum, r) => sum + r.quantity),
          referenceThreshold: relevant.fold(0, (sum, r) => sum + r.lowStockThreshold),
          isLowSomewhere: relevant.any((r) => r.isLowStock),
          stockedWarehouseCount: relevant.length,
        ),
      );
    } else {
      WarehouseStock? row;
      for (final r in rows) {
        if (r.warehouseId == warehouseId) {
          row = r;
          break;
        }
      }
      if (row == null) continue;
      result.add(
        ProductWithStock(
          product: product,
          totalQuantity: row.quantity,
          referenceThreshold: row.lowStockThreshold,
          isLowSomewhere: row.isLowStock,
          stockedWarehouseCount: 1,
        ),
      );
    }
  }
  return result;
});
