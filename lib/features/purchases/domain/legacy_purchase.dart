/// A purchase saved on this computer by app versions before purchases moved
/// to the server. Only read, so it can be offered for import as a draft
/// (see `import_legacy_purchases_dialog.dart`); products were typed as text
/// and the supplier chosen by name, so both are matched by name on import.
class LegacyPurchase {
  const LegacyPurchase({
    required this.id,
    required this.supplierName,
    required this.date,
    required this.items,
    required this.amountPaid,
  });

  final String id;
  final String supplierName;
  final DateTime date;
  final List<LegacyPurchaseLine> items;
  final double amountPaid;

  double get totalCost => items.fold(0, (sum, item) => sum + item.quantity * item.unitCost);

  Map<String, dynamic> toJson() => {
    'id': id,
    'supplierName': supplierName,
    'date': date.toUtc().toIso8601String(),
    'items': [for (final i in items) i.toJson()],
    'amountPaid': amountPaid,
  };

  factory LegacyPurchase.fromJson(Map<String, dynamic> json) => LegacyPurchase(
    id: json['id'] as String,
    supplierName: json['supplierName'] as String,
    date: DateTime.parse(json['date'] as String).toLocal(),
    items: [
      for (final i in (json['items'] as List<dynamic>))
        LegacyPurchaseLine.fromJson(Map<String, dynamic>.from(i as Map)),
    ],
    amountPaid: (json['amountPaid'] as num?)?.toDouble() ?? 0,
  );
}

class LegacyPurchaseLine {
  const LegacyPurchaseLine({
    required this.productName,
    required this.quantity,
    required this.unitCost,
  });

  final String productName;
  final int quantity;
  final double unitCost;

  Map<String, dynamic> toJson() => {
    'productName': productName,
    'quantity': quantity,
    'unitCost': unitCost,
  };

  factory LegacyPurchaseLine.fromJson(Map<String, dynamic> json) => LegacyPurchaseLine(
    productName: json['productName'] as String,
    quantity: (json['quantity'] as num).toInt(),
    unitCost: (json['unitCost'] as num).toDouble(),
  );
}
