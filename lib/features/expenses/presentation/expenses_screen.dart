import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/local_only_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import 'expense_form_dialog.dart';

/// LOCAL ONLY: expenses have no backend yet (see `docs/desktop-api.md`),
/// so this screen works on this computer for the current session.
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Expenses',
              subtitle: '${expenses.length} recorded expenses',
              badge: const LocalOnlyBadge(),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const ExpenseFormDialog(),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add expense'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (expenses.isEmpty)
              const Expanded(
                child: Card(
                  child: Center(
                    child: Text('No expenses recorded yet. Use "Add expense" to add one.'),
                  ),
                ),
              )
            else
              Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Category')),
                        DataColumn(label: Text('Note')),
                        DataColumn(label: Text('Payment method')),
                        DataColumn(label: Text('Amount'), numeric: true),
                      ],
                      rows: [
                        for (final expense in expenses)
                          DataRow(
                            cells: [
                              DataCell(Text(dateFormat.format(expense.date))),
                              DataCell(Text(expense.category)),
                              DataCell(Text(expense.note)),
                              DataCell(Text(expense.paymentMethod.label)),
                              DataCell(Text(currencyFormat.format(expense.amount))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
