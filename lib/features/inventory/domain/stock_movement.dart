enum StockMovementType { stockIn, stockOut, adjustment }

extension StockMovementTypeLabel on StockMovementType {
  String get label => switch (this) {
        StockMovementType.stockIn => 'Stock in',
        StockMovementType.stockOut => 'Stock out',
        StockMovementType.adjustment => 'Adjustment',
      };

  /// Signed multiplier applied to the entered quantity when updating a
  /// product's on-hand stock (adjustments carry their own sign already).
  int get signMultiplier => this == StockMovementType.stockOut ? -1 : 1;
}

/// A single stock-in / stock-out / adjustment entry. Placeholder domain
/// model — no `/api/v1/inventory` endpoint exists yet.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.warehouseId,
    required this.warehouseName,
    required this.type,
    required this.quantity,
    required this.reason,
    required this.date,
    required this.resultingStock,
  });

  final String id;
  final String productId;
  final String productName;
  final String warehouseId;
  final String warehouseName;
  final StockMovementType type;

  /// Always a positive count; [type] determines the direction it's applied.
  final int quantity;
  final String reason;
  final DateTime date;
  final int resultingStock;
}
