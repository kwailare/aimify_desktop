import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../parties/presentation/credit_entry_dialog.dart';
import '../../parties/presentation/party_history_dialog.dart';

/// Money owed to the business (customer balances) and money the business
/// owes (supplier balances), in one place. It is a view over the same live
/// customers and suppliers as those screens, and each balance is the sum of
/// that party's credit ledger, so nothing here can drift from the source.
///
/// Reading a side needs `customers.read` / `suppliers.read`; recording a
/// payment needs `credit.record`.
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
    final canSeeCustomers = hasPermission(ref, Permissions.customersRead);
    final canSeeSuppliers = hasPermission(ref, Permissions.suppliersRead);
    final canRecord = hasPermission(ref, Permissions.creditRecord);
    final customers = ref.watch(partyListProvider(PartyType.customer));
    final suppliers = ref.watch(partyListProvider(PartyType.supplier));

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
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  StatCard(
                    label: 'Total receivable',
                    value: canSeeCustomers ? currencyFormat.format(totalReceivable) : '—',
                    caption: 'Owed to you by customers',
                    icon: Icons.call_received,
                    accentColor: const Color(0xFF2F8F5B),
                  ),
                  StatCard(
                    label: 'Total payable',
                    value: canSeeSuppliers ? currencyFormat.format(totalPayable) : '—',
                    caption: 'You owe suppliers',
                    icon: Icons.call_made,
                    accentColor: theme.colorScheme.error,
                  ),
                  StatCard(
                    label: 'Net position',
                    value: (canSeeCustomers && canSeeSuppliers)
                        ? '${net >= 0 ? '+' : '-'}${currencyFormat.format(net.abs())}'
                        : '—',
                    caption: net >= 0 ? 'More owed to you than you owe' : "You owe more than you're owed",
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
                  _DebtsTable(
                    parties: customers,
                    allowed: canSeeCustomers,
                    canRecord: canRecord,
                    type: PartyType.customer,
                    emptyMessage: 'No customer currently owes you anything.',
                    deniedMessage: "Your role can't view customers.",
                  ),
                  _DebtsTable(
                    parties: suppliers,
                    allowed: canSeeSuppliers,
                    canRecord: canRecord,
                    type: PartyType.supplier,
                    emptyMessage: "You don't owe any supplier anything right now.",
                    deniedMessage: "Your role can't view suppliers.",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtsTable extends ConsumerWidget {
  const _DebtsTable({
    required this.parties,
    required this.allowed,
    required this.canRecord,
    required this.type,
    required this.emptyMessage,
    required this.deniedMessage,
  });

  final List<Party> parties;
  final bool allowed;
  final bool canRecord;
  final PartyType type;
  final String emptyMessage;
  final String deniedMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!allowed) return _Message(deniedMessage);

    final owing = parties.where((p) => p.balanceOwed > 0).toList()
      ..sort((a, b) => b.balanceOwed.compareTo(a.balanceOwed));

    if (owing.isEmpty) return _Message(emptyMessage);

    final isCustomer = type == PartyType.customer;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: [
              DataColumn(label: Text(type.label)),
              DataColumn(label: Text(isCustomer ? 'Phone' : 'Contact person')),
              if (isCustomer) const DataColumn(label: Text('Credit limit'), numeric: true),
              const DataColumn(label: Text('Balance owed'), numeric: true),
              const DataColumn(label: Text('Status')),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final party in owing)
                DataRow(
                  onSelectChanged: (_) => showDialog(
                    context: context,
                    builder: (_) => PartyHistoryDialog(party: party),
                  ),
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(party.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    DataCell(Text((isCustomer ? party.phone : party.contactPerson) ?? '—')),
                    if (isCustomer)
                      DataCell(Text(party.creditLimit > 0 ? currencyFormat.format(party.creditLimit) : '—')),
                    DataCell(Text(currencyFormat.format(party.balanceOwed))),
                    DataCell(
                      party.isAtCreditLimit
                          ? const StatusPill(label: 'At limit', tone: StatusTone.negative)
                          : const StatusPill(label: 'Owing', tone: StatusTone.warning),
                    ),
                    DataCell(
                      Tooltip(
                        message: canRecord ? '' : "Your role can't record payments",
                        child: TextButton(
                          onPressed: !canRecord
                              ? null
                              : () => showDialog(
                                    context: context,
                                    builder: (_) => CreditEntryDialog(party: party, kind: CreditKind.payment),
                                  ),
                          child: const Text('Record payment'),
                        ),
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

class _Message extends StatelessWidget {
  const _Message(this.message);

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
