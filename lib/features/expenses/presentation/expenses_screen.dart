import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import 'expense_form_dialog.dart';

/// UI-only for now: reads from the MOCK [expensesProvider].
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
              badge: const MockDataBadge(),
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
