/// The four movement types `POST /api/v1/inventory/movements` accepts.
///
/// - [stockIn]: goods received.
/// - [stockOut]: goods leaving (needs `stock.out`; the only type Sales
///   Staff can record).
/// - [adjustment]: a correction up or down (damage, write-off, found stock).
/// - [count]: a physical stock count — the person enters what they counted
///   and the app records the difference from the system figure.
enum StockMovementType { stockIn, stockOut, adjustment, count }

extension StockMovementTypeX on StockMovementType {
  String get label => switch (this) {
        StockMovementType.stockIn => 'Stock in',
        StockMovementType.stockOut => 'Stock out',
        StockMovementType.adjustment => 'Adjustment',
        StockMovementType.count => 'Stock count',
      };

  /// The value the API uses for `type`.
  String get apiValue => switch (this) {
        StockMovementType.stockIn => 'stock_in',
        StockMovementType.stockOut => 'stock_out',
        StockMovementType.adjustment => 'adjustment',
        StockMovementType.count => 'count',
      };

  static StockMovementType fromApi(String value) => switch (value) {
        'stock_in' => StockMovementType.stockIn,
        'stock_out' => StockMovementType.stockOut,
        'count' => StockMovementType.count,
        _ => StockMovementType.adjustment,
      };
}

/// The signed whole-number change to send to the server for what a person
/// typed. The API applies `quantity` as a delta (`stock = stock + quantity`),
/// so "stock out 30" must go as -30, a decreasing adjustment as a negative,
/// and a count as the difference between what was counted and what the
/// system shows.
int signedMovementDelta({
  required StockMovementType type,
  required int entered,
  required int currentStock,
  bool adjustDown = false,
}) =>
    switch (type) {
      StockMovementType.stockIn => entered,
      StockMovementType.stockOut => -entered,
      StockMovementType.adjustment => adjustDown ? -entered : entered,
      StockMovementType.count => entered - currentStock,
    };

/// One row of the stock ledger, as `GET /api/v1/inventory/movements`
/// returns it. [quantity] is the signed change that was applied (negative
/// removes stock); [previousStock] and [newStock] bracket it.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.warehouseId,
    this.userId,
    required this.type,
    required this.quantity,
    this.reason,
    required this.previousStock,
    required this.newStock,
    required this.createdAt,
    this.isPending = false,
  });

  final String id;
  final String productId;
  final String warehouseId;

  /// Who recorded it. The API only exposes the id, so the ledger can say
  /// "You" for your own entries and "Team member" for everyone else.
  final String? userId;
  final StockMovementType type;
  final int quantity;
  final String? reason;
  final int previousStock;
  final int newStock;
  final DateTime createdAt;

  /// True for a movement recorded offline that hasn't reached the server
  /// yet; [previousStock]/[newStock] are then this computer's best estimate.
  final bool isPending;

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        productId: json['productId'] as String,
        warehouseId: json['warehouseId'] as String,
        userId: json['userId'] as String?,
        type: StockMovementTypeX.fromApi(json['type'] as String? ?? ''),
        quantity: (json['quantity'] as num).toInt(),
        reason: json['reason'] as String?,
        previousStock: (json['previousStock'] as num?)?.toInt() ?? 0,
        newStock: (json['newStock'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

/// What recording a movement returns: the ledger row, the product's new
/// stock, and — only when this movement crossed a threshold — an alert.
class MovementResult {
  const MovementResult({required this.movement, required this.currentStock, this.alert});

  final StockMovement movement;
  final int currentStock;

  /// `low_stock`, `out_of_stock`, or `null`.
  final String? alert;

  factory MovementResult.fromJson(Map<String, dynamic> json) => MovementResult(
        movement: StockMovement.fromJson(json['movement'] as Map<String, dynamic>),
        currentStock: (json['currentStock'] as num?)?.toInt() ?? 0,
        alert: json['alert'] as String?,
      );
}
