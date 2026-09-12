import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/status_pill.dart';
import '../data/customers_repository.dart';
import 'customer_form_dialog.dart';
import 'customer_history_dialog.dart';

/// UI-only for now: reads from the MOCK [customersProvider].
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Customers',
              subtitle: '${customers.length} customers · tap a row for transaction history',
              badge: const MockDataBadge(),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const CustomerFormDialog(),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add customer'),
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
                        DataColumn(label: Text('Customer')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Credit limit'), numeric: true),
                        DataColumn(label: Text('Balance owed'), numeric: true),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: [
                        for (final customer in customers)
                          DataRow(
                            onSelectChanged: (_) => showDialog(
                              context: context,
                              builder: (_) => CustomerHistoryDialog(customer: customer),
                            ),
                            cells: [
                              DataCell(Text(customer.name)),
                              DataCell(Text(customer.phone)),
                              DataCell(Text(currencyFormat.format(customer.creditLimit))),
                              DataCell(Text(currencyFormat.format(customer.balanceOwed))),
                              DataCell(
                                customer.balanceOwed >= customer.creditLimit &&
                                        customer.creditLimit > 0
                                    ? const StatusPill(
                                        label: 'At limit', tone: StatusTone.negative)
                                    : customer.balanceOwed > 0
                                        ? const StatusPill(
                                            label: 'Owing', tone: StatusTone.warning)
                                        : const StatusPill(
                                            label: 'Clear', tone: StatusTone.positive),
                              ),
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
