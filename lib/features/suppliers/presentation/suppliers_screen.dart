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
import '../../customers/presentation/customer_import_dialog.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../parties/presentation/party_form_dialog.dart';
import '../../purchases/data/purchases_repository.dart';
import '../../purchases/data/reorder.dart';
import '../../purchases/domain/purchase.dart';
import '../../purchases/presentation/reorder_dialog.dart';
import 'supplier_actions.dart';

enum _Show { all, owing, overdue, settled, archived }

extension on _Show {
  String get label => switch (this) {
        _Show.all => 'All',
        _Show.owing => 'You owe',
        _Show.overdue => 'Overdue',
        _Show.settled => 'Settled',
        _Show.archived => 'Archived',
      };

  bool matches(Party s) => switch (this) {
        _Show.all => s.isActive,
        _Show.owing => s.isActive && s.balanceOwed > 0,
        _Show.overdue => s.isActive && s.overdue > 0,
        _Show.settled => s.isActive && s.balanceOwed <= 0,
        _Show.archived => !s.isActive,
      };
}

/// Suppliers from the server: how many, what you owe (and what is overdue),
/// what you bought this month, searchable and filtered by standing
/// (archived ones can be restored). A row opens the supplier's page.
/// Suppliers can be imported from and exported to Excel, and products at
/// their reorder level are a click away.
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _search = TextEditingController();
  _Show _show = _Show.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRead = hasPermission(ref, Permissions.suppliersView);
    final canCreate = hasPermission(ref, Permissions.suppliersCreate);
    final canEdit = hasPermission(ref, Permissions.suppliersEdit);
    final canArchive = hasPermission(ref, Permissions.suppliersArchive);
    final canSeePurchases = hasPermission(ref, Permissions.purchasesView);
    final canOrder = hasPermission(ref, Permissions.purchasesCreate);
    final state = ref.watch(partiesProvider(PartyType.supplier));
    final all = ref.watch(partyListProvider(PartyType.supplier));

    final active = all.where((s) => s.isActive).toList();
    final owed = active.fold(0.0, (t, s) => t + (s.balanceOwed > 0 ? s.balanceOwed : 0));
    final overdue = active.fold(0.0, (t, s) => t + s.overdue);
    final owing = active.where((s) => s.balanceOwed > 0).length;
    final overdueCount = active.where((s) => s.overdue > 0).length;
    final now = DateTime.now();
    final monthPurchases = (ref.watch(purchasesProvider).valueOrNull ?? const <Purchase>[]).where(
      (p) => p.status != PurchaseStatus.cancelled && p.orderDate.year == now.year && p.orderDate.month == now.month,
    );
    final boughtThisMonth = monthPurchases.fold(0.0, (t, p) => t + p.total);
    final toReorder = ref.watch(reorderGroupsProvider).fold(0, (n, g) => n + g.lines.length);

    final query = _search.text.trim().toLowerCase();
    final rows = all
        .where(_show.matches)
        .where(
          (s) =>
              query.isEmpty ||
              s.name.toLowerCase().contains(query) ||
              (s.contactPerson ?? '').toLowerCase().contains(query) ||
              (s.phone ?? '').toLowerCase().contains(query) ||
              (s.email ?? '').toLowerCase().contains(query),
        )
        .toList();

    Widget body;
    if (!canRead) {
      body = const Card(
        child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text("Your role can't view suppliers."))),
      );
    } else if (state.isLoading && !state.hasValue) {
      body = const LoadingPanel(label: 'Loading suppliers…');
    } else if (state.hasError && !state.hasValue) {
      body = ErrorRetryCard(
        error: state.error!,
        onRetry: () => ref.read(partiesProvider(PartyType.supplier).notifier).refresh(),
      );
    } else if (rows.isEmpty) {
      body = Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              all.isEmpty
                  ? 'No suppliers yet.${canCreate ? ' Use "Add supplier", or import them from Excel.' : ''}'
                  : 'No suppliers match.',
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
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Contact')),
              DataColumn(label: Text('Phone')),
              DataColumn(label: Text('Terms')),
              DataColumn(label: Text('You owe'), numeric: true),
              DataColumn(label: Text('Overdue'), numeric: true),
              DataColumn(label: Text('Bought'), numeric: true),
              DataColumn(label: Text('Last purchase')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final s in rows)
                DataRow(
                  key: ValueKey('supplier-row-${s.id}'),
                  onSelectChanged: (_) => context.go('/suppliers/${s.id}'),
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    DataCell(Text(s.contactPerson ?? '—')),
                    DataCell(Text(s.phone ?? '—')),
                    DataCell(Text('${s.paymentTermsDays} days')),
                    DataCell(Text(currencyFormat.format(s.balanceOwed))),
                    DataCell(
                      Text(
                        s.overdue > 0 ? currencyFormat.format(s.overdue) : '—',
                        style: s.overdue > 0 ? TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w700) : null,
                      ),
                    ),
                    DataCell(Text(s.totalPurchases > 0 ? currencyFormat.format(s.totalPurchases) : '—')),
                    DataCell(Text(s.lastPurchaseAt == null ? '—' : dateFormat.format(s.lastPurchaseAt!))),
                    DataCell(supplierStatusPill(s)),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.isActive) ...[
                            IconButton(
                              tooltip: canEdit ? 'Edit' : "Your role can't edit suppliers",
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: canEdit
                                  ? () => showDialog(
                                        context: context,
                                        builder: (_) => PartyFormDialog(type: PartyType.supplier, party: s),
                                      )
                                  : null,
                            ),
                            IconButton(
                              key: ValueKey('supplier-archive-${s.id}'),
                              tooltip: canArchive ? 'Archive' : "Your role can't archive suppliers",
                              icon: const Icon(Icons.archive_outlined, size: 18),
                              onPressed: canArchive ? () => archiveSupplier(context, ref, s) : null,
                            ),
                          ] else
                            TextButton.icon(
                              key: ValueKey('supplier-restore-${s.id}'),
                              onPressed: canArchive ? () => restoreSupplier(context, ref, s) : null,
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
              title: 'Suppliers',
              subtitle: canRead
                  ? '${active.length} active · open a supplier for their purchases, prices and account'
                  : 'Not available for your role',
              actions: [
                if (canOrder)
                  OutlinedButton.icon(
                    key: const Key('suppliers-reorder'),
                    onPressed: () => showDialog(context: context, builder: (_) => const ReorderDialog()),
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: Text(toReorder == 0 ? 'Reorder' : 'Reorder ($toReorder)'),
                  ),
                if (canRead)
                  OutlinedButton.icon(
                    key: const Key('suppliers-export'),
                    onPressed: rows.isEmpty ? null : () => exportSuppliers(context, rows),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                if (canCreate)
                  OutlinedButton.icon(
                    key: const Key('suppliers-import'),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const CustomerImportDialog(type: PartyType.supplier),
                    ),
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Import'),
                  ),
                Tooltip(
                  message: canCreate ? '' : "Your role can't add suppliers",
                  child: ElevatedButton.icon(
                    key: const Key('suppliers-add'),
                    onPressed: canCreate
                        ? () => showDialog(context: context, builder: (_) => const PartyFormDialog(type: PartyType.supplier))
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add supplier'),
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
                    key: const Key('suppliers-stat-count'),
                    label: 'Suppliers',
                    value: '${active.length}',
                    caption: 'You owe $owing of them',
                    icon: Icons.storefront_outlined,
                  ),
                  StatCard(
                    key: const Key('suppliers-stat-owed'),
                    label: 'You owe',
                    value: currencyFormat.format(owed),
                    caption: 'To active suppliers',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  StatCard(
                    key: const Key('suppliers-stat-overdue'),
                    label: 'Overdue',
                    value: currencyFormat.format(overdue),
                    caption: '$overdueCount supplier${overdueCount == 1 ? '' : 's'} past their terms',
                    icon: Icons.schedule_outlined,
                    accentColor: overdue > 0 ? theme.colorScheme.error : null,
                  ),
                  if (canSeePurchases)
                    StatCard(
                      key: const Key('suppliers-stat-month'),
                      label: 'Bought this month',
                      value: currencyFormat.format(boughtThisMonth),
                      caption: '${monthPurchases.length} purchase${monthPurchases.length == 1 ? '' : 's'}',
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
                  SegmentedButton<_Show>(
                    key: const Key('suppliers-show'),
                    showSelectedIcon: false,
                    segments: [for (final s in _Show.values) ButtonSegment(value: s, label: Text(s.label))],
                    selected: {_show},
                    onSelectionChanged: (s) => setState(() => _show = s.first),
                  ),
                  ToolbarSearchField(
                    controller: _search,
                    hintText: 'Search name, contact, phone or email…',
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
