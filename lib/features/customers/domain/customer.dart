/// LOCAL ONLY — there is no `/api/v1/customers` endpoint yet, so customers
/// are saved on this computer only (see `persisted_list.dart`).
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.creditLimit,
    required this.balanceOwed,
    required this.transactionHistory,
  });

  final String id;
  final String name;
  final String phone;
  final double creditLimit;

  /// How much this customer currently owes.
  final double balanceOwed;
  final List<CustomerTransaction> transactionHistory;

  double get availableCredit => creditLimit - balanceOwed;

  Customer copyWith({double? balanceOwed, List<CustomerTransaction>? transactionHistory}) =>
      Customer(
        id: id,
        name: name,
        phone: phone,
        creditLimit: creditLimit,
        balanceOwed: balanceOwed ?? this.balanceOwed,
        transactionHistory: transactionHistory ?? this.transactionHistory,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'creditLimit': creditLimit,
        'balanceOwed': balanceOwed,
        'transactionHistory': [for (final t in transactionHistory) t.toJson()],
      };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        creditLimit: (json['creditLimit'] as num).toDouble(),
        balanceOwed: (json['balanceOwed'] as num).toDouble(),
        transactionHistory: [
          for (final t in (json['transactionHistory'] as List<dynamic>? ?? const []))
            CustomerTransaction.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
      );
}

class CustomerTransaction {
  const CustomerTransaction({
    required this.date,
    required this.description,
    required this.amount,
  });

  final DateTime date;
  final String description;
  final double amount;

  Map<String, dynamic> toJson() => {
        'date': date.toUtc().toIso8601String(),
        'description': description,
        'amount': amount,
      };

  factory CustomerTransaction.fromJson(Map<String, dynamic> json) => CustomerTransaction(
        date: DateTime.parse(json['date'] as String).toLocal(),
        description: json['description'] as String,
        amount: (json['amount'] as num).toDouble(),
      );
}
