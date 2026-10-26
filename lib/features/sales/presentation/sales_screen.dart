import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/offline/outbox.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import 'sale_detail_dialog.dart';

enum _Period { today, week, month, all }

extension on _Period {
  String get label => switch (this) {
        _Period.today => 'Today',
        _Period.week => 'This week',
        _Period.month => 'This month',
        _Period.all => 'All',
      };

  DateTime? start(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Period.today => today,
      _Period.week => today.subtract(Duration(days: today.weekday - 1)),
      _Period.month => DateTime(now.year, now.month),
      _Period.all => null,
    };
  }
}

enum _Show { all, unpaid, voided }

extension on _Show {
  String get label => switch (this) {
        _Show.all => 'All',
        _Show.unpaid => 'Unpaid',
        _Show.voided => 'Voided',
      };

  bool matches(Sale s) => switch (this) {
        _Show.all => true,
        _Show.unpaid => !s.isVoided && s.balance > 0.004,
        _Show.voided => s.isVoided,
      };
}

/// Sales, from the server: what was sold today and this month, what
/// customers still owe on them, and every sale with its payment standing.
/// Opening one shows its lines and payments, with Print invoice, Record
/// payment and Void.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _search = TextEditingController();
  _Period _period = _Period.today;
  _Show _show = _Show.all;
  String? _customerId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Sale s) => showDialog(context: context, builder: (_) => SaleDetailDialog(saleId: s.id));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(salesProvider);
    final all = state.valueOrNull ?? const <Sale>[];
    final queued = ref.watch(outboxOpsProvider).where((o) => o.kind == OpKind.saleCreate && !o.failed).toList();
    final canCreate = hasPermission(ref, Permissions.salesCreate);
    final customers = hasPermission(ref, Permissions.customersView)
        ? ref.watch(partyListProvider(PartyType.customer))
        : const <Party>[];
    final customerName = {for (final c in customers) c.id: c.name};

    final now = DateTime.now();
    final live = all.where((s) => !s.isVoided).toList();
    double soldSince(DateTime from) => live.where((s) => !s.saleDate.isBefore(from)).fold(0.0, (t, s) => t + s.total);
    final today = _Period.today.start(now)!;
    final todayCount = live.where((s) => !s.saleDate.isBefore(today)).length;
    final owed = live.fold(0.0, (t, s) => t + s.balance);
    final unpaidCount = live.where((s) => s.balance > 0.004).length;

    final from = _period.start(now);
    final query = _search.text.trim().toLowerCase();
    final rows = all
        .where((s) => from == null || !s.saleDate.isBefore(from))
        .where(_show.matches)
        .where((s) => _customerId == null || s.customerId == _customerId)
        .where(
          (s) =>
              query.isEmpty ||
              s.reference.toLowerCase().contains(query) ||
              s.customerName.toLowerCase().contains(query) ||
              s.lines.any((l) => l.productName.toLowerCase().contains(query) || l.sku.toLowerCase().contains(query)),
        )
        .toList();
    final shownTotal = rows.where((s) => !s.isVoided).fold(0.0, (t, s) => t + s.total);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Sales',
              subtitle: 'Stock leaves the warehouse as each sale is completed',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => ref.read(salesProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
                Tooltip(
                  message: canCreate ? '' : "Your role can't record sales",
                  child: ElevatedButton.icon(
                    key: const Key('sales-new'),
                    onPressed: canCreate ? () => recordSale(context, ref) : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New sale'),
                  ),
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
                  key: const Key('sales-stat-today'),
                  label: 'Sold today',
                  value: currencyFormat.format(soldSince(today)),
                  caption: '$todayCount sale${todayCount == 1 ? '' : 's'}',
                  icon: Icons.point_of_sale_outlined,
                  accentColor: const Color(0xFF2F8F5B),
                ),
                StatCard(
                  label: 'Sold this month',
                  value: currencyFormat.format(soldSince(_Period.month.start(now)!)),
                  caption: 'Voided sales not counted',
                  icon: Icons.calendar_month_outlined,
                ),
                StatCard(
                  key: const Key('sales-stat-owed'),
                  label: 'Owed on sales',
                  value: currencyFormat.format(owed),
                  caption: '$unpaidCount sale${unpaidCount == 1 ? '' : 's'} not fully paid',
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: owed > 0 ? theme.colorScheme.error : null,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<_Period>(
                  key: const Key('sales-period'),
                  showSelectedIcon: false,
                  segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label))],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.first),
                ),
                SegmentedButton<_Show>(
                  key: const Key('sales-show'),
                  showSelectedIcon: false,
                  segments: [for (final f in _Show.values) ButtonSegment(value: f, label: Text(f.label))],
                  selected: {_show},
                  onSelectionChanged: (s) => setState(() => _show = s.first),
                ),
                if (customers.isNotEmpty)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.person_outline, size: 18)),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All customers')),
                        for (final c in customers)
                          DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _customerId = v),
                    ),
                  ),
                ToolbarSearchField(
                  controller: _search,
                  hintText: 'Search invoice, customer or product…',
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${rows.length} sale${rows.length == 1 ? '' : 's'} · ${currencyFormat.format(shownTotal)}',
              key: const Key('sales-shown-summary'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 8),
            if (state.isLoading && !state.hasValue)
              const LoadingPanel(label: 'Loading sales…')
            else if (state.hasError && !state.hasValue)
              ErrorRetryCard(error: state.error!, onRetry: () => ref.read(salesProvider.notifier).refresh())
            else if (rows.isEmpty && queued.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      all.isEmpty
                          ? 'No sales yet.${canCreate ? ' Use "New sale" to record one.' : ''}'
                          : 'No sales match.',
                    ),
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(theme.colorScheme.onSurface.withValues(alpha: 0.03)),
                    columns: const [
                      DataColumn(label: Text('Invoice')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Customer')),
                      DataColumn(label: Text('Warehouse')),
                      DataColumn(label: Text('Units'), numeric: true),
                      DataColumn(label: Text('Total'), numeric: true),
                      DataColumn(label: Text('Still due'), numeric: true),
                      DataColumn(label: Text('Payment')),
                    ],
                    rows: [
                      for (final op in queued) _queuedRow(op, customerName),
                      for (final s in rows)
                        DataRow(
                          key: ValueKey('sale-row-${s.id}'),
                          onSelectChanged: (_) => _open(s),
                          cells: [
                            DataCell(Text(s.reference, style: const TextStyle(fontWeight: FontWeight.w700))),
                            DataCell(Text(dateTimeFormat.format(s.saleDate))),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(s.customerName, overflow: TextOverflow.ellipsis),
                              ),
                            ),
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
              ),
          ],
        ),
      ),
    );
  }

  DataRow _queuedRow(OutboxOp op, Map<String, String> customerName) {
    final input = SaleInput.fromJson(Map<String, dynamic>.from(op.payload['input'] as Map));
    final units = input.lines.fold(0, (s, l) => s + l.quantity);
    return DataRow(
      key: ValueKey('sale-queued-${op.id}'),
      cells: [
        const DataCell(Text('—')),
        DataCell(Text(dateTimeFormat.format(op.createdAt))),
        DataCell(
          Text(input.customerId == null ? 'Walk-in customer' : customerName[input.customerId] ?? 'Customer'),
        ),
        const DataCell(Text('')),
        DataCell(Text('$units')),
        DataCell(Text(currencyFormat.format(input.total))),
        DataCell(Text(input.unpaid > 0.004 ? currencyFormat.format(input.unpaid) : '—')),
        const DataCell(StatusPill(label: 'Waiting to sync', tone: StatusTone.neutral)),
      ],
    );
  }
}
