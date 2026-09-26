import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/status_pill.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../../products/data/products_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../domain/activity_event.dart';

/// Everything on the dashboard is derived from the real products,
/// warehouses, alerts and stock ledger the other screens already load — no
/// separate endpoint, no sample data. Inventory valuation is calculated
/// here (current stock × price) because the API has no valuation endpoint.

/// Current stock valued at what it cost to buy.
final inventoryValueProvider = Provider<double>((ref) {
  return ref.watch(productListProvider).fold(0.0, (sum, p) => sum + p.stockValueAtCost);
});

/// Current stock valued at selling price.
final retailValueProvider = Provider<double>((ref) {
  return ref.watch(productListProvider).fold(0.0, (sum, p) => sum + p.stockValueAtRetail);
});

final unitsOnHandProvider = Provider<int>((ref) {
  return ref.watch(productListProvider).fold(0, (sum, p) => sum + p.currentStock);
});

/// Stock value at cost by category, largest first — powers the featured
/// card's composition bar.
final inventoryValueByCategoryProvider = Provider<List<MapEntry<String, double>>>((ref) {
  final totals = <String, double>{};
  for (final product in ref.watch(productListProvider)) {
    final value = product.stockValueAtCost;
    if (value <= 0) continue;
    totals.update(
      product.category ?? 'Uncategorised',
      (existing) => existing + value,
      ifAbsent: () => value,
    );
  }
  return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
});

final lowStockCountProvider = Provider<int>(
  (ref) => ref.watch(stockAlertListProvider).lowStock.length,
);

final outOfStockCountProvider = Provider<int>(
  (ref) => ref.watch(stockAlertListProvider).outOfStock.length,
);

final activeWarehouseCountProvider = Provider<int>(
  (ref) => ref.watch(activeWarehousesProvider).length,
);

/// The latest stock movements as a feed, newest first.
final activityFeedProvider = Provider<List<ActivityEvent>>((ref) {
  final movements = ref.watch(movementListProvider);
  final names = {for (final p in ref.watch(productListProvider)) p.id: p.name};

  final events = [
    for (final m in movements)
      ActivityEvent(
        date: m.createdAt,
        title: '${m.type.label} · ${names[m.productId] ?? 'Archived product'}',
        subtitle: m.reason == null || m.reason!.isEmpty
            ? '${m.previousStock} → ${m.newStock} on hand'
            : '${m.reason} · ${m.previousStock} → ${m.newStock}',
        amountLabel: '${m.quantity > 0 ? '+' : ''}${m.quantity}',
        icon: switch (m.type) {
          StockMovementType.stockIn => Icons.arrow_downward_rounded,
          StockMovementType.stockOut => Icons.arrow_upward_rounded,
          StockMovementType.adjustment => Icons.tune_rounded,
          StockMovementType.count => Icons.fact_check_outlined,
        },
        tone: m.quantity < 0 ? StatusTone.warning : StatusTone.neutral,
      ),
  ]..sort((a, b) => b.date.compareTo(a.date));

  return events.take(8).toList();
});
