import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/data/inventory_repository.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';

/// Chart-ready aggregates for the Reports screen, computed from the live
/// products and stock ledger. There is no reporting or valuation endpoint
/// on the backend yet, so valuation is current stock × price, calculated
/// here — and the trend covers only the latest 100 movements the ledger
/// endpoint returns.

class CategoryValue {
  const CategoryValue({required this.category, required this.atCost, required this.atRetail});

  final String category;
  final double atCost;
  final double atRetail;
}

/// Stock value per category (at cost and at selling price), largest first.
final categoryValuesProvider = Provider<List<CategoryValue>>((ref) {
  final cost = <String, double>{};
  final retail = <String, double>{};
  for (final p in ref.watch(productListProvider)) {
    final key = p.category ?? 'Uncategorised';
    cost.update(key, (v) => v + p.stockValueAtCost, ifAbsent: () => p.stockValueAtCost);
    retail.update(key, (v) => v + p.stockValueAtRetail, ifAbsent: () => p.stockValueAtRetail);
  }
  return [
    for (final key in cost.keys)
      if (cost[key]! > 0 || retail[key]! > 0)
        CategoryValue(category: key, atCost: cost[key]!, atRetail: retail[key]!),
  ]..sort((a, b) => b.atCost.compareTo(a.atCost));
});

class DailyMovementVolume {
  const DailyMovementVolume({required this.date, required this.stockIn, required this.stockOut});

  final DateTime date;
  final int stockIn;
  final int stockOut;
}

/// Units added and removed for each of the last 14 days.
final movementVolumeProvider = Provider<List<DailyMovementVolume>>((ref) {
  final movements = ref.watch(movementListProvider);
  final today = DateTime.now();

  return List.generate(14, (i) {
    final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: 13 - i));
    final sameDay = movements.where((m) =>
        m.createdAt.year == day.year && m.createdAt.month == day.month && m.createdAt.day == day.day);
    return DailyMovementVolume(
      date: day,
      stockIn: sameDay.where((m) => m.quantity > 0).fold(0, (sum, m) => sum + m.quantity),
      stockOut: sameDay.where((m) => m.quantity < 0).fold(0, (sum, m) => sum - m.quantity),
    );
  });
});

class StockHealth {
  const StockHealth({required this.healthy, required this.low, required this.out});

  final int healthy;
  final int low;
  final int out;

  int get total => healthy + low + out;
}

final stockHealthProvider = Provider<StockHealth>((ref) {
  final products = ref.watch(productListProvider);
  return StockHealth(
    healthy: products.where((p) => !p.isLowStock && !p.isOutOfStock).length,
    low: products.where((p) => p.isLowStock).length,
    out: products.where((p) => p.isOutOfStock).length,
  );
});

/// The products holding the most money, at purchase cost.
final topProductsByValueProvider = Provider<List<Product>>((ref) {
  final products = [...ref.watch(productListProvider).where((p) => p.stockValueAtCost > 0)]
    ..sort((a, b) => b.stockValueAtCost.compareTo(a.stockValueAtCost));
  return products.take(6).toList();
});
