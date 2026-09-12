/// On-hand quantity of one product at one warehouse — the join that makes
/// warehouses independent of each other. The same product can be well
/// stocked in one warehouse and critically low in another; this record is
/// what actually varies per location, not the catalog entry itself.
class WarehouseStock {
  const WarehouseStock({
    required this.productId,
    required this.warehouseId,
    required this.quantity,
    required this.lowStockThreshold,
  });

  final String productId;
  final String warehouseId;
  final int quantity;
  final int lowStockThreshold;

  bool get isLowStock => quantity <= lowStockThreshold;

  WarehouseStock copyWith({int? quantity, int? lowStockThreshold}) => WarehouseStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: quantity ?? this.quantity,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      );
}
