enum PaymentMethod { cash, bankTransfer, card, mobileMoney }

extension PaymentMethodLabel on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.bankTransfer => 'Bank transfer',
        PaymentMethod.card => 'Card',
        PaymentMethod.mobileMoney => 'Mobile money',
      };
}

/// LOCAL ONLY — there is no `/api/v1/expenses` endpoint yet, so expenses
/// are saved on this computer only (see `persisted_list.dart`).
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'amount': amount,
        'date': date.toUtc().toIso8601String(),
        'paymentMethod': paymentMethod.name,
        'note': note,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        category: json['category'] as String,
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String).toLocal(),
        paymentMethod: PaymentMethod.values.firstWhere(
          (m) => m.name == json['paymentMethod'],
          orElse: () => PaymentMethod.cash,
        ),
        note: json['note'] as String,
      );
}
