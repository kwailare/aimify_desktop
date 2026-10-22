/// Purchases exactly as `/api/v1/purchases` returns them. See "Purchases" in
/// `docs/desktop-api.md`.
enum PurchaseStatus { draft, pending, partiallyReceived, received, cancelled }

extension PurchaseStatusX on PurchaseStatus {
  String get apiValue => switch (this) {
    PurchaseStatus.draft => 'draft',
    PurchaseStatus.pending => 'pending',
    PurchaseStatus.partiallyReceived => 'partially_received',
    PurchaseStatus.received => 'received',
    PurchaseStatus.cancelled => 'cancelled',
  };

  String get label => switch (this) {
    PurchaseStatus.draft => 'Draft',
    PurchaseStatus.pending => 'Ordered',
    PurchaseStatus.partiallyReceived => 'Partly received',
    PurchaseStatus.received => 'Received',
    PurchaseStatus.cancelled => 'Cancelled',
  };

  /// Still waiting for goods (draft, ordered or partly received).
  bool get isOpen =>
      this == PurchaseStatus.draft ||
      this == PurchaseStatus.pending ||
      this == PurchaseStatus.partiallyReceived;

  bool get canReceive => isOpen;

  static PurchaseStatus fromApi(String value) => switch (value) {
    'pending' => PurchaseStatus.pending,
    'partially_received' => PurchaseStatus.partiallyReceived,
    'received' => PurchaseStatus.received,
    'cancelled' => PurchaseStatus.cancelled,
    _ => PurchaseStatus.draft,
  };
}

class PurchaseLine {
  const PurchaseLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.receivedQuantity,
  });

  final String id;
  final String productId;
  final String productName;
  final String sku;
  final String unit;
  final int quantity;
  final double unitCost;
  final int receivedQuantity;

  int get outstanding => quantity - receivedQuantity;
  double get lineTotal => quantity * unitCost;

  factory PurchaseLine.fromJson(Map<String, dynamic> json) => PurchaseLine(
    id: json['id'] as String,
    productId: json['productId'] as String,
    productName: json['productName'] as String? ?? 'Product',
    sku: json['sku'] as String? ?? '',
    unit: json['unit'] as String? ?? 'piece',
    quantity: (json['quantity'] as num).toInt(),
    unitCost: (json['unitCost'] as num).toDouble(),
    receivedQuantity: (json['receivedQuantity'] as num?)?.toInt() ?? 0,
  );
}

class PurchaseReceipt {
  const PurchaseReceipt({
    required this.id,
    required this.createdAt,
    this.userName,
    required this.lines,
  });

  final String id;
  final DateTime createdAt;
  final String? userName;
  final List<({String productId, int quantity})> lines;

  factory PurchaseReceipt.fromJson(Map<String, dynamic> json) => PurchaseReceipt(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    userName: json['userName'] as String?,
    lines: [
      for (final row in (json['lines'] as List<dynamic>? ?? const []))
        (
          productId: (row as Map<String, dynamic>)['productId'] as String,
          quantity: (row['quantity'] as num).toInt(),
        ),
    ],
  );
}

class PurchasePayment {
  const PurchasePayment({
    required this.id,
    required this.amount,
    this.note,
    required this.createdAt,
    this.userName,
  });

  final String id;
  final double amount;
  final String? note;
  final DateTime createdAt;
  final String? userName;

  factory PurchasePayment.fromJson(Map<String, dynamic> json) => PurchasePayment(
    id: json['id'] as String,
    amount: (json['amount'] as num).toDouble(),
    note: json['note'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    userName: json['userName'] as String?,
  );
}

class Purchase {
  const Purchase({
    required this.id,
    required this.reference,
    required this.supplierId,
    required this.supplierName,
    required this.warehouseId,
    required this.warehouseName,
    required this.status,
    required this.orderDate,
    this.expectedDate,
    this.notes,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.amountPaid,
    this.postedAt,
    this.createdByName,
    required this.lines,
    this.receipts = const [],
    this.payments = const [],
  });

  final String id;
  final String reference;
  final String supplierId;
  final String supplierName;
  final String warehouseId;
  final String warehouseName;
  final PurchaseStatus status;
  final DateTime orderDate;
  final DateTime? expectedDate;
  final String? notes;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double amountPaid;

  /// When it reached the supplier's account (its first receipt).
  final DateTime? postedAt;
  final String? createdByName;
  final List<PurchaseLine> lines;

  /// Only filled by `GET /purchases/{id}`.
  final List<PurchaseReceipt> receipts;
  final List<PurchasePayment> payments;

  double get balance => total - amountPaid;
  bool get isPaid => amountPaid >= total && total > 0;
  int get unitsOrdered => lines.fold(0, (sum, l) => sum + l.quantity);
  int get unitsReceived => lines.fold(0, (sum, l) => sum + l.receivedQuantity);

  /// Lines and prices can change only while nothing has been received.
  bool get canEdit =>
      (status == PurchaseStatus.draft || status == PurchaseStatus.pending) && postedAt == null;
  bool get canCancel => canEdit;

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
    id: json['id'] as String,
    reference: json['reference'] as String,
    supplierId: json['supplierId'] as String,
    supplierName: json['supplierName'] as String? ?? 'Supplier',
    warehouseId: json['warehouseId'] as String,
    warehouseName: json['warehouseName'] as String? ?? 'Warehouse',
    status: PurchaseStatusX.fromApi(json['status'] as String? ?? 'draft'),
    orderDate: DateTime.parse(json['orderDate'] as String),
    expectedDate: json['expectedDate'] == null
        ? null
        : DateTime.tryParse(json['expectedDate'] as String),
    notes: json['notes'] as String?,
    subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
    discount: (json['discount'] as num?)?.toDouble() ?? 0,
    tax: (json['tax'] as num?)?.toDouble() ?? 0,
    total: (json['total'] as num?)?.toDouble() ?? 0,
    amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0,
    postedAt: json['postedAt'] == null ? null : DateTime.tryParse(json['postedAt'] as String),
    createdByName: json['createdByName'] as String?,
    lines: [
      for (final row in (json['lines'] as List<dynamic>? ?? const []))
        PurchaseLine.fromJson(row as Map<String, dynamic>),
    ],
    receipts: [
      for (final row in (json['receipts'] as List<dynamic>? ?? const []))
        PurchaseReceipt.fromJson(row as Map<String, dynamic>),
    ],
    payments: [
      for (final row in (json['payments'] as List<dynamic>? ?? const []))
        PurchasePayment.fromJson(row as Map<String, dynamic>),
    ],
  );
}

/// One line as entered in the form (and queued offline).
class PurchaseLineInput {
  const PurchaseLineInput({
    required this.productId,
    required this.quantity,
    required this.unitCost,
  });

  final String productId;
  final int quantity;
  final double unitCost;

  double get lineTotal => quantity * unitCost;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
    'unitCost': unitCost,
  };

  factory PurchaseLineInput.fromJson(Map<String, dynamic> json) => PurchaseLineInput(
    productId: json['productId'] as String,
    quantity: (json['quantity'] as num).toInt(),
    unitCost: (json['unitCost'] as num).toDouble(),
  );

  PurchaseLineInput withProductId(String id) =>
      PurchaseLineInput(productId: id, quantity: quantity, unitCost: unitCost);
}

/// What the form sends to create a purchase (or, without [amountPaid] and
/// [receive], to edit one).
class PurchaseInput {
  const PurchaseInput({
    required this.supplierId,
    required this.warehouseId,
    required this.lines,
    this.placeOrder = false,
    required this.orderDate,
    this.expectedDate,
    this.notes,
    this.discount = 0,
    this.tax = 0,
    this.amountPaid = 0,
    this.receive = false,
  });

  final String supplierId;
  final String warehouseId;
  final List<PurchaseLineInput> lines;

  /// `pending` (ordered) instead of `draft`.
  final bool placeOrder;
  final DateTime orderDate;
  final DateTime? expectedDate;
  final String? notes;
  final double discount;
  final double tax;
  final double amountPaid;

  /// Receive everything straight away (bought and collected on the spot).
  final bool receive;

  double get subtotal => lines.fold(0.0, (sum, l) => sum + l.lineTotal);
  double get total => subtotal - discount + tax;

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Fields shared by create and edit.
  Map<String, dynamic> toEditJson() => {
    'supplierId': supplierId,
    'warehouseId': warehouseId,
    'lines': [for (final l in lines) l.toJson()],
    'status': placeOrder ? 'pending' : 'draft',
    'orderDate': _date(orderDate),
    'expectedDate': expectedDate == null ? null : _date(expectedDate!),
    'notes': notes,
    'discount': discount,
    'tax': tax,
  };

  Map<String, dynamic> toJson() => {...toEditJson(), 'amountPaid': amountPaid, 'receive': receive};

  factory PurchaseInput.fromJson(Map<String, dynamic> json) => PurchaseInput(
    supplierId: json['supplierId'] as String,
    warehouseId: json['warehouseId'] as String,
    lines: [
      for (final row in (json['lines'] as List<dynamic>))
        PurchaseLineInput.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
    placeOrder: json['status'] == 'pending',
    orderDate: DateTime.parse(json['orderDate'] as String),
    expectedDate: json['expectedDate'] == null
        ? null
        : DateTime.parse(json['expectedDate'] as String),
    notes: json['notes'] as String?,
    discount: (json['discount'] as num?)?.toDouble() ?? 0,
    tax: (json['tax'] as num?)?.toDouble() ?? 0,
    amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0,
    receive: json['receive'] as bool? ?? false,
  );

  /// The same purchase pointing at server ids once records created offline
  /// have synced.
  PurchaseInput resolved(String Function(String id) resolve) => PurchaseInput(
    supplierId: resolve(supplierId),
    warehouseId: warehouseId,
    lines: [for (final l in lines) l.withProductId(resolve(l.productId))],
    placeOrder: placeOrder,
    orderDate: orderDate,
    expectedDate: expectedDate,
    notes: notes,
    discount: discount,
    tax: tax,
    amountPaid: amountPaid,
    receive: receive,
  );
}
