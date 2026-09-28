/// Customers (people who owe you) and suppliers (people you owe) are the same
/// kind of record on the backend, so the app models them once.
enum PartyType { customer, supplier }

extension PartyTypeX on PartyType {
  String get apiValue => name;

  String get label => this == PartyType.customer ? 'Customer' : 'Supplier';
  String get plural => this == PartyType.customer ? 'customers' : 'suppliers';

  static PartyType fromApi(String value) =>
      value == 'supplier' ? PartyType.supplier : PartyType.customer;
}

/// A customer or supplier as `/api/v1/customers` and `/api/v1/suppliers`
/// return them. [balanceOwed] is what is still owed: for a customer, what they
/// owe you; for a supplier, what you owe them. It is the sum of the party's
/// credit ledger.
class Party {
  const Party({
    required this.id,
    required this.type,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.creditLimit = 0,
    this.balanceOwed = 0,
    this.isActive = true,
    this.isPending = false,
  });

  final String id;
  final PartyType type;
  final String name;

  /// Suppliers only.
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;

  /// Customers only.
  final double creditLimit;
  final double balanceOwed;
  final bool isActive;

  /// True for a party created while offline that hasn't reached the server.
  final bool isPending;

  bool get isAtCreditLimit => type == PartyType.customer && creditLimit > 0 && balanceOwed >= creditLimit;

  Party copyWith({double? balanceOwed, bool? isPending}) => Party(
        id: id,
        type: type,
        name: name,
        contactPerson: contactPerson,
        phone: phone,
        email: email,
        address: address,
        notes: notes,
        creditLimit: creditLimit,
        balanceOwed: balanceOwed ?? this.balanceOwed,
        isActive: isActive,
        isPending: isPending ?? this.isPending,
      );

  Party withInput(PartyInput input) => Party(
        id: id,
        type: type,
        name: input.name,
        contactPerson: input.contactPerson,
        phone: input.phone,
        email: input.email,
        address: input.address,
        notes: input.notes,
        creditLimit: input.creditLimit,
        balanceOwed: balanceOwed,
        isActive: isActive,
        isPending: isPending,
      );

  factory Party.fromJson(PartyType type, Map<String, dynamic> json) => Party(
        id: json['id'] as String,
        type: type,
        name: json['name'] as String,
        contactPerson: json['contactPerson'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        creditLimit: (json['creditLimit'] as num?)?.toDouble() ?? 0,
        balanceOwed: (json['balanceOwed'] as num?)?.toDouble() ?? 0,
        isActive: (json['status'] as String?) != 'archived',
      );
}

/// The editable fields of a customer or supplier — what create sends and
/// edit changes.
class PartyInput {
  const PartyInput({
    required this.type,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.creditLimit = 0,
  });

  final PartyType type;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double creditLimit;

  /// The request body. Customers send `creditLimit`, suppliers send
  /// `contactPerson` — the server refuses the other resource's field.
  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
        if (type == PartyType.supplier) 'contactPerson': contactPerson,
        if (type == PartyType.customer) 'creditLimit': creditLimit,
      };

  factory PartyInput.fromJson(PartyType type, Map<String, dynamic> json) => PartyInput(
        type: type,
        name: json['name'] as String,
        contactPerson: json['contactPerson'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        creditLimit: (json['creditLimit'] as num?)?.toDouble() ?? 0,
      );

  Party toLocalParty(String id) => Party(
        id: id,
        type: type,
        name: name,
        contactPerson: contactPerson,
        phone: phone,
        email: email,
        address: address,
        notes: notes,
        creditLimit: creditLimit,
        isPending: true,
      );
}

/// What a credit-ledger entry does to the balance owed.
enum CreditKind { charge, payment, adjustment }

extension CreditKindX on CreditKind {
  String get apiValue => name;

  String get label => switch (this) {
        CreditKind.charge => 'Charge',
        CreditKind.payment => 'Payment',
        CreditKind.adjustment => 'Adjustment',
      };

  static CreditKind fromApi(String value) => switch (value) {
        'payment' => CreditKind.payment,
        'adjustment' => CreditKind.adjustment,
        _ => CreditKind.charge,
      };
}

/// One line of a party's credit ledger. [amount] is signed as stored: a
/// positive amount raised the balance owed, a negative one lowered it.
class CreditEntry {
  const CreditEntry({
    required this.id,
    required this.partyType,
    required this.partyId,
    required this.kind,
    required this.amount,
    this.note,
    this.userId,
    required this.createdAt,
    this.isPending = false,
  });

  final String id;
  final PartyType partyType;
  final String partyId;
  final CreditKind kind;
  final double amount;
  final String? note;
  final String? userId;
  final DateTime createdAt;
  final bool isPending;

  factory CreditEntry.fromJson(Map<String, dynamic> json) => CreditEntry(
        id: json['id'] as String,
        partyType: PartyTypeX.fromApi(json['partyType'] as String? ?? 'customer'),
        partyId: json['partyId'] as String,
        kind: CreditKindX.fromApi(json['kind'] as String? ?? 'charge'),
        amount: (json['amount'] as num).toDouble(),
        note: json['note'] as String?,
        userId: json['userId'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );
}

/// The signed amount an entry of [kind] stores, given what the person typed.
/// Charges raise the balance, payments lower it, and an adjustment is signed
/// by the person (the server applies the same rule).
double signedCreditAmount(CreditKind kind, double entered) => switch (kind) {
      CreditKind.charge => entered.abs(),
      CreditKind.payment => -entered.abs(),
      CreditKind.adjustment => entered,
    };
