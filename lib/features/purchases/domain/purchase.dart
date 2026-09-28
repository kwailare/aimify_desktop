enum PaymentStatus { paid, partial, unpaid }

extension PaymentStatusLabel on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.paid => 'Paid',
        PaymentStatus.partial => 'Partial',
        PaymentStatus.unpaid => 'Unpaid',
      };
}

class PurchaseLineItem {
  const PurchaseLineItem({
    required this.productName,
    required this.quantity,
    required this.unitCost,
  });

  final String productName;
  final int quantity;
  final double unitCost;

  double get lineTotal => quantity * unitCost;

  Map<String, dynamic> toJson() =>
      {'productName': productName, 'quantity': quantity, 'unitCost': unitCost};

  factory PurchaseLineItem.fromJson(Map<String, dynamic> json) => PurchaseLineItem(
        productName: json['productName'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitCost: (json['unitCost'] as num).toDouble(),
      );
}

/// LOCAL ONLY — there is no `/api/v1/purchases` endpoint yet, so purchases
/// are saved on this computer only (see `persisted_list.dart`).
class Purchase {
  const Purchase({
    required this.id,
    required this.supplierName,
    required this.date,
    required this.items,
    required this.paymentStatus,
    required this.amountPaid,
  });

  final String id;
  final String supplierName;
  final DateTime date;
  final List<PurchaseLineItem> items;
  final PaymentStatus paymentStatus;
  final double amountPaid;

  double get totalCost => items.fold(0, (sum, item) => sum + item.lineTotal);
  double get balanceDue => totalCost - amountPaid;

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierName': supplierName,
        'date': date.toUtc().toIso8601String(),
        'items': [for (final i in items) i.toJson()],
        'paymentStatus': paymentStatus.name,
        'amountPaid': amountPaid,
      };

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
        id: json['id'] as String,
        supplierName: json['supplierName'] as String,
        date: DateTime.parse(json['date'] as String).toLocal(),
        items: [
          for (final i in (json['items'] as List<dynamic>))
            PurchaseLineItem.fromJson(Map<String, dynamic>.from(i as Map)),
        ],
        paymentStatus: PaymentStatus.values.firstWhere(
          (s) => s.name == json['paymentStatus'],
          orElse: () => PaymentStatus.unpaid,
        ),
        amountPaid: (json['amountPaid'] as num).toDouble(),
      );
}
