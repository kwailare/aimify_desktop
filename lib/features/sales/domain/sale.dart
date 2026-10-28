/// Sales exactly as `/api/v1/sales` returns them. See "Sales" in
/// `docs/desktop-api.md`.
enum SaleStatus { completed, voided }

enum SalePaymentMethod { cash, transfer, pos, card, cheque, other }

extension SalePaymentMethodX on SalePaymentMethod {
  String get apiValue => name;

  String get label => switch (this) {
        SalePaymentMethod.cash => 'Cash',
        SalePaymentMethod.transfer => 'Bank transfer',
        SalePaymentMethod.pos => 'POS',
        SalePaymentMethod.card => 'Card',
        SalePaymentMethod.cheque => 'Cheque',
        SalePaymentMethod.other => 'Other',
      };

  static SalePaymentMethod fromApi(String? value) =>
      SalePaymentMethod.values.where((m) => m.name == value).firstOrNull ?? SalePaymentMethod.cash;
}

class SaleLine {
  const SaleLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.listPrice,
  });

  final String id;
  final String productId;
  final String productName;
  final String sku;
  final String unit;
  final int quantity;
  final double unitPrice;

  /// The product's selling price when it was sold.
  final double listPrice;

  double get lineTotal => quantity * unitPrice;
  bool get discounted => unitPrice < listPrice - 0.004;

  factory SaleLine.fromJson(Map<String, dynamic> json) => SaleLine(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName: json['productName'] as String? ?? 'Product',
        sku: json['sku'] as String? ?? '',
        unit: json['unit'] as String? ?? 'piece',
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        listPrice: (json['listPrice'] as num?)?.toDouble() ?? (json['unitPrice'] as num).toDouble(),
      );
}

class SalePayment {
  const SalePayment({
    required this.id,
    required this.amount,
    required this.method,
    this.note,
    required this.createdAt,
    this.userName,
    this.receiptNumber,
  });

  final String id;
  final double amount;
  final SalePaymentMethod method;
  final String? note;
  final DateTime createdAt;
  final String? userName;

  /// Set when it came from a payment on the customer's account.
  final String? receiptNumber;

  factory SalePayment.fromJson(Map<String, dynamic> json) => SalePayment(
        id: json['id'] as String,
        amount: (json['amount'] as num).toDouble(),
        method: SalePaymentMethodX.fromApi(json['method'] as String?),
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        userName: json['userName'] as String?,
        receiptNumber: json['receiptNumber'] as String?,
      );
}

class Sale {
  const Sale({
    required this.id,
    required this.reference,
    this.customerId,
    required this.customerName,
    required this.warehouseId,
    required this.warehouseName,
    required this.status,
    required this.saleDate,
    this.dueDate,
    this.daysOverdue = 0,
    this.notes,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.amountPaid,
    this.overLimit = false,
    this.voidReason,
    this.createdByName,
    required this.lines,
    this.payments = const [],
  });

  final String id;
  final String reference;

  /// `null` for a walk-in sale.
  final String? customerId;
  final String customerName;
  final String warehouseId;
  final String warehouseName;
  final SaleStatus status;
  final DateTime saleDate;

  /// The sale date plus the customer's payment terms (null for walk-ins).
  final DateTime? dueDate;

  /// Days past [dueDate] with something still unpaid (0 otherwise).
  final int daysOverdue;
  final String? notes;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double amountPaid;

  /// Allowed over the customer's credit limit by an Owner or Administrator.
  final bool overLimit;
  final String? voidReason;
  final String? createdByName;
  final List<SaleLine> lines;

  /// Only filled by `GET /sales/{id}`.
  final List<SalePayment> payments;

  bool get isVoided => status == SaleStatus.voided;
  bool get isWalkIn => customerId == null;
  double get balance => isVoided ? 0 : total - amountPaid;
  bool get isPaid => !isVoided && amountPaid >= total - 0.004;
  int get units => lines.fold(0, (sum, l) => sum + l.quantity);

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] as String,
        reference: json['reference'] as String,
        customerId: json['customerId'] as String?,
        customerName: json['customerName'] as String? ?? 'Walk-in customer',
        warehouseId: json['warehouseId'] as String,
        warehouseName: json['warehouseName'] as String? ?? 'Warehouse',
        status: json['status'] == 'voided' ? SaleStatus.voided : SaleStatus.completed,
        saleDate: DateTime.parse(json['saleDate'] as String),
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? '')?.toLocal(),
        daysOverdue: (json['daysOverdue'] as num?)?.toInt() ?? 0,
        notes: json['notes'] as String?,
        subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        tax: (json['tax'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0,
        overLimit: json['overLimit'] as bool? ?? false,
        voidReason: json['voidReason'] as String?,
        createdByName: json['createdByName'] as String?,
        lines: [
          for (final row in (json['lines'] as List<dynamic>? ?? const []))
            SaleLine.fromJson(row as Map<String, dynamic>),
        ],
        payments: [
          for (final row in (json['payments'] as List<dynamic>? ?? const []))
            SalePayment.fromJson(row as Map<String, dynamic>),
        ],
      );
}

class SaleLineInput {
  const SaleLineInput({required this.productId, required this.quantity, required this.unitPrice});

  final String productId;
  final int quantity;
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => {'productId': productId, 'quantity': quantity, 'unitPrice': unitPrice};

  factory SaleLineInput.fromJson(Map<String, dynamic> json) => SaleLineInput(
        productId: json['productId'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
      );
}

/// What the sale form sends (and what is queued offline).
class SaleInput {
  const SaleInput({
    this.customerId,
    required this.warehouseId,
    required this.lines,
    this.discount = 0,
    this.tax = 0,
    required this.amountPaid,
    this.paymentMethod = SalePaymentMethod.cash,
    this.notes,
    this.allowOverLimit = false,
  });

  final String? customerId;
  final String warehouseId;
  final List<SaleLineInput> lines;
  final double discount;
  final double tax;
  final double amountPaid;
  final SalePaymentMethod paymentMethod;
  final String? notes;
  final bool allowOverLimit;

  double get subtotal => lines.fold(0.0, (sum, l) => sum + l.lineTotal);
  double get total => subtotal - discount + tax;
  double get unpaid => total - amountPaid;

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'warehouseId': warehouseId,
        'lines': [for (final l in lines) l.toJson()],
        'discount': discount,
        'tax': tax,
        'amountPaid': amountPaid,
        'paymentMethod': paymentMethod.apiValue,
        'notes': notes,
        'allowOverLimit': allowOverLimit,
      };

  factory SaleInput.fromJson(Map<String, dynamic> json) => SaleInput(
        customerId: json['customerId'] as String?,
        warehouseId: json['warehouseId'] as String,
        lines: [
          for (final row in (json['lines'] as List<dynamic>))
            SaleLineInput.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        tax: (json['tax'] as num?)?.toDouble() ?? 0,
        amountPaid: (json['amountPaid'] as num).toDouble(),
        paymentMethod: SalePaymentMethodX.fromApi(json['paymentMethod'] as String?),
        notes: json['notes'] as String?,
        allowOverLimit: json['allowOverLimit'] as bool? ?? false,
      );

  /// The same sale pointing at server ids once records created offline have
  /// synced.
  SaleInput resolved(String Function(String id) resolve) => SaleInput(
        customerId: customerId == null ? null : resolve(customerId!),
        warehouseId: warehouseId,
        lines: [
          for (final l in lines) SaleLineInput(productId: resolve(l.productId), quantity: l.quantity, unitPrice: l.unitPrice),
        ],
        discount: discount,
        tax: tax,
        amountPaid: amountPaid,
        paymentMethod: paymentMethod,
        notes: notes,
        allowOverLimit: allowOverLimit,
      );
}
