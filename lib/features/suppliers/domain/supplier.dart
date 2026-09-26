/// LOCAL ONLY — there is no `/api/v1/suppliers` endpoint yet, so suppliers
/// live on this computer for the current session and are not synced.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    required this.contactPerson,
    required this.phone,
    required this.productsSupplied,
    required this.balanceOwed,
  });

  final String id;
  final String name;
  final String contactPerson;
  final String phone;
  final List<String> productsSupplied;

  /// How much this business owes the supplier right now.
  final double balanceOwed;

  Supplier copyWith({double? balanceOwed}) => Supplier(
        id: id,
        name: name,
        contactPerson: contactPerson,
        phone: phone,
        productsSupplied: productsSupplied,
        balanceOwed: balanceOwed ?? this.balanceOwed,
      );
}
