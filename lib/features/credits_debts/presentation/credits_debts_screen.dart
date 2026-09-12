import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer.dart';
import '../../suppliers/data/suppliers_repository.dart';
import '../../suppliers/domain/supplier.dart';
import 'record_payment_dialog.dart';

/// Money owed to the business (customer balances) and money the business
/// owes (supplier balances), in one place. Reads from the same MOCK
/// [customersProvider] / [suppliersProvider] as those modules' own
/// screens — this is a different view over the same data, not a separate
/// source of truth.
class CreditsDebtsScreen extends ConsumerStatefulWidget {
  const CreditsDebtsScreen({super.key});

  @override
  ConsumerState<CreditsDebtsScreen> createState() => _CreditsDebtsScreenState();
}

class _CreditsDebtsScreenState extends ConsumerState<CreditsDebtsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customers = ref.watch(customersProvider);
    final suppliers = ref.watch(suppliersProvider);

    final totalReceivable = customers.fold(0.0, (sum, c) => sum + c.balanceOwed);
    final totalPayable = suppliers.fold(0.0, (sum, s) => sum + s.balanceOwed);
    final net = totalReceivable - totalPayable;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Credits & Debts',
              subtitle: 'Money owed to you, and money you owe suppliers',
              badge: MockDataBadge(),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  StatCard(
                    label: 'Total receivable',
                    value: currencyFormat.format(totalReceivable),
                    caption: 'Owed to you by customers',
                    icon: Icons.call_received,
                    accentColor: const Color(0xFF2F8F5B),
                  ),
                  StatCard(
                    label: 'Total payable',
                    value: currencyFormat.format(totalPayable),
                    caption: 'You owe suppliers',
                    icon: Icons.call_made,
                    accentColor: theme.colorScheme.error,
                  ),
                  StatCard(
                    label: 'Net position',
                    value: '${net >= 0 ? '+' : '-'}${currencyFormat.format(net.abs())}',
                    caption: net >= 0 ? 'More owed to you than you owe' : 'You owe more than you\'re owed',
                    icon: Icons.balance,
                    accentColor: net >= 0 ? const Color(0xFF2F8F5B) : theme.colorScheme.error,
                  ),
                ];
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 156,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (context, index) => cards[index],
                );
              },
            ),
            const SizedBox(height: 24),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(text: 'Customers who owe you'),
                Tab(text: 'Suppliers you owe'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _CustomerDebtsTable(customers: customers),
                  _SupplierCreditsTable(suppliers: suppliers),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerDebtsTable extends ConsumerWidget {
  const _CustomerDebtsTable({required this.customers});

  final List<Customer> customers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owing = customers.where((c) => c.balanceOwed > 0).toList()
      ..sort((a, b) => b.balanceOwed.compareTo(a.balanceOwed));

    if (owing.isEmpty) {
      return const _EmptyState(message: 'No customer currently owes you anything.');
    }

    return Card(
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
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final customer in owing)
                DataRow(
                  cells: [
                    DataCell(Text(customer.name)),
                    DataCell(Text(customer.phone)),
                    DataCell(Text(currencyFormat.format(customer.creditLimit))),
                    DataCell(Text(currencyFormat.format(customer.balanceOwed))),
                    DataCell(
                      customer.balanceOwed >= customer.creditLimit
                          ? const StatusPill(label: 'At limit', tone: StatusTone.negative)
                          : const StatusPill(label: 'Owing', tone: StatusTone.warning),
                    ),
                    DataCell(
                      TextButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => RecordPaymentDialog(
                            title: 'Record payment from ${customer.name}',
                            currentBalance: customer.balanceOwed,
                            onSubmit: (amount) => ref
                                .read(customersProvider.notifier)
                                .recordPayment(customer.id, amount),
                          ),
                        ),
                        child: const Text('Record payment'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierCreditsTable extends ConsumerWidget {
  const _SupplierCreditsTable({required this.suppliers});

  final List<Supplier> suppliers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owing = suppliers.where((s) => s.balanceOwed > 0).toList()
      ..sort((a, b) => b.balanceOwed.compareTo(a.balanceOwed));

    if (owing.isEmpty) {
      return const _EmptyState(message: "You don't owe any supplier anything right now.");
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Contact person')),
              DataColumn(label: Text('Balance owed'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final supplier in owing)
                DataRow(
                  cells: [
                    DataCell(Text(supplier.name)),
                    DataCell(Text(supplier.contactPerson)),
                    DataCell(
                      StatusPill(
                        label: currencyFormat.format(supplier.balanceOwed),
                        tone: StatusTone.warning,
                      ),
                    ),
                    DataCell(
                      TextButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => RecordPaymentDialog(
                            title: 'Record payment to ${supplier.name}',
                            currentBalance: supplier.balanceOwed,
                            onSubmit: (amount) => ref
                                .read(suppliersProvider.notifier)
                                .recordPayment(supplier.id, amount),
                          ),
                        ),
                        child: const Text('Record payment'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
      ),
    );
  }
}
