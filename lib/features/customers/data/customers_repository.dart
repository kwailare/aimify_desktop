import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/customer.dart';

/// LOCAL ONLY — in-memory for the current session. No `/api/v1/customers`
/// endpoint exists yet, so nothing here is saved or synced.
class CustomersNotifier extends Notifier<List<Customer>> {
  @override
  List<Customer> build() => const [];

  void addCustomer(Customer customer) => state = [...state, customer];

  /// Records a payment against a customer's outstanding balance — used by
  /// the Credits & Debts screen. Clamped so it can't go negative.
  void recordPayment(String customerId, double amount) {
    state = [
      for (final customer in state)
        if (customer.id == customerId)
          customer.copyWith(
            balanceOwed: (customer.balanceOwed - amount).clamp(0, double.infinity),
            transactionHistory: [
              ...customer.transactionHistory,
              CustomerTransaction(
                date: DateTime.now(),
                description: 'Payment received',
                amount: -amount,
              ),
            ],
          )
        else
          customer,
    ];
  }
}

final customersProvider = NotifierProvider<CustomersNotifier, List<Customer>>(
  CustomersNotifier.new,
);
