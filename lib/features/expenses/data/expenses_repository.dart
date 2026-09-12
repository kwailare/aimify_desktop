import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/expense.dart';

/// MOCK repository — in-memory only. No `/api/v1/expenses` endpoint yet.
class ExpensesNotifier extends Notifier<List<Expense>> {
  @override
  List<Expense> build() {
    final now = DateTime.now();
    return [
      Expense(
        id: 'e1',
        category: 'Rent',
        amount: 250000,
        date: DateTime(now.year, now.month, 1),
        paymentMethod: PaymentMethod.bankTransfer,
        note: 'SAMPLE — Warehouse rent for the month',
      ),
      Expense(
        id: 'e2',
        category: 'Transport',
        amount: 18000,
        date: now.subtract(const Duration(days: 3)),
        paymentMethod: PaymentMethod.cash,
        note: 'SAMPLE — Delivery van fuel',
      ),
      Expense(
        id: 'e3',
        category: 'Utilities',
        amount: 32500,
        date: now.subtract(const Duration(days: 5)),
        paymentMethod: PaymentMethod.mobileMoney,
        note: 'SAMPLE — Electricity bill',
      ),
      Expense(
        id: 'e4',
        category: 'Staff wages',
        amount: 400000,
        date: now.subtract(const Duration(days: 7)),
        paymentMethod: PaymentMethod.bankTransfer,
        note: 'SAMPLE — Warehouse staff payroll',
      ),
    ];
  }

  void addExpense(Expense expense) => state = [expense, ...state];
}

final expensesProvider = NotifierProvider<ExpensesNotifier, List<Expense>>(
  ExpensesNotifier.new,
);

/// Convenience derived total for the dashboard.
final totalExpensesThisMonthProvider = Provider<double>((ref) {
  final expenses = ref.watch(expensesProvider);
  final now = DateTime.now();
  return expenses
      .where((e) => e.date.year == now.year && e.date.month == now.month)
      .fold(0.0, (sum, e) => sum + e.amount);
});
