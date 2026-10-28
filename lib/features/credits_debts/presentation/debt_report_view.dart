import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../documents/debt_documents.dart';
import '../../documents/document_preview.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../parties/presentation/credit_entry_dialog.dart';
import '../data/debt_excel.dart';
import '../data/debt_report.dart';

void _toast(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

Party? _partyFor(WidgetRef ref, PartyType type, String id) =>
    ref.read(partyListProvider(type)).where((p) => p.id == id).firstOrNull;

void _printReport(BuildContext context, WidgetRef ref, DebtReport report) {
  final who = report.type == PartyType.customer ? 'customer' : 'supplier';
  ref.read(documentOpenerProvider).open(
        context,
        ref,
        title: 'Debt report ($who)',
        fileName: 'debt-report-$who.pdf',
        build: (kit) => buildDebtReport(kit, report),
      );
}

Future<void> _exportReport(BuildContext context, DebtReport report) async {
  final who = report.type == PartyType.customer ? 'customers' : 'suppliers';
  try {
    final bytes = Uint8List.fromList(buildDebtReportExcel(report));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save debt report',
      fileName: 'debt-report-$who.xlsx',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path == null) return;
    await File(path).writeAsBytes(bytes);
    if (context.mounted) _toast(context, 'Debt report saved to $path');
  } catch (e) {
    if (context.mounted) _toast(context, "Couldn't save the report: ${friendlyError(e)}");
  }
}

/// The aging report for customers or suppliers: totals by age, then each
/// party's debt split by how far past due it is. A row lists that party's
/// open items. Print/PDF and Excel.
class DebtAgingView extends ConsumerStatefulWidget {
  const DebtAgingView({super.key});

  @override
  ConsumerState<DebtAgingView> createState() => _DebtAgingViewState();
}

class _DebtAgingViewState extends ConsumerState<DebtAgingView> {
  late PartyType _type =
      hasPermission(ref, Permissions.customersView) ? PartyType.customer : PartyType.supplier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCustomers = hasPermission(ref, Permissions.customersView);
    final canSuppliers = hasPermission(ref, Permissions.suppliersView);
    if (!canCustomers && !canSuppliers) {
      return const Center(child: Text("Your role can't view customers or suppliers."));
    }
    final state = ref.watch(debtReportProvider(_type));
    final report = state.valueOrNull;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canCustomers && canSuppliers)
                SegmentedButton<PartyType>(
                  key: const Key('aging-side'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: PartyType.customer, label: Text('Customers owe you')),
                    ButtonSegment(value: PartyType.supplier, label: Text('You owe suppliers')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
              if (report != null)
                Text(
                  'As of ${dateTimeFormat.format(report.asOf)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(debtReportProvider(_type)),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              OutlinedButton.icon(
                key: const Key('aging-pdf'),
                onPressed: report == null ? null : () => _printReport(context, ref, report),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print / PDF'),
              ),
              OutlinedButton.icon(
                key: const Key('aging-excel'),
                onPressed: report == null ? null : () => _exportReport(context, report),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Excel'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (state.isLoading && report == null)
            const LoadingPanel(label: 'Working out the debt report…')
          else if (state.hasError && report == null)
            ErrorRetryCard(error: state.error!, onRetry: () => ref.invalidate(debtReportProvider(_type)))
          else if (report != null) ...[
            _BucketStrip(report: report),
            const SizedBox(height: 14),
            if (report.parties.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Text(_type == PartyType.customer ? 'No customer owes you anything.' : "You don't owe any supplier."),
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
                    columns: [
                      DataColumn(label: Text(_type.label)),
                      const DataColumn(label: Text('Balance'), numeric: true),
                      for (final b in AgeBucket.values) DataColumn(label: Text(b.label), numeric: true),
                      const DataColumn(label: Text('Last paid')),
                    ],
                    rows: [
                      for (final p in report.parties)
                        DataRow(
                          key: ValueKey('aging-row-${p.id}'),
                          onSelectChanged: (_) => showDialog(
                            context: context,
                            builder: (_) => _OpenItemsDialog(type: _type, row: p),
                          ),
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            ),
                            DataCell(
                              Text(
                                p.balance < 0 ? '${currencyFormat.format(-p.balance)} credit' : currencyFormat.format(p.balance),
                              ),
                            ),
                            for (final b in AgeBucket.values)
                              DataCell(
                                Text(
                                  (p.buckets[b] ?? 0) > 0 ? currencyFormat.format(p.buckets[b]!) : '—',
                                  style: b != AgeBucket.current && (p.buckets[b] ?? 0) > 0
                                      ? TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)
                                      : null,
                                ),
                              ),
                            DataCell(Text(p.lastPaymentAt == null ? 'Never' : dateFormat.format(p.lastPaymentAt!))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BucketStrip extends StatelessWidget {
  const _BucketStrip({required this.report});

  final DebtReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, double value, {Color? color, Key? key}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              key: key,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 4),
                Text(
                  currencyFormat.format(value),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
        );
    return Card(
      child: Row(
        children: [
          cell(report.type == PartyType.customer ? 'Owed to you' : 'You owe', report.balance, key: const Key('aging-total')),
          cell('Overdue', report.overdue, color: report.overdue > 0 ? theme.colorScheme.error : null, key: const Key('aging-overdue')),
          for (final b in AgeBucket.values)
            cell(b.label, report.buckets[b] ?? 0, color: b != AgeBucket.current && (report.buckets[b] ?? 0) > 0 ? theme.colorScheme.error : null),
        ],
      ),
    );
  }
}

/// One party's open debts, oldest due first.
class _OpenItemsDialog extends ConsumerWidget {
  const _OpenItemsDialog({required this.type, required this.row});

  final PartyType type;
  final DebtorRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final party = _partyFor(ref, type, row.id);
    final canRecord = hasPermission(ref, Permissions.creditRecord);
    return AlertDialog(
      title: Text(row.name),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'Balance ${currencyFormat.format(row.balance)}',
                if (row.overdue > 0) '${currencyFormat.format(row.overdue)} overdue',
                '${row.paymentTermsDays}-day terms',
                if (row.phone != null) row.phone!,
              ].join(' · '),
            ),
            const SizedBox(height: 10),
            if (row.items.isEmpty)
              const Text('Nothing open.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 34,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 40,
                  columns: const [
                    DataColumn(label: Text('Item')),
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Due')),
                    DataColumn(label: Text('Still open'), numeric: true),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final i in row.items)
                      DataRow(
                        cells: [
                          DataCell(Text(i.reference)),
                          DataCell(Text(dateFormat.format(i.date))),
                          DataCell(Text(dateFormat.format(i.dueDate))),
                          DataCell(Text(currencyFormat.format(i.openAmount))),
                          DataCell(
                            i.daysOverdue > 0
                                ? StatusPill(label: '${i.daysOverdue}d overdue', tone: StatusTone.negative)
                                : const StatusPill(label: 'Not yet due', tone: StatusTone.positive),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            if (row.balance < 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  type == PartyType.customer
                      ? 'They are ${currencyFormat.format(-row.balance)} in credit (owed back to them).'
                      : 'They owe you ${currencyFormat.format(-row.balance)} back.',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (type == PartyType.customer)
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/customers/${row.id}');
            },
            child: const Text('Open customer'),
          ),
        if (canRecord && party != null && row.balance > 0)
          ElevatedButton(
            onPressed: () => recordCreditEntry(context, ref, party, CreditKind.payment),
            child: const Text('Record payment'),
          ),
      ],
    );
  }
}

/// Customers with overdue debt, biggest first, with how to reach them and
/// when they last paid.
class WhoToChaseView extends ConsumerWidget {
  const WhoToChaseView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (!hasPermission(ref, Permissions.customersView)) {
      return const Center(child: Text("Your role can't view customers."));
    }
    final state = ref.watch(debtReportProvider(PartyType.customer));
    final report = state.valueOrNull;
    if (state.isLoading && report == null) return const LoadingPanel(label: 'Finding overdue customers…');
    if (state.hasError && report == null) {
      return ErrorRetryCard(error: state.error!, onRetry: () => ref.invalidate(debtReportProvider(PartyType.customer)));
    }
    final rows = report?.toChase ?? const <DebtorRow>[];
    if (rows.isEmpty) {
      return const Center(child: Text('Nobody is overdue. 🎉'));
    }
    final canRecord = hasPermission(ref, Permissions.creditRecord);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = rows[i];
        final party = _partyFor(ref, PartyType.customer, r.id);
        return Card(
          key: ValueKey('chase-${r.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          r.phone ?? 'No phone',
                          r.lastPaymentAt == null
                              ? 'never paid'
                              : 'last paid ${dateFormat.format(r.lastPaymentAt!)} (${r.daysSinceLastPayment} days ago)',
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${currencyFormat.format(r.overdue)} overdue',
                      style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w800),
                    ),
                    Text('up to ${r.maxDaysOverdue} days · owes ${currencyFormat.format(r.balance)}', style: muted),
                  ],
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => context.go('/customers/${r.id}'),
                  child: const Text('Open'),
                ),
                if (canRecord && party != null) ...[
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: ValueKey('chase-pay-${r.id}'),
                    onPressed: () => recordCreditEntry(context, ref, party, CreditKind.payment),
                    child: const Text('Record payment'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
