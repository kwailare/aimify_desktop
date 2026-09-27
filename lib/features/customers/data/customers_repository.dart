import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/offline/persisted_list.dart';
import '../domain/customer.dart';

/// LOCAL ONLY — saved on this computer (per signed-in user) and restored on
/// the next launch. No `/api/v1/customers` endpoint exists yet, so nothing
/// here is synced.
class CustomersNotifier extends PersistedListNotifier<Customer> {
  @override
  String get name => 'customers';

  @override
  Map<String, dynamic> encode(Customer item) => item.toJson();

  @override
  Customer decode(Map<String, dynamic> json) => Customer.fromJson(json);

  void addCustomer(Customer customer) => setAndSave([...state, customer]);

  /// Records a payment against a customer's outstanding balance — used by
  /// the Credits & Debts screen. Clamped so it can't go negative.
  void recordPayment(String customerId, double amount) {
    setAndSave([
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
    ]);
  }
}

final customersProvider = NotifierProvider<CustomersNotifier, List<Customer>>(
  CustomersNotifier.new,
);
