import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../parties/presentation/party_form_dialog.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';
import '../data/customer_types.dart';
import 'customer_actions.dart';
import 'customer_import_dialog.dart';
import 'customer_types_dialog.dart';

enum _Show { all, owing, atLimit, clear, archived }

extension on _Show {
  String get label => switch (this) {
        _Show.all => 'All',
        _Show.owing => 'Owing',
        _Show.atLimit => 'At limit',
        _Show.clear => 'Clear',
        _Show.archived => 'Archived',
      };

  bool matches(Party c) => switch (this) {
        _Show.all => c.isActive,
        _Show.owing => c.isActive && c.balanceOwed > 0,
        _Show.atLimit => c.isActive && c.isAtCreditLimit,
        _Show.clear => c.isActive && c.balanceOwed <= 0,
        _Show.archived => !c.isActive,
      };
}

/// "No type" in the type filter.
const _untyped = '';

/// Customers from the server: how many, what they owe and what they bought
/// this month, searchable and filtered by type and standing (archived ones
/// can be restored). A row opens the customer's page. Owners and
/// Administrators manage the types; customers can be imported from and
/// exported to Excel.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  _Show _show = _Show.all;
  String? _typeId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRead = hasPermission(ref, Permissions.customersView);
    final canCreate = hasPermission(ref, Permissions.customersCreate);
    final canEdit = hasPermission(ref, Permissions.customersEdit);
    final canArchive = hasPermission(ref, Permissions.customersArchive);
    final canManageTypes = hasPermission(ref, Permissions.customersTypes);
    final canSeeSales = hasPermission(ref, Permissions.salesView);
    final state = ref.watch(partiesProvider(PartyType.customer));
    final all = ref.watch(partyListProvider(PartyType.customer));
    final types = ref.watch(customerTypesProvider).valueOrNull ?? const <CustomerType>[];

    final active = all.where((c) => c.isActive).toList();
    final owed = active.fold(0.0, (t, c) => t + (c.balanceOwed > 0 ? c.balanceOwed : 0));
    final owing = active.where((c) => c.balanceOwed > 0).length;
    final atLimit = active.where((c) => c.isAtCreditLimit).length;
    final now = DateTime.now();
    final monthSales = (ref.watch(salesProvider).valueOrNull ?? const <Sale>[]).where(
      (s) => !s.isVoided && !s.isWalkIn && s.saleDate.year == now.year && s.saleDate.month == now.month,
    );
    final soldThisMonth = monthSales.fold(0.0, (t, s) => t + s.total);
    final buyersThisMonth = monthSales.map((s) => s.customerId).toSet().length;

    final query = _search.text.trim().toLowerCase();
    final rows = all
        .where(_show.matches)
        .where((c) => _typeId == null || (c.customerTypeId ?? _untyped) == _typeId)
        .where(
          (c) =>
              query.isEmpty ||
              c.name.toLowerCase().contains(query) ||
              (c.phone ?? '').toLowerCase().contains(query) ||
              (c.email ?? '').toLowerCase().contains(query),
        )
        .toList();

    Widget body;
    if (!canRead) {
      body = const Card(
        child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text("Your role can't view customers."))),
      );
    } else if (state.isLoading && !state.hasValue) {
      body = const LoadingPanel(label: 'Loading customers…');
    } else if (state.hasError && !state.hasValue) {
      body = ErrorRetryCard(
        error: state.error!,
        onRetry: () => ref.read(partiesProvider(PartyType.customer).notifier).refresh(),
      );
    } else if (rows.isEmpty) {
      body = Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              all.isEmpty
                  ? 'No customers yet.${canCreate ? ' Use "Add customer", or import them from Excel.' : ''}'
                  : 'No customers match.',
            ),
          ),
        ),
      );
    } else {
      body = Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(theme.colorScheme.onSurface.withValues(alpha: 0.03)),
            columns: const [
              DataColumn(label: Text('Customer')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Phone')),
              DataColumn(label: Text('Credit limit'), numeric: true),
              DataColumn(label: Text('Owes you'), numeric: true),
              DataColumn(label: Text('Bought'), numeric: true),
              DataColumn(label: Text('Last purchase')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final c in rows)
                DataRow(
                  key: ValueKey('customer-row-${c.id}'),
                  onSelectChanged: (_) => context.go('/customers/${c.id}'),
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    DataCell(Text(ref.watch(customerTypeNameProvider(c)) ?? '—')),
                    DataCell(Text(c.phone ?? '—')),
                    DataCell(Text(c.creditLimit > 0 ? currencyFormat.format(c.creditLimit) : '—')),
                    DataCell(Text(currencyFormat.format(c.balanceOwed))),
                    DataCell(Text(c.totalSales > 0 ? currencyFormat.format(c.totalSales) : '—')),
                    DataCell(Text(c.lastSaleAt == null ? '—' : dateFormat.format(c.lastSaleAt!))),
                    DataCell(customerStatusPill(c)),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (c.isActive) ...[
                            IconButton(
                              tooltip: canEdit ? 'Edit' : "Your role can't edit customers",
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: canEdit
                                  ? () => showDialog(
                                        context: context,
                                        builder: (_) => PartyFormDialog(type: PartyType.customer, party: c),
                                      )
                                  : null,
                            ),
                            IconButton(
                              key: ValueKey('customer-archive-${c.id}'),
                              tooltip: canArchive ? 'Archive' : "Your role can't archive customers",
                              icon: const Icon(Icons.archive_outlined, size: 18),
                              onPressed: canArchive ? () => archiveCustomer(context, ref, c) : null,
                            ),
                          ] else
                            TextButton.icon(
                              key: ValueKey('customer-restore-${c.id}'),
                              onPressed: canArchive ? () => restoreCustomer(context, ref, c) : null,
                              icon: const Icon(Icons.unarchive_outlined, size: 18),
                              label: const Text('Restore'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Customers',
              subtitle: canRead
                  ? '${active.length} active · open a customer for their sales and account'
                  : 'Not available for your role',
              actions: [
                if (canManageTypes)
                  OutlinedButton.icon(
                    key: const Key('customers-types'),
                    onPressed: () => showDialog(context: context, builder: (_) => const CustomerTypesDialog()),
                    icon: const Icon(Icons.label_outline, size: 18),
                    label: const Text('Types'),
                  ),
                if (canRead)
                  OutlinedButton.icon(
                    key: const Key('customers-export'),
                    onPressed: rows.isEmpty ? null : () => exportCustomers(context, ref, rows),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                if (canCreate)
                  OutlinedButton.icon(
                    key: const Key('customers-import'),
                    onPressed: () => showDialog(context: context, builder: (_) => const CustomerImportDialog()),
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Import'),
                  ),
                Tooltip(
                  message: canCreate ? '' : "Your role can't add customers",
                  child: ElevatedButton.icon(
                    key: const Key('customers-add'),
                    onPressed: canCreate
                        ? () => showDialog(context: context, builder: (_) => const PartyFormDialog(type: PartyType.customer))
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add customer'),
                  ),
                ),
              ],
            ),
            if (canRead) ...[
              const SizedBox(height: 18),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisExtent: 156,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                children: [
                  StatCard(
                    key: const Key('customers-stat-count'),
                    label: 'Customers',
                    value: '${active.length}',
                    caption: '$owing owing you',
                    icon: Icons.people_alt_outlined,
                  ),
                  StatCard(
                    key: const Key('customers-stat-owed'),
                    label: 'Owed to you',
                    value: currencyFormat.format(owed),
                    caption: 'By active customers',
                    icon: Icons.account_balance_wallet_outlined,
                    accentColor: owed > 0 ? theme.colorScheme.error : null,
                  ),
                  StatCard(
                    key: const Key('customers-stat-limit'),
                    label: 'At their limit',
                    value: '$atLimit',
                    caption: 'Credit sales to them are blocked',
                    icon: Icons.block_outlined,
                    accentColor: atLimit > 0 ? const Color(0xFFB7791F) : null,
                  ),
                  if (canSeeSales)
                    StatCard(
                      key: const Key('customers-stat-month'),
                      label: 'Sold to customers this month',
                      value: currencyFormat.format(soldThisMonth),
                      caption: '$buyersThisMonth customer${buyersThisMonth == 1 ? '' : 's'} bought',
                      icon: Icons.point_of_sale_outlined,
                      accentColor: const Color(0xFF2F8F5B),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<_Show>(
                    key: const Key('customers-show'),
                    showSelectedIcon: false,
                    segments: [for (final s in _Show.values) ButtonSegment(value: s, label: Text(s.label))],
                    selected: {_show},
                    onSelectionChanged: (s) => setState(() => _show = s.first),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('customers-type-filter'),
                      initialValue: _typeId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.label_outline, size: 18)),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All types')),
                        for (final t in types) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                        const DropdownMenuItem<String?>(value: _untyped, child: Text('No type')),
                      ],
                      onChanged: (v) => setState(() => _typeId = v),
                    ),
                  ),
                  ToolbarSearchField(
                    controller: _search,
                    hintText: 'Search name, phone or email…',
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 20),
            body,
          ],
        ),
      ),
    );
  }
}
