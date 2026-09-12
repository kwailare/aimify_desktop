/// Placeholder domain model — no `/api/v1/customers` endpoint yet.
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
}
