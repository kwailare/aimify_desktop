import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../parties/data/supplier_options.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';

/// A product at or below its reorder level, with how many to buy: up to its
/// maximum stock when it has one, otherwise back to twice the reorder level.
class ReorderLine {
  const ReorderLine({required this.product, required this.suggested});

  final Product product;
  final int suggested;
}

/// The products to reorder from one supplier ([supplierId] null: products
/// without a usual supplier).
class ReorderGroup {
  const ReorderGroup({required this.supplierId, required this.supplierName, required this.lines});

  final String? supplierId;
  final String supplierName;
  final List<ReorderLine> lines;
}

int suggestedReorder(Product p) {
  final target = p.maxStock != null && p.maxStock! > p.minStock ? p.maxStock! : p.minStock * 2;
  final needed = target - p.currentStock;
  return needed > 0 ? needed : 1;
}

/// Groups [products] that need reordering by their usual supplier: suppliers
/// by name, products by how far below their level they are; products with
/// no supplier last.
List<ReorderGroup> reorderGroups(List<Product> products, List<SupplierOption> suppliers) {
  final names = {for (final s in suppliers) s.id: s.name};
  final due = products.where((p) => !p.isArchived && p.minStock > 0 && p.currentStock <= p.minStock);
  final bySupplier = <String?, List<ReorderLine>>{};
  for (final p in due) {
    final key = p.supplierId != null && names.containsKey(p.supplierId) ? p.supplierId : null;
    bySupplier.putIfAbsent(key, () => []).add(ReorderLine(product: p, suggested: suggestedReorder(p)));
  }
  final groups = [
    for (final entry in bySupplier.entries)
      ReorderGroup(
        supplierId: entry.key,
        supplierName: entry.key == null ? 'No usual supplier' : names[entry.key]!,
        lines: entry.value
          ..sort((a, b) => (a.product.currentStock - a.product.minStock).compareTo(b.product.currentStock - b.product.minStock)),
      ),
  ];
  groups.sort((a, b) {
    if (a.supplierId == null) return 1;
    if (b.supplierId == null) return -1;
    return a.supplierName.toLowerCase().compareTo(b.supplierName.toLowerCase());
  });
  return groups;
}

final reorderGroupsProvider = Provider<List<ReorderGroup>>((ref) {
  final products = ref.watch(productListProvider);
  final suppliers = ref.watch(supplierOptionsProvider).valueOrNull ?? const <SupplierOption>[];
  return reorderGroups(products, suppliers);
});
