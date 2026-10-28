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
import '../../parties/presentation/credit_entry_row.dart';
import '../../products/data/products_repository.dart';
import '../../purchases/data/purchases_repository.dart';
import '../../purchases/data/reorder.dart';
import '../../purchases/domain/purchase.dart';
import '../../purchases/presentation/purchase_detail_dialog.dart';
import '../../purchases/presentation/purchase_form_dialog.dart';
import '../../purchases/presentation/reorder_dialog.dart';
import '../data/supplier_prices.dart';
import 'supplier_actions.dart';

enum _Tab { purchases, prices, account }

/// One supplier: contacts and terms, what you owe them and what is overdue,
/// what you have bought from them, and three tabs — their purchases, the
/// products they supply with what each has cost, and the account history.
/// New purchase, Record payment, Statement, Edit and Archive/Restore work from
/// here, and products of theirs at the reorder level can be ordered.
class SupplierProfileScreen extends ConsumerStatefulWidget {
  const SupplierProfileScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  ConsumerState<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends ConsumerState<SupplierProfileScreen> {
  late _Tab _tab = hasPermission(ref, Permissions.purchasesView) ? _Tab.purchases : _Tab.prices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final state = ref.watch(partiesProvider(PartyType.supplier));
    final s = ref.watch(partyListProvider(PartyType.supplier)).where((p) => p.id == widget.supplierId).firstOrNull;

    final backButton = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('supplier-back'),
        onPressed: () => context.go('/suppliers'),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Suppliers'),
      ),
    );

    if (s == null) {
      return Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              backButton,
              const SizedBox(height: 16),
              if (state.isLoading && !state.hasValue)
                const LoadingPanel(label: 'Loading supplier…')
              else if (state.hasError && !state.hasValue)
                ErrorRetryCard(
                  error: state.error!,
                  onRetry: () => ref.read(partiesProvider(PartyType.supplier).notifier).refresh(),
                )
              else
                const Card(
                  child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('This supplier was not found.'))),
                ),
            ],
          ),
        ),
      );
    }

    final canOrder = hasPermission(ref, Permissions.purchasesCreate) && s.isActive;
    final canSeePurchases = hasPermission(ref, Permissions.purchasesView);
    final canRecord = hasPermission(ref, Permissions.creditRecord);
    final canEdit = hasPermission(ref, Permissions.suppliersEdit) && s.isActive;
    final canArchive = hasPermission(ref, Permissions.suppliersArchive);
    final toReorder = ref
        .watch(reorderGroupsProvider)
        .where((g) => g.supplierId == s.id)
        .fold(0, (n, g) => n + g.lines.length);

    void entry(CreditKind kind) => recordCreditEntry(context, ref, s, kind);

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
                Text(s.name, key: const Key('supplier-name'), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                supplierStatusPill(s),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (s.contactPerson != null) 'Attn: ${s.contactPerson}',
                ?s.phone,
                ?s.email,
                ?s.address,
              ].join('  ·  '),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            if (s.notes != null) ...[
              const SizedBox(height: 4),
              Text(s.notes!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canOrder)
                  ElevatedButton.icon(
                    key: const Key('supplier-new-purchase'),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => PurchaseFormDialog(initialSupplierId: s.id),
                    ),
                    icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                    label: const Text('New purchase'),
                  ),
                if (canOrder && toReorder > 0)
                  OutlinedButton.icon(
                    key: const Key('supplier-reorder'),
                    onPressed: () => showDialog(context: context, builder: (_) => ReorderDialog(supplierId: s.id)),
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: Text('Reorder ($toReorder low)'),
                  ),
                if (canRecord)
                  OutlinedButton.icon(
                    key: const Key('supplier-record-payment'),
                    onPressed: s.balanceOwed > 0 ? () => entry(CreditKind.payment) : null,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Record payment'),
                  ),
                if (!s.isPending)
                  OutlinedButton.icon(
                    key: const Key('supplier-statement'),
                    onPressed: () => showDialog(context: context, builder: (_) => StatementDialog(party: s)),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Statement'),
                  ),
                if (canEdit)
                  OutlinedButton.icon(
                    key: const Key('supplier-edit'),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => PartyFormDialog(type: PartyType.supplier, party: s),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                if (canArchive && s.isActive)
                  TextButton.icon(
                    key: const Key('supplier-archive'),
                    onPressed: () => archiveSupplier(context, ref, s),
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Archive'),
                  ),
                if (canArchive && !s.isActive)
                  OutlinedButton.icon(
                    key: const Key('supplier-restore'),
                    onPressed: () => restoreSupplier(context, ref, s),
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
                  key: const Key('supplier-stat-owe'),
                  label: 'You owe',
                  value: currencyFormat.format(s.balanceOwed),
                  caption: s.overdue > 0 ? '${currencyFormat.format(s.overdue)} overdue' : 'Nothing overdue',
                  icon: Icons.account_balance_wallet_outlined,
                  accentColor: s.overdue > 0 ? theme.colorScheme.error : null,
                ),
                StatCard(
                  key: const Key('supplier-stat-bought'),
                  label: 'Bought (all time)',
                  value: currencyFormat.format(s.totalPurchases),
                  caption: '${s.purchaseCount} purchase${s.purchaseCount == 1 ? '' : 's'}',
                  icon: Icons.shopping_cart_outlined,
                  accentColor: const Color(0xFF2F8F5B),
                ),
                StatCard(
                  label: 'Last purchase',
                  value: s.lastPurchaseAt == null ? 'Never' : dateFormat.format(s.lastPurchaseAt!),
                  caption: toReorder > 0 ? '$toReorder of their products at reorder level' : 'Nothing to reorder',
                  icon: Icons.event_outlined,
                ),
                StatCard(
                  label: 'Payment terms',
                  value: '${s.paymentTermsDays} days',
                  caption: 'After each delivery',
                  icon: Icons.schedule_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_Tab>(
                key: const Key('supplier-tabs'),
                showSelectedIcon: false,
                segments: [
                  if (canSeePurchases) const ButtonSegment(value: _Tab.purchases, label: Text('Purchases')),
                  const ButtonSegment(value: _Tab.prices, label: Text('Products & prices')),
                  const ButtonSegment(value: _Tab.account, label: Text('Account history')),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
            ),
            const SizedBox(height: 12),
            switch (_tab) {
              _Tab.purchases when canSeePurchases => _PurchasesTab(supplier: s),
              _Tab.account => _AccountTab(supplier: s, canRecord: canRecord, onEntry: entry),
              _ => _PricesTab(supplier: s),
            },
          ],
        ),
      ),
    );
  }
}

class _PurchasesTab extends ConsumerWidget {
  const _PurchasesTab({required this.supplier});

  final Party supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(supplierPurchaseHistoryProvider(supplier.id));
    if (state.isLoading && !state.hasValue) return const LoadingPanel(label: 'Loading purchases…');
    if (state.hasError && !state.hasValue) {
      return ErrorRetryCard(error: state.error!, onRetry: () => ref.invalidate(supplierPurchaseHistoryProvider(supplier.id)));
    }
    final purchases = state.valueOrNull ?? const <Purchase>[];
    if (purchases.isEmpty) {
      return const Card(child: Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No purchases from this supplier yet.'))));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.all(theme.colorScheme.onSurface.withValues(alpha: 0.03)),
          columns: const [
            DataColumn(label: Text('PO')),
            DataColumn(label: Text('Ordered')),
            DataColumn(label: Text('Warehouse')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Arrived'), numeric: true),
            DataColumn(label: Text('Total'), numeric: true),
            DataColumn(label: Text('Payment')),
          ],
          rows: [
            for (final p in purchases)
              DataRow(
                key: ValueKey('supplier-purchase-${p.id}'),
                onSelectChanged: (_) => showDialog(context: context, builder: (_) => PurchaseDetailDialog(purchaseId: p.id)),
                cells: [
                  DataCell(Text(p.reference, style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text(dateFormat.format(p.orderDate))),
                  DataCell(Text(p.warehouseName)),
                  DataCell(purchaseStatusPill(p.status)),
                  DataCell(Text('${p.unitsReceived} / ${p.unitsOrdered}')),
                  DataCell(Text(currencyFormat.format(p.total))),
                  DataCell(purchasePaymentPill(p)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The products this supplier provides: those that list them as usual
/// supplier and those bought from them, with the last price, the change from
/// the one before, and the price history.
class _PricesTab extends ConsumerWidget {
  const _PricesTab({required this.supplier});

  final Party supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final state = ref.watch(supplierPricesProvider(supplier.id));
    final prices = state.valueOrNull ?? const <SupplierProductPrice>[];
    final priced = {for (final p in prices) p.productId};
    final linkedOnly = ref
        .watch(productListProvider)
        .where((p) => p.supplierId == supplier.id && !p.isArchived && !priced.contains(p.id))
        .toList();

    if (state.isLoading && !state.hasValue) return const LoadingPanel(label: 'Loading prices…');
    if (state.hasError && !state.hasValue) {
      return ErrorRetryCard(error: state.error!, onRetry: () => ref.invalidate(supplierPricesProvider(supplier.id)));
    }
    if (prices.isEmpty && linkedOnly.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: Text('Nothing bought from this supplier yet, and no product lists them as its supplier.')),
        ),
      );
    }

    Widget change(SupplierProductPrice p) {
      if (p.change == null) return Text('—', style: muted);
      final color = p.wentUp ? theme.colorScheme.error : (p.wentDown ? const Color(0xFF2F8F5B) : null);
      final sign = p.wentUp ? '+' : (p.wentDown ? '−' : '');
      return Text(
        '$sign${currencyFormat.format(p.change!.abs())}${p.changePercent == null ? '' : ' ($sign${p.changePercent!.abs().toStringAsFixed(1)}%)'}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          headingRowColor: WidgetStateProperty.all(theme.colorScheme.onSurface.withValues(alpha: 0.03)),
          columns: const [
            DataColumn(label: Text('Product')),
            DataColumn(label: Text('Last cost'), numeric: true),
            DataColumn(label: Text('Change')),
            DataColumn(label: Text('Last bought')),
            DataColumn(label: Text('Times'), numeric: true),
            DataColumn(label: Text('Cost now'), numeric: true),
          ],
          rows: [
            for (final p in prices)
              DataRow(
                key: ValueKey('supplier-price-${p.productId}'),
                onSelectChanged: (_) => showDialog(context: context, builder: (_) => _PriceHistoryDialog(price: p)),
                cells: [
                  DataCell(Text('${p.name} · ${p.sku}')),
                  DataCell(Text(currencyFormat.format(p.lastCost))),
                  DataCell(change(p)),
                  DataCell(Text('${dateFormat.format(p.lastDate)} · ${p.lastReference}')),
                  DataCell(Text('${p.timesBought}')),
                  DataCell(Text(currencyFormat.format(p.currentCost))),
                ],
              ),
            for (final p in linkedOnly)
              DataRow(
                key: ValueKey('supplier-linked-${p.id}'),
                cells: [
                  DataCell(Text('${p.name} · ${p.sku}')),
                  const DataCell(Text('—')),
                  const DataCell(Text('—')),
                  DataCell(Text('Not bought from them yet', style: muted)),
                  const DataCell(Text('0')),
                  DataCell(Text(currencyFormat.format(p.purchasePrice))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PriceHistoryDialog extends StatelessWidget {
  const _PriceHistoryDialog({required this.price});

  final SupplierProductPrice price;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${price.name} — price history'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
              columnSpacing: 24,
              headingRowHeight: 34,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 38,
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('PO')),
                DataColumn(label: Text('Qty'), numeric: true),
                DataColumn(label: Text('Unit cost'), numeric: true),
              ],
              rows: [
                for (final h in price.history)
                  DataRow(
                    cells: [
                      DataCell(Text(dateFormat.format(h.date))),
                      DataCell(Text(h.reference)),
                      DataCell(Text('${h.quantity} ${price.unit}')),
                      DataCell(Text(currencyFormat.format(h.unitCost))),
                    ],
                  ),
              ],
            ),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
}

class _AccountTab extends ConsumerWidget {
  const _AccountTab({required this.supplier, required this.canRecord, required this.onEntry});

  final Party supplier;
  final bool canRecord;
  final void Function(CreditKind) onEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = (type: PartyType.supplier, id: supplier.id);
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
                    key: const Key('supplier-add-invoice'),
                    onPressed: supplier.isActive ? () => onEntry(CreditKind.charge) : null,
                    child: const Text('Add invoice'),
                  ),
                  TextButton(
                    key: const Key('supplier-adjust'),
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
              for (final e in entries) CreditEntryRow(entry: e, myId: myId, theme: theme, party: supplier),
          ],
        ),
      ),
    );
  }
}

