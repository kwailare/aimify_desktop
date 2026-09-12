enum PaymentMethod { cash, bankTransfer, card, mobileMoney }

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.bankTransfer => 'Bank transfer',
        PaymentMethod.card => 'Card',
        PaymentMethod.mobileMoney => 'Mobile money',
      };
}

/// Placeholder domain model — no `/api/v1/expenses` endpoint yet.
class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    required this.note,
  });

  final String id;
  final String category;
  final double amount;
  final DateTime date;
  final PaymentMethod paymentMethod;
  final String note;
}
