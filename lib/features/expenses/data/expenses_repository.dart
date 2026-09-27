import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/offline/persisted_list.dart';
import '../domain/expense.dart';

/// LOCAL ONLY — saved on this computer (per signed-in user) and restored on
/// the next launch. No `/api/v1/expenses` endpoint exists yet, so nothing
/// here is synced.
class ExpensesNotifier extends PersistedListNotifier<Expense> {
  @override
  String get name => 'expenses';

  @override
  Map<String, dynamic> encode(Expense item) => item.toJson();

  @override
  Expense decode(Map<String, dynamic> json) => Expense.fromJson(json);

  void addExpense(Expense expense) => setAndSave([expense, ...state]);
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
