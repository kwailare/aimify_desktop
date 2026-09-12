import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/product.dart';

/// MOCK repository — in-memory only, seeded with obviously-fake sample
/// data (`SAMPLE-...` SKUs). There is no `/api/v1/products` endpoint on
/// aimify-web yet, so nothing here survives an app restart. This class is
/// the single seam to replace with a real HTTP-backed repository later:
/// the screen only depends on [productsProvider]'s shape, not on how the
/// list is sourced.
///
/// Catalog only — no stock quantity here. On-hand stock is tracked per
/// warehouse; see `warehouse_stock_repository.dart`.
class ProductsNotifier extends Notifier<List<Product>> {
  @override
  List<Product> build() => const [
        Product(
          id: 'p1',
          sku: 'SAMPLE-SKU-001',
          barcode: '6009999000011',
          name: '50kg Bag of Rice',
          category: 'Grains',
          unitOfMeasure: 'Bag',
          purchasePrice: 32000,
          sellingPrice: 38500,
        ),
        Product(
          id: 'p2',
          sku: 'SAMPLE-SKU-002',
          barcode: '6009999000028',
          name: '25L Vegetable Oil',
          category: 'Cooking Oil',
          unitOfMeasure: 'Jerrican',
          purchasePrice: 21000,
          sellingPrice: 25500,
        ),
        Product(
          id: 'p3',
          sku: 'SAMPLE-SKU-003',
          barcode: '6009999000035',
          name: 'Carton of Bottled Water (24pk)',
          category: 'Beverages',
          unitOfMeasure: 'Carton',
          purchasePrice: 1800,
          sellingPrice: 2400,
        ),
        Product(
          id: 'p4',
          sku: 'SAMPLE-SKU-004',
          barcode: '6009999000042',
          name: '1kg Sugar Pack',
          category: 'Groceries',
          unitOfMeasure: 'Pack',
          purchasePrice: 1200,
          sellingPrice: 1550,
        ),
        Product(
          id: 'p5',
          sku: 'SAMPLE-SKU-005',
          barcode: '6009999000059',
          name: 'Carton of Detergent (12pk)',
          category: 'Household',
          unitOfMeasure: 'Carton',
          purchasePrice: 9500,
          sellingPrice: 12000,
        ),
      ];

  void addProduct(Product product) => state = [...state, product];

  void updateProduct(Product updated) =>
      state = [for (final p in state) if (p.id == updated.id) updated else p];

  void removeProduct(String id) => state = state.where((p) => p.id != id).toList();
}

final productsProvider = NotifierProvider<ProductsNotifier, List<Product>>(
  ProductsNotifier.new,
);
