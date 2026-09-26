import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/expense.dart';

/// LOCAL ONLY — in-memory for the current session. No `/api/v1/expenses`
/// endpoint exists yet, so nothing here is saved or synced.
class ExpensesNotifier extends Notifier<List<Expense>> {
  @override
  List<Expense> build() => const [];

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
