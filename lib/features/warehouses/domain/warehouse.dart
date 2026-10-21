/// A stock location, exactly as `GET /api/v1/warehouses` returns it.
///
/// Warehouses are never deleted, only disabled ([isActive] false), because
/// past stock movements point at them. A warehouse can only be disabled once
/// it holds no stock, and the plan caps how many can be active at once.
class Warehouse {
  const Warehouse({
    required this.id,
    required this.name,
    this.address,
    this.managerName,
    this.phone,
    required this.isActive,
    required this.createdAt,
    this.stock = WarehouseStock.empty,
  });

  final String id;
  final String name;
  final String? address;
  final String? managerName;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;

  /// What the warehouse holds right now.
  final WarehouseStock stock;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        managerName: json['managerName'] as String?,
        phone: json['phone'] as String?,
        isActive: (json['status'] as String?) != 'inactive',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        stock: json['stock'] is Map<String, dynamic>
            ? WarehouseStock.fromJson(json['stock'] as Map<String, dynamic>)
            : WarehouseStock.empty,
      );
}

/// A warehouse's stock: total units, how many products have a non-zero
/// balance there, and their value at purchase and selling price.
class WarehouseStock {
  const WarehouseStock({
    required this.units,
    required this.products,
    required this.valueAtCost,
    required this.valueAtRetail,
  });

  static const empty = WarehouseStock(units: 0, products: 0, valueAtCost: 0, valueAtRetail: 0);

  final int units;
  final int products;
  final double valueAtCost;
  final double valueAtRetail;

  bool get isEmpty => products == 0;

  factory WarehouseStock.fromJson(Map<String, dynamic> json) => WarehouseStock(
        units: (json['units'] as num?)?.toInt() ?? 0,
        products: (json['products'] as num?)?.toInt() ?? 0,
        valueAtCost: (json['valueAtCost'] as num?)?.toDouble() ?? 0,
        valueAtRetail: (json['valueAtRetail'] as num?)?.toDouble() ?? 0,
      );
}
