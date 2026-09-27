/// LOCAL ONLY — there is no `/api/v1/suppliers` endpoint yet, so suppliers
/// are saved on this computer only (see `persisted_list.dart`).
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'contactPerson': contactPerson,
        'phone': phone,
        'productsSupplied': productsSupplied,
        'balanceOwed': balanceOwed,
      };

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as String,
        name: json['name'] as String,
        contactPerson: json['contactPerson'] as String,
        phone: json['phone'] as String,
        productsSupplied: List<String>.from(json['productsSupplied'] as List),
        balanceOwed: (json['balanceOwed'] as num).toDouble(),
      );
}
