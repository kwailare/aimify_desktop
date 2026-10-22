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
import '../../parties/data/supplier_options.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';
import 'import_legacy_purchases_dialog.dart';
import 'purchase_detail_dialog.dart';
import 'purchase_form_dialog.dart';

enum _Filter { open, received, cancelled, all }

extension on _Filter {
  String get label => switch (this) {
    _Filter.open => 'Open',
    _Filter.received => 'Received',
    _Filter.cancelled => 'Cancelled',
    _Filter.all => 'All',
  };

  bool matches(PurchaseStatus status) => switch (this) {
    _Filter.open => status.isOpen,
    _Filter.received => status == PurchaseStatus.received,
    _Filter.cancelled => status == PurchaseStatus.cancelled,
    _Filter.all => true,
  };
}

/// Purchases from suppliers, from the server: open orders first, what has
/// arrived and what is still owed. Opening one shows its lines, deliveries
/// and payments, with Receive, Pay, Edit and Cancel as its status allows.
class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.open;
  String? _supplierId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Purchase p) => showDialog(
    context: context,
    builder: (_) => PurchaseDetailDialog(purchaseId: p.id),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(purchasesProvider);
    final all = state.valueOrNull ?? const <Purchase>[];
    final queued = ref
        .watch(outboxOpsProvider)
        .where((o) => o.kind == OpKind.purchaseCreate && !o.failed)
        .toList();
    final legacy = ref.watch(legacyPurchasesProvider);
    final canCreate = hasPermission(ref, Permissions.purchasesCreate);
    final suppliers = ref.watch(supplierOptionsProvider).valueOrNull ?? const <SupplierOption>[];
    final supplierName = {for (final s in suppliers) s.id: s.name};

    final now = DateTime.now();
    final open = all.where((p) => p.status.isOpen).toList();
    final unitsAwaited = open.fold(0, (s, p) => s + p.unitsOrdered - p.unitsReceived);
    final owed = all
        .where((p) => p.status != PurchaseStatus.cancelled && p.postedAt != null)
        .fold(0.0, (s, p) => s + p.balance);
    final thisMonth = all
        .where(
          (p) =>
              p.status != PurchaseStatus.cancelled &&
              p.orderDate.year == now.year &&
              p.orderDate.month == now.month,
        )
        .fold(0.0, (s, p) => s + p.total);

    final query = _search.text.trim().toLowerCase();
    final rows = all
        .where((p) => _filter.matches(p.status))
        .where((p) => _supplierId == null || p.supplierId == _supplierId)
        .where(
          (p) =>
              query.isEmpty ||
              p.reference.toLowerCase().contains(query) ||
              p.supplierName.toLowerCase().contains(query) ||
              p.lines.any((l) => l.productName.toLowerCase().contains(query)),
        )
        .toList();

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Purchases',
              subtitle: '${open.length} open · goods arrive into stock when received',
              actions: [
                if (legacy.isNotEmpty && canCreate)
                  OutlinedButton.icon(
                    key: const Key('purchases-import-legacy'),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const ImportLegacyPurchasesDialog(),
                    ),
                    icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                    label: Text('Import ${legacy.length} saved on this computer'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => ref.read(purchasesProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
                Tooltip(
                  message: canCreate ? '' : "Your role can't record purchases",
                  child: ElevatedButton.icon(
                    key: const Key('purchases-new'),
                    onPressed: canCreate
                        ? () => showDialog(
                            context: context,
                            builder: (_) => const PurchaseFormDialog(),
                          )
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Record purchase'),
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
                  label: 'Open purchases',
                  value: '${open.length}',
                  caption: '$unitsAwaited unit${unitsAwaited == 1 ? '' : 's'} still to arrive',
                  icon: Icons.local_shipping_outlined,
                ),
                StatCard(
                  label: 'Owed to suppliers',
                  value: currencyFormat.format(owed),
                  caption: 'On purchases received so far',
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: owed > 0 ? theme.colorScheme.error : null,
                ),
                StatCard(
                  label: 'Bought this month',
                  value: currencyFormat.format(thisMonth),
                  caption: 'Purchases ordered this month',
                  icon: Icons.shopping_cart_outlined,
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
                SegmentedButton<_Filter>(
                  key: const Key('purchases-filter'),
                  showSelectedIcon: false,
                  segments: [
                    for (final f in _Filter.values) ButtonSegment(value: f, label: Text(f.label)),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.storefront_outlined, size: 18),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All suppliers')),
                      for (final s in suppliers)
                        DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                ),
                ToolbarSearchField(
                  controller: _search,
                  hintText: 'Search PO, supplier or product…',
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.isLoading && !state.hasValue)
              const LoadingPanel(label: 'Loading purchases…')
            else if (state.hasError && !state.hasValue)
              ErrorRetryCard(
                error: state.error!,
                onRetry: () => ref.read(purchasesProvider.notifier).refresh(),
              )
            else if (rows.isEmpty && queued.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      all.isEmpty
                          ? 'No purchases yet.${canCreate ? ' Use "Record purchase" to add one.' : ''}'
                          : 'No purchases match.',
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
                    headingRowColor: WidgetStateProperty.all(
                      theme.colorScheme.onSurface.withValues(alpha: 0.03),
                    ),
                    columns: const [
                      DataColumn(label: Text('PO')),
                      DataColumn(label: Text('Supplier')),
                      DataColumn(label: Text('Warehouse')),
                      DataColumn(label: Text('Ordered')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Arrived'), numeric: true),
                      DataColumn(label: Text('Total'), numeric: true),
                      DataColumn(label: Text('Payment')),
                    ],
                    rows: [
                      for (final op in queued) _queuedRow(op, supplierName),
                      for (final p in rows)
                        DataRow(
                          key: ValueKey('purchase-row-${p.id}'),
                          onSelectChanged: (_) => _open(p),
                          cells: [
                            DataCell(
                              Text(
                                p.reference,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(p.supplierName, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            DataCell(Text(p.warehouseName)),
                            DataCell(Text(dateFormat.format(p.orderDate))),
                            DataCell(purchaseStatusPill(p.status)),
                            DataCell(Text('${p.unitsReceived} / ${p.unitsOrdered}')),
                            DataCell(Text(currencyFormat.format(p.total))),
                            DataCell(purchasePaymentPill(p)),
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

  DataRow _queuedRow(OutboxOp op, Map<String, String> supplierName) {
    final input = PurchaseInput.fromJson(Map<String, dynamic>.from(op.payload['input'] as Map));
    return DataRow(
      key: ValueKey('purchase-queued-${op.id}'),
      cells: [
        const DataCell(Text('—')),
        DataCell(Text(supplierName[input.supplierId] ?? 'Supplier')),
        const DataCell(Text('')),
        DataCell(Text(dateFormat.format(input.orderDate))),
        const DataCell(StatusPill(label: 'Waiting to sync', tone: StatusTone.neutral)),
        DataCell(Text(input.receive ? '${input.lines.fold(0, (s, l) => s + l.quantity)}' : '0')),
        DataCell(Text(currencyFormat.format(input.total))),
        const DataCell(Text('')),
      ],
    );
  }
}
