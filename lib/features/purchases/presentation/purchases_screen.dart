import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/local_only_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/status_pill.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';
import 'purchase_form_dialog.dart';

/// LOCAL ONLY: purchases have no backend yet (see `docs/desktop-api.md`),
/// so this screen works on this computer for the current session.
class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Purchases',
              subtitle: '${purchases.length} purchase orders',
              badge: const LocalOnlyBadge(),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const PurchaseFormDialog(),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Record purchase'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (purchases.isEmpty)
              const Expanded(
                child: Card(
                  child: Center(
                    child: Text('No purchases recorded yet. Use "Record purchase" to add one.'),
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
                      columns: [
                        const DataColumn(label: Text('PO #')),
                        const DataColumn(label: Text('Supplier')),
                        const DataColumn(label: Text('Date')),
                        const DataColumn(label: Text('Items')),
                        const DataColumn(label: Text('Total'), numeric: true),
                        const DataColumn(label: Text('Payment')),
                      ],
                      rows: [
                        for (final purchase in purchases)
                          DataRow(
                            cells: [
                              DataCell(Text(purchase.id)),
                              DataCell(Text(purchase.supplierName)),
                              DataCell(Text(dateFormat.format(purchase.date))),
                              DataCell(Text('${purchase.items.length} line item(s)')),
                              DataCell(Text(currencyFormat.format(purchase.totalCost))),
                              DataCell(_PaymentStatusPill(status: purchase.paymentStatus)),
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

class _PaymentStatusPill extends StatelessWidget {
  const _PaymentStatusPill({required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      PaymentStatus.paid => StatusTone.positive,
      PaymentStatus.partial => StatusTone.warning,
      PaymentStatus.unpaid => StatusTone.negative,
    };
    return StatusPill(label: status.label, tone: tone);
  }
}
