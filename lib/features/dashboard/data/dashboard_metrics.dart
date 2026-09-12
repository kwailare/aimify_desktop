import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../customers/data/customers_repository.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/data/warehouse_stock_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../../products/data/products_repository.dart';
import '../../purchases/data/purchases_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../domain/activity_event.dart';

/// Org-wide derived analytics for the dashboard — deliberately not scoped
/// to [selectedWarehouseIdProvider] the way module screens are, since an
/// overview is supposed to show everything at once. Every one of these
/// reads from a MOCK module repository (products/purchases/inventory/
/// customers/warehouses) — none of it is real until those modules have
/// actual backend endpoints. See each module's `data/*_repository.dart`
/// for the seam to swap in real data later.

final inventoryValueProvider = Provider<double>((ref) {
  final products = {for (final p in ref.watch(productsProvider)) p.id: p};
  final stock = ref.watch(warehouseStockProvider);
  return stock.fold(0.0, (sum, row) {
    final product = products[row.productId];
    if (product == null) return sum;
    return sum + row.quantity * product.purchasePrice;
  });
});

/// Inventory value broken down by category, largest first — powers the
/// featured card's mini composition bars.
final inventoryValueByCategoryProvider = Provider<List<MapEntry<String, double>>>((ref) {
  final products = ref.watch(productsProvider);
  final stock = ref.watch(warehouseStockProvider);
  final quantityByProduct = <String, int>{};
  for (final row in stock) {
    quantityByProduct.update(row.productId, (v) => v + row.quantity, ifAbsent: () => row.quantity);
  }

  final totals = <String, double>{};
  for (final product in products) {
    final quantity = quantityByProduct[product.id] ?? 0;
    if (quantity == 0) continue;
    totals.update(
      product.category,
      (value) => value + quantity * product.purchasePrice,
      ifAbsent: () => quantity * product.purchasePrice,
    );
  }
  final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return entries;
});

final lowStockCountProvider = Provider<int>((ref) {
  return ref.watch(warehouseStockProvider).where((row) => row.isLowStock).length;
});

final outstandingDebtProvider = Provider<double>((ref) {
  final customers = ref.watch(customersProvider);
  return customers.fold(0.0, (sum, c) => sum + c.balanceOwed);
});

/// How many independent stock locations the org is running — a stand-in
/// for the "today's sales" tile now that this app is inventory-only.
final warehouseCountProvider = Provider<int>((ref) => ref.watch(warehousesProvider).length);

/// Total units moved (in + out + adjustment) across every warehouse today.
final todaysMovementCountProvider = Provider<int>((ref) {
  final now = DateTime.now();
  return ref.watch(inventoryProvider).where((m) {
    return m.date.year == now.year && m.date.month == now.month && m.date.day == now.day;
  }).length;
});

/// Merges purchases and stock movements into one chronological feed for
/// the dashboard's "Recent activity" card, newest first.
final activityFeedProvider = Provider<List<ActivityEvent>>((ref) {
  final purchases = ref.watch(purchasesProvider);
  final movements = ref.watch(inventoryProvider);

  final events = <ActivityEvent>[
    for (final purchase in purchases)
      ActivityEvent(
        kind: ActivityKind.purchase,
        date: purchase.date,
        title: 'Purchase from ${purchase.supplierName}',
        subtitle: '${purchase.id} · ${purchase.warehouseName}',
        amountLabel: currencyFormat.format(purchase.totalCost),
        icon: Icons.shopping_cart_outlined,
        tone: StatusTone.neutral,
      ),
    for (final movement in movements)
      ActivityEvent(
        kind: ActivityKind.stockMovement,
        date: movement.date,
        title: '${movement.type.label} · ${movement.productName}',
        subtitle: '${movement.warehouseName} · ${movement.reason}',
        amountLabel: '${movement.type == StockMovementType.stockOut ? '-' : '+'}${movement.quantity}',
        icon: switch (movement.type) {
          StockMovementType.stockIn => Icons.arrow_downward_rounded,
          StockMovementType.stockOut => Icons.arrow_upward_rounded,
          StockMovementType.adjustment => Icons.tune_rounded,
        },
        tone: movement.type == StockMovementType.stockOut
            ? StatusTone.warning
            : StatusTone.neutral,
      ),
  ]..sort((a, b) => b.date.compareTo(a.date));

  return events.take(8).toList();
});
