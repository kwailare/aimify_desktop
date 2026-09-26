/// A stock location, exactly as `GET /api/v1/warehouses` returns it.
///
/// Warehouses are never deleted, only disabled ([isActive] false), because
/// past stock movements point at them. The plan caps how many can be active
/// at once (the default plan allows one).
class Warehouse {
  const Warehouse({
    required this.id,
    required this.name,
    this.address,
    this.managerName,
    this.phone,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? address;
  final String? managerName;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        managerName: json['managerName'] as String?,
        phone: json['phone'] as String?,
        isActive: (json['status'] as String?) != 'inactive',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
