import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../documents/statement_dialog.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../parties/presentation/credit_entry_dialog.dart';
import '../../parties/presentation/party_form_dialog.dart';
import '../../parties/presentation/party_history_dialog.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/sale_detail_dialog.dart';
import '../data/customer_types.dart';
import 'customer_actions.dart';

enum _Tab { sales, account }

/// One customer: contact details and type, what they owe and can still buy
/// on credit, what they have bought, and two tabs — their sales and their
/// account (every charge, payment and adjustment). New sale, Record payment,
/// Statement, Edit and Archive/Restore work from here.
class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  late _Tab _tab = hasPermission(ref, Permissions.salesView) ? _Tab.sales : _Tab.account;

  void _back() => context.go('/customers');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final state = ref.watch(partiesProvider(PartyType.customer));
    final c = ref.watch(partyListProvider(PartyType.customer)).where((p) => p.id == widget.customerId).firstOrNull;

    final backButton = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('customer-back'),
        onPressed: _back,
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Customers'),
      ),
    );

    if (c == null) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              backButton,
              const SizedBox(height: 16),
              if (state.isLoading && !state.hasValue)
                const LoadingPanel(label: 'Loading customer…')
              else if (state.hasError && !state.hasValue)
                ErrorRetryCard(
                  error: state.error!,
                  onRetry: () => ref.read(partiesProvider(PartyType.customer).notifier).refresh(),
                )
              else
                const Card(
                  child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('This customer was not found.'))),
                ),
            ],
          ),
        ),
      );
    }

    final canSell = hasPermission(ref, Permissions.salesCreate) && c.isActive;
    final canRecord = hasPermission(ref, Permissions.creditRecord);
    final canEdit = hasPermission(ref, Permissions.customersEdit) && c.isActive;
    final canArchive = hasPermission(ref, Permissions.customersArchive);
    final canSeeSales = hasPermission(ref, Permissions.salesView);
    final typeName = ref.watch(customerTypeNameProvider(c));
    final left = c.creditLeft;

    void entry(CreditKind kind) =>
        showDialog(context: context, builder: (_) => CreditEntryDialog(party: c, kind: kind));

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            backButton,
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(c.name, key: const Key('customer-name'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (typeName != null)
                  Chip(
                    key: const Key('customer-type-chip'),
                    label: Text(typeName),
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.label_outline, size: 16),
                  ),
                customerStatusPill(c),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                c.phone,
                c.email,
                c.address,
              ].whereType<String>().join('  ·  ').ifEmpty('No contact details'),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            if (c.notes != null) ...[
              const SizedBox(height: 4),
              Text(c.notes!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canSell)
                  ElevatedButton.icon(
                    key: const Key('customer-new-sale'),
                    onPressed: () => recordSale(context, ref, customerId: c.id),
                    icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                    label: const Text('New sale'),
                  ),
                if (canRecord)
                  OutlinedButton.icon(
                    key: const Key('customer-record-payment'),
                    onPressed: c.balanceOwed > 0 ? () => entry(CreditKind.payment) : null,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Record payment'),
                  ),
                if (!c.isPending)
                  OutlinedButton.icon(
                    key: const Key('customer-statement'),
                    onPressed: () => showDialog(context: context, builder: (_) => StatementDialog(party: c)),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Statement'),
                  ),
                if (canEdit)
                  OutlinedButton.icon(
                    key: const Key('customer-edit'),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => PartyFormDialog(type: PartyType.customer, party: c),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                if (canArchive && c.isActive)
                  TextButton.icon(
                    key: const Key('customer-archive'),
                    onPressed: () => archiveCustomer(context, ref, c),
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Archive'),
                  ),
                if (canArchive && !c.isActive)
                  OutlinedButton.icon(
                    key: const Key('customer-restore'),
                    onPressed: () => restoreCustomer(context, ref, c),
                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                    label: const Text('Restore'),
                  ),
              ],
            ),
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
                  key: const Key('customer-stat-owes'),
                  label: 'Owes you',
                  value: currencyFormat.format(c.balanceOwed),
                  caption: left == null
                      ? 'No credit limit set'
                      : left <= 0
                          ? 'At their limit of ${currencyFormat.format(c.creditLimit)}'
                          : '${currencyFormat.format(left)} of credit left',
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: c.isAtCreditLimit ? theme.colorScheme.error : (c.balanceOwed > 0 ? const Color(0xFFB7791F) : null),
                ),
                StatCard(
                  key: const Key('customer-stat-bought'),
                  label: 'Bought (all time)',
                  value: currencyFormat.format(c.totalSales),
                  caption: '${c.salesCount} sale${c.salesCount == 1 ? '' : 's'}',
                  icon: Icons.shopping_bag_outlined,
                  accentColor: const Color(0xFF2F8F5B),
                ),
                StatCard(
                  key: const Key('customer-stat-last'),
                  label: 'Last purchase',
                  value: c.lastSaleAt == null ? 'Never' : dateFormat.format(c.lastSaleAt!),
                  caption: c.lastSaleAt == null ? 'No sales yet' : _ago(c.lastSaleAt!),
                  icon: Icons.event_outlined,
                ),
                StatCard(
                  label: 'Credit limit',
                  value: c.creditLimit > 0 ? currencyFormat.format(c.creditLimit) : 'None',
                  caption: typeName == null ? 'No type' : 'Type: $typeName',
                  icon: Icons.speed_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_Tab>(
                key: const Key('customer-tabs'),
                showSelectedIcon: false,
                segments: [
                  if (canSeeSales) const ButtonSegment(value: _Tab.sales, label: Text('Sales')),
                  const ButtonSegment(value: _Tab.account, label: Text('Account history')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 12),
            if (_tab == _Tab.sales && canSeeSales)
              _SalesTab(customer: c)
            else
              _AccountTab(customer: c, canRecord: canRecord, onEntry: entry),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime at) {
    final days = DateTime.now().difference(at).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 60) return '$days days ago';
    return '${(days / 30).floor()} months ago';
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _SalesTab extends ConsumerWidget {
  const _SalesTab({required this.customer});

  final Party customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(customerSaleHistoryProvider(customer.id));
    if (state.isLoading && !state.hasValue) return const LoadingPanel(label: 'Loading sales…');
    if (state.hasError && !state.hasValue) {
      return ErrorRetryCard(error: state.error!, onRetry: () => ref.invalidate(customerSaleHistoryProvider(customer.id)));
    }
    final sales = state.valueOrNull ?? const <Sale>[];
    if (sales.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No sales to this customer yet.'))));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.all(theme.colorScheme.onSurface.withValues(alpha: 0.03)),
          columns: const [
            DataColumn(label: Text('Invoice')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Warehouse')),
            DataColumn(label: Text('Units'), numeric: true),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(label: Text('Still due'), numeric: true),
            DataColumn(label: Text('Payment')),
          ],
          rows: [
            for (final s in sales)
              DataRow(
                key: ValueKey('customer-sale-${s.id}'),
                onSelectChanged: (_) => showDialog(context: context, builder: (_) => SaleDetailDialog(saleId: s.id)),
                cells: [
                  DataCell(Text(s.reference, style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text(dateTimeFormat.format(s.saleDate))),
                  DataCell(Text(s.warehouseName)),
                  DataCell(Text('${s.units}')),
                  DataCell(
                    Text(
                      currencyFormat.format(s.total),
                      style: s.isVoided ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                    ),
                  ),
                  DataCell(Text(s.balance > 0.004 ? currencyFormat.format(s.balance) : '—')),
                  DataCell(salePaymentPill(s)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountTab extends ConsumerWidget {
  const _AccountTab({required this.customer, required this.canRecord, required this.onEntry});

  final Party customer;
  final bool canRecord;
  final void Function(CreditKind) onEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = (type: PartyType.customer, id: customer.id);
    final state = ref.watch(creditEntriesProvider(key));
    final entries = ref.watch(creditLedgerProvider(key));
    final myId = ref.watch(sessionUserIdProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canRecord)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('customer-add-charge'),
                    onPressed: customer.isActive ? () => onEntry(CreditKind.charge) : null,
                    child: const Text('Add charge'),
                  ),
                  TextButton(
                    key: const Key('customer-adjust'),
                    onPressed: () => onEntry(CreditKind.adjustment),
                    child: const Text('Adjust balance'),
                  ),
                ],
              ),
            if (state.isLoading && !state.hasValue && entries.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
            else if (state.hasError && !state.hasValue && entries.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(friendlyError(state.error!)))
            else if (entries.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 12), child: Text('Nothing on their account yet.'))
            else
              for (final e in entries) CreditEntryRow(entry: e, myId: myId, theme: theme),
          ],
        ),
      ),
    );
  }
}
