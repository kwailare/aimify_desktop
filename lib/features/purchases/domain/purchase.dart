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
}

/// Placeholder domain model — no `/api/v1/purchases` endpoint yet.
class Purchase {
  const Purchase({
    required this.id,
    required this.supplierName,
    required this.warehouseId,
    required this.warehouseName,
    required this.date,
    required this.items,
    required this.paymentStatus,
    required this.amountPaid,
  });

  final String id;
  final String supplierName;
  final String warehouseId;
  final String warehouseName;
  final DateTime date;
  final List<PurchaseLineItem> items;
  final PaymentStatus paymentStatus;
  final double amountPaid;

  double get totalCost => items.fold(0, (sum, item) => sum + item.lineTotal);
  double get balanceDue => totalCost - amountPaid;
}
