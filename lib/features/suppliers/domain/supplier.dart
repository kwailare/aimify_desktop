/// Placeholder domain model — no `/api/v1/suppliers` endpoint yet.
///
/// Scoped to one [warehouseId] — a real distributor relationship is
/// usually managed by whoever runs that specific location, consistent
/// with staff eventually only seeing suppliers for their own warehouse.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.phone,
    required this.productsSupplied,
    required this.balanceOwed,
    required this.warehouseId,
  });

  final String id;
  final String name;
  final String contactPerson;
  final String phone;
  final List<String> productsSupplied;

  /// How much this business owes the supplier right now.
  final double balanceOwed;
  final String warehouseId;

  Supplier copyWith({double? balanceOwed}) => Supplier(
        id: id,
        name: name,
        contactPerson: contactPerson,
        phone: phone,
        productsSupplied: productsSupplied,
        balanceOwed: balanceOwed ?? this.balanceOwed,
        warehouseId: warehouseId,
      );
}
