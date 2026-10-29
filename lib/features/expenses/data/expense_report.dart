import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../sales/domain/sale.dart';
import '../domain/expense.dart';

/// One category's spending in a period, against its monthly budget.
class CategorySpend {
  const CategorySpend({required this.name, required this.total, required this.count, this.budget = 0});

  final String name;
  final double total;
  final int count;

  /// The category's monthly budget times the number of months in the period
  /// (0 without a budget).
  final double budget;

  bool get hasBudget => budget > 0;
  double get left => budget - total;
  bool get overBudget => hasBudget && total > budget + 0.004;

  /// How much of the budget is used, 0–1+ (null without one).
  double? get used => hasBudget ? total / budget : null;
}

class ExpenseReport {
  const ExpenseReport({
    required this.from,
    required this.to,
    required this.months,
    required this.total,
    required this.count,
    required this.byCategory,
    required this.byMonth,
    required this.byWarehouse,
    required this.byMethod,
    required this.expenses,
  });

  /// The period: [from] inclusive, [to] exclusive.
  final DateTime from;
  final DateTime to;

  /// Whole months in the period (budgets are monthly).
  final int months;
  final double total;
  final int count;

  /// Biggest first; categories with a budget and no spending are included.
  final List<CategorySpend> byCategory;

  /// Oldest first, as (first day of the month, total).
  final List<(DateTime, double)> byMonth;

  /// Biggest first; "The whole business" for expenses with no warehouse.
  final List<(String, double)> byWarehouse;
  final List<(SalePaymentMethod, double)> byMethod;

  /// The recorded expenses in the period, newest first.
  final List<Expense> expenses;

  double get budget => byCategory.fold(0.0, (s, c) => s + c.budget);
}

int _monthsBetween(DateTime from, DateTime to) {
  final months = (to.year - from.year) * 12 + to.month - from.month;
  return months < 1 ? 1 : months;
}

/// The report for [from] (inclusive) to [to] (exclusive), from [all]
/// expenses (voided ones are left out) and the [categories] with their
/// budgets.
ExpenseReport buildExpenseReport(List<Expense> all, List<ExpenseCategory> categories, DateTime from, DateTime to) {
  final inPeriod = all.where((e) => !e.isVoided && !e.expenseDate.isBefore(from) && e.expenseDate.isBefore(to)).toList()
    ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
  final months = _monthsBetween(from, to);

  final byCategory = <String, (String, double, int)>{};
  final byMonth = <DateTime, double>{};
  final byWarehouse = <String, double>{};
  final byMethod = <SalePaymentMethod, double>{};
  for (final e in inPeriod) {
    final c = byCategory[e.categoryId] ?? (e.categoryName, 0.0, 0);
    byCategory[e.categoryId] = (c.$1, c.$2 + e.amount, c.$3 + 1);
    final month = DateTime(e.expenseDate.year, e.expenseDate.month);
    byMonth[month] = (byMonth[month] ?? 0) + e.amount;
    final w = e.warehouseName ?? 'The whole business';
    byWarehouse[w] = (byWarehouse[w] ?? 0) + e.amount;
    byMethod[e.paymentMethod] = (byMethod[e.paymentMethod] ?? 0) + e.amount;
  }
  final budgets = {for (final c in categories) c.id: c};
  final spends = [
    for (final entry in byCategory.entries)
      CategorySpend(
        name: budgets[entry.key]?.name ?? entry.value.$1,
        total: entry.value.$2,
        count: entry.value.$3,
        budget: (budgets[entry.key]?.monthlyBudget ?? 0) * months,
      ),
    for (final c in categories)
      if (c.hasBudget && !byCategory.containsKey(c.id))
        CategorySpend(name: c.name, total: 0, count: 0, budget: c.monthlyBudget * months),
  ]..sort((a, b) => b.total.compareTo(a.total));

  return ExpenseReport(
    from: from,
    to: to,
    months: months,
    total: inPeriod.fold(0.0, (s, e) => s + e.amount),
    count: inPeriod.length,
    byCategory: spends,
    byMonth: (byMonth.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => a.$1.compareTo(b.$1))),
    byWarehouse: (byWarehouse.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2))),
    byMethod: (byMethod.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2))),
    expenses: inPeriod,
  );
}

/// The report as a spreadsheet: a summary sheet (by category with budgets,
/// by month, by warehouse) and every expense.
List<int> buildExpenseReportExcel(ExpenseReport r) {
  final book = Excel.createExcel();
  final date = DateFormat('yyyy-MM-dd');
  final summary = book[book.getDefaultSheet()!];
  summary.appendRow([TextCellValue('Expenses ${date.format(r.from)} to ${date.format(r.to.subtract(const Duration(days: 1)))}')]);
  summary.appendRow([TextCellValue('Total'), DoubleCellValue(r.total), TextCellValue('${r.count} expenses')]);
  summary.appendRow([]);
  summary.appendRow([for (final h in ['Category', 'Spent', 'Expenses', 'Budget', 'Left']) TextCellValue(h)]);
  for (final c in r.byCategory) {
    summary.appendRow([
      TextCellValue(c.name),
      DoubleCellValue(c.total),
      IntCellValue(c.count),
      c.hasBudget ? DoubleCellValue(c.budget) : TextCellValue(''),
      c.hasBudget ? DoubleCellValue(c.left) : TextCellValue(''),
    ]);
  }
  summary.appendRow([]);
  summary.appendRow([TextCellValue('Month'), TextCellValue('Spent')]);
  for (final (month, total) in r.byMonth) {
    summary.appendRow([TextCellValue(DateFormat('MMMM yyyy').format(month)), DoubleCellValue(total)]);
  }
  summary.appendRow([]);
  summary.appendRow([TextCellValue('Warehouse'), TextCellValue('Spent')]);
  for (final (warehouse, total) in r.byWarehouse) {
    summary.appendRow([TextCellValue(warehouse), DoubleCellValue(total)]);
  }
  book.rename(book.getDefaultSheet()!, 'Summary');

  final list = book['Expenses'];
  list.appendRow([
    for (final h in ['Reference', 'Date', 'Category', 'Description', 'Paid to', 'Their receipt no.', 'Paid by', 'Warehouse', 'Amount', 'Recorded by'])
      TextCellValue(h),
  ]);
  for (final e in r.expenses) {
    list.appendRow([
      TextCellValue(e.reference),
      TextCellValue(date.format(e.expenseDate)),
      TextCellValue(e.categoryName),
      TextCellValue(e.description ?? ''),
      TextCellValue(e.payee ?? ''),
      TextCellValue(e.receiptNumber ?? ''),
      TextCellValue(e.paymentMethod.label),
      TextCellValue(e.warehouseName ?? ''),
      DoubleCellValue(e.amount),
      TextCellValue(e.createdByName ?? ''),
    ]);
  }
  return book.encode() ?? const [];
}
