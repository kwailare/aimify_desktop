import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/local_only_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/status_pill.dart';
import '../data/suppliers_repository.dart';
import 'supplier_form_dialog.dart';

/// LOCAL ONLY: suppliers have no backend yet (see `docs/desktop-api.md`),
/// so this screen works on this computer for the current session.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Suppliers',
              subtitle: '${suppliers.length} suppliers on file',
              badge: const LocalOnlyBadge(),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const SupplierFormDialog(),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add supplier'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (suppliers.isEmpty)
              const Expanded(
                child: Card(
                  child: Center(
                    child: Text('No suppliers yet. Use "Add supplier" to add one.'),
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
                        DataColumn(label: Text('Supplier')),
                        DataColumn(label: Text('Contact person')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Products supplied')),
                        DataColumn(label: Text('Balance owed'), numeric: true),
                      ],
                      rows: [
                        for (final supplier in suppliers)
                          DataRow(
                            cells: [
                              DataCell(Text(supplier.name)),
                              DataCell(Text(supplier.contactPerson)),
                              DataCell(Text(supplier.phone)),
                              DataCell(
                                Text(
                                  supplier.productsSupplied.isEmpty
                                      ? '—'
                                      : supplier.productsSupplied.join(', '),
                                ),
                              ),
                              DataCell(
                                supplier.balanceOwed > 0
                                    ? StatusPill(
                                        label: currencyFormat.format(supplier.balanceOwed),
                                        tone: StatusTone.warning,
                                      )
                                    : const StatusPill(label: 'Settled', tone: StatusTone.positive),
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
