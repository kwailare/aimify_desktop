import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/customer.dart';

/// MOCK repository — in-memory only. No `/api/v1/customers` endpoint yet.
class CustomersNotifier extends Notifier<List<Customer>> {
  @override
  List<Customer> build() {
    final now = DateTime.now();
    return [
      Customer(
        id: 'c1',
        name: 'SAMPLE Blessing Retail Store',
        phone: '+234 706 555 0201',
        creditLimit: 200000,
        balanceOwed: 45000,
        transactionHistory: [
          CustomerTransaction(
            date: now.subtract(const Duration(days: 6)),
            description: 'Sale — SAMPLE-INV-2040',
            amount: 45000,
          ),
        ],
      ),
      Customer(
        id: 'c2',
        name: 'SAMPLE Kingsway Provisions',
        phone: '+234 707 555 0202',
        creditLimit: 500000,
        balanceOwed: 0,
        transactionHistory: [
          CustomerTransaction(
            date: now.subtract(const Duration(days: 10)),
            description: 'Sale — SAMPLE-INV-2031',
            amount: 120000,
          ),
          CustomerTransaction(
            date: now.subtract(const Duration(days: 9)),
            description: 'Payment received',
            amount: -120000,
          ),
        ],
      ),
      Customer(
        id: 'c3',
        name: 'SAMPLE Corner Shop Emeka',
        phone: '+234 708 555 0203',
        creditLimit: 80000,
        balanceOwed: 80000,
        transactionHistory: [
          CustomerTransaction(
            date: now.subtract(const Duration(days: 20)),
            description: 'Sale — SAMPLE-INV-2015',
            amount: 80000,
          ),
        ],
      ),
    ];
  }

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
