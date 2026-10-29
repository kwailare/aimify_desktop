import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/offline/outbox.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/toolbar_search_field.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../documents/document_preview.dart';
import '../../documents/expense_documents.dart';
import '../../sales/domain/sale.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/expense_report.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import 'expense_categories_dialog.dart';
import 'expense_detail_dialog.dart';
import 'expense_form_dialog.dart';
import 'legacy_expenses_dialog.dart';
import 'recurring_view.dart';

enum _Tab { expenses, recurring, report }

enum Period { thisMonth, lastMonth, thisYear, last12 }

extension PeriodX on Period {
  String get label => switch (this) {
        Period.thisMonth => 'This month',
        Period.lastMonth => 'Last month',
        Period.thisYear => 'This year',
        Period.last12 => 'Last 12 months',
      };

  (DateTime, DateTime) range(DateTime now) => switch (this) {
        Period.thisMonth => (DateTime(now.year, now.month), DateTime(now.year, now.month + 1)),
        Period.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
        Period.thisYear => (DateTime(now.year), DateTime(now.year, now.month + 1)),
        Period.last12 => (DateTime(now.year, now.month - 11), DateTime(now.year, now.month + 1)),
      };
}

/// Expenses from the server: what this month has cost against the budgets,
/// recurring expenses that are due, and every expense, filtered by period,
/// category, warehouse and search (voided ones on request). Tabs for the
/// recurring expenses and the report (by category with budgets, by month and
/// by warehouse; PDF and Excel). Expenses saved on this computer by older
/// versions are offered for upload.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  _Tab _tab = _Tab.expenses;
  Period _period = Period.thisMonth;
  String? _categoryId;
  String? _warehouseId;
  bool _showVoided = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canView = hasPermission(ref, Permissions.expensesView);
    final canCreate = hasPermission(ref, Permissions.expensesCreate);
    final canManage = hasPermission(ref, Permissions.expensesManage);
    final due = ref.watch(dueRecurringProvider);
    final legacy = ref.watch(legacyExpensesProvider);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Expenses',
              subtitle: 'What the business spends, by category, with receipts',
              actions: [
                if (legacy.isNotEmpty && canCreate)
                  OutlinedButton.icon(
                    key: const Key('expenses-legacy'),
                    onPressed: () => showDialog(context: context, builder: (_) => const LegacyExpensesDialog()),
                    icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                    label: Text('Upload ${legacy.length} saved on this computer'),
                  ),
                if (canManage)
                  OutlinedButton.icon(
                    key: const Key('expenses-categories'),
                    onPressed: () => showDialog(context: context, builder: (_) => const ExpenseCategoriesDialog()),
                    icon: const Icon(Icons.category_outlined, size: 18),
                    label: const Text('Categories & budgets'),
                  ),
                Tooltip(
                  message: canCreate ? '' : "Your role can't record expenses",
                  child: ElevatedButton.icon(
                    key: const Key('expenses-new'),
                    onPressed: canCreate ? () => showDialog(context: context, builder: (_) => const ExpenseFormDialog()) : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Record expense'),
                  ),
                ),
              ],
            ),
            if (due.isNotEmpty) ...[
              const SizedBox(height: 14),
              // Tinted from the theme's warning colour, so it reads in light and dark.
              Container(
                key: const Key('expenses-due'),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.12),
                  border: Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.event_repeat, size: 18, color: theme.colorScheme.secondary),
                          const SizedBox(width: 8),
                          Text(
                            '${due.length} recurring expense${due.length == 1 ? ' is' : 's are'} due',
                            style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                          ),
                        ],
                      ),
                      for (final r in due)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${r.description} · ${currencyFormat.format(r.amount)} · due ${dateFormat.format(r.nextDueDate.toLocal())}',
                                style: TextStyle(color: theme.colorScheme.onSurface),
                              ),
                            ),
                            TextButton(
                              key: ValueKey('due-record-${r.id}'),
                              onPressed: () => recordDueRecurring(context, ref, r),
                              child: const Text('Record'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_Tab>(
                key: const Key('expenses-tabs'),
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: _Tab.expenses, label: Text('Expenses')),
                  if (canCreate) const ButtonSegment(value: _Tab.recurring, label: Text('Recurring')),
                  if (canView) const ButtonSegment(value: _Tab.report, label: Text('Report & budgets')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 14),
            switch (_tab) {
              _Tab.recurring => const RecurringExpensesView(),
              _Tab.report => const ExpenseReportView(),
              _Tab.expenses => canView
                  ? _expensesList(theme)
                  : const Card(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: Text('Your role can record expenses but not see the list.')),
                      ),
                    ),
            },
          ],
        ),
      ),
    );
  }

  Widget _expensesList(ThemeData theme) {
    final state = ref.watch(expensesProvider);
    final all = state.valueOrNull ?? const <Expense>[];
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    final warehouses = ref.watch(warehouseListProvider);
    final queued = ref.watch(outboxOpsProvider).where((o) => o.kind == OpKind.expenseCreate && !o.failed).toList();
    final now = DateTime.now();
    final (from, to) = _period.range(now);

    final monthReport = buildExpenseReport(all, categories, DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    final over = monthReport.byCategory.where((c) => c.overBudget).toList();
    final today = DateTime(now.year, now.month, now.day);
    final todayTotal = all.where((e) => !e.isVoided && !e.expenseDate.isBefore(today)).fold(0.0, (s, e) => s + e.amount);
    final lastMonth = buildExpenseReport(all, categories, DateTime(now.year, now.month - 1), DateTime(now.year, now.month)).total;

    final query = _search.text.trim().toLowerCase();
    final rows = all
        .where((e) => !e.expenseDate.isBefore(from) && e.expenseDate.isBefore(to))
        .where((e) => _showVoided || !e.isVoided)
        .where((e) => _categoryId == null || e.categoryId == _categoryId)
        .where((e) => _warehouseId == null || e.warehouseId == _warehouseId)
        .where(
          (e) =>
              query.isEmpty ||
              e.reference.toLowerCase().contains(query) ||
              (e.description ?? '').toLowerCase().contains(query) ||
              (e.payee ?? '').toLowerCase().contains(query) ||
              (e.receiptNumber ?? '').toLowerCase().contains(query),
        )
        .toList();
    final shown = rows.where((e) => !e.isVoided).fold(0.0, (s, e) => s + e.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              key: const Key('expenses-stat-month'),
              label: 'This month',
              value: currencyFormat.format(monthReport.total),
              caption: '${monthReport.count} expense${monthReport.count == 1 ? '' : 's'} · last month ${currencyFormat.format(lastMonth)}',
              icon: Icons.receipt_long_outlined,
            ),
            StatCard(
              key: const Key('expenses-stat-budget'),
              label: 'Budget this month',
              value: monthReport.budget > 0 ? currencyFormat.format(monthReport.budget) : 'None set',
              caption: monthReport.budget > 0
                  ? '${currencyFormat.format((monthReport.budget - monthReport.byCategory.where((c) => c.hasBudget).fold(0.0, (s, c) => s + c.total)).clamp(0, double.infinity))} left in budgeted categories'
                  : 'Set budgets under Categories & budgets',
              icon: Icons.savings_outlined,
            ),
            StatCard(
              key: const Key('expenses-stat-over'),
              label: 'Over budget',
              value: '${over.length}',
              caption: over.isEmpty ? 'No category over its budget' : over.map((c) => c.name).join(', '),
              icon: Icons.warning_amber_outlined,
              accentColor: over.isEmpty ? null : theme.colorScheme.error,
            ),
            StatCard(
              label: 'Today',
              value: currencyFormat.format(todayTotal),
              caption: 'Recorded today',
              icon: Icons.today_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<Period>(
              key: const Key('expenses-period'),
              showSelectedIcon: false,
              segments: [for (final p in Period.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                key: const Key('expenses-category-filter'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.category_outlined, size: 18)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                  for (final c in categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ),
            if (warehouses.length > 1)
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.warehouse_outlined, size: 18)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All warehouses')),
                    for (final w in warehouses) DropdownMenuItem<String?>(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _warehouseId = v),
                ),
              ),
            FilterChip(
              key: const Key('expenses-show-voided'),
              label: const Text('Show voided'),
              selected: _showVoided,
              onSelected: (v) => setState(() => _showVoided = v),
            ),
            ToolbarSearchField(
              controller: _search,
              hintText: 'Search reference, description, paid to…',
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${rows.length} expense${rows.length == 1 ? '' : 's'} · ${currencyFormat.format(shown)}',
          key: const Key('expenses-shown'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 8),
        if (state.isLoading && !state.hasValue)
          const LoadingPanel(label: 'Loading expenses…')
        else if (state.hasError && !state.hasValue)
          ErrorRetryCard(error: state.error!, onRetry: () => ref.read(expensesProvider.notifier).refresh())
        else if (rows.isEmpty && queued.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(child: Text(all.isEmpty ? 'No expenses yet.' : 'No expenses match.')),
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
                  DataColumn(label: Text('Ref.')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Category')),
                  DataColumn(label: Text('What')),
                  DataColumn(label: Text('Paid by')),
                  DataColumn(label: Text('Warehouse')),
                  DataColumn(label: Text('Amount'), numeric: true),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final op in queued)
                    () {
                      final input = ExpenseInput.fromJson(Map<String, dynamic>.from(op.payload['input'] as Map));
                      return DataRow(
                        key: ValueKey('expense-queued-${op.id}'),
                        cells: [
                          const DataCell(Text('—')),
                          DataCell(Text(dateFormat.format(input.expenseDate))),
                          DataCell(Text(categories.where((c) => c.id == input.categoryId).firstOrNull?.name ?? '')),
                          DataCell(Text(input.description ?? input.payee ?? '')),
                          DataCell(Text(input.paymentMethod.label)),
                          const DataCell(Text('')),
                          DataCell(Text(currencyFormat.format(input.amount))),
                          const DataCell(StatusPill(label: 'Waiting to sync', tone: StatusTone.neutral)),
                        ],
                      );
                    }(),
                  for (final e in rows)
                    DataRow(
                      key: ValueKey('expense-row-${e.id}'),
                      onSelectChanged: (_) => showDialog(context: context, builder: (_) => ExpenseDetailDialog(expenseId: e.id)),
                      cells: [
                        DataCell(Text(e.reference, style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text(dateFormat.format(e.expenseDate))),
                        DataCell(Text(e.categoryName)),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Text(e.title, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        DataCell(Text(e.paymentMethod.label)),
                        DataCell(Text(e.warehouseName ?? '—')),
                        DataCell(
                          Text(
                            currencyFormat.format(e.amount),
                            style: e.isVoided ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (e.hasAttachment)
                                Tooltip(
                                  message: 'Receipt attached',
                                  child: Icon(e.attachmentIsPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18),
                                ),
                              if (e.isVoided) ...[
                                const SizedBox(width: 6),
                                const StatusPill(label: 'Voided', tone: StatusTone.neutral),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Spending in a period: by category against the budgets, by month and by
/// warehouse, with Print / PDF and Excel.
class ExpenseReportView extends ConsumerStatefulWidget {
  const ExpenseReportView({super.key});

  @override
  ConsumerState<ExpenseReportView> createState() => _ExpenseReportViewState();
}

class _ExpenseReportViewState extends ConsumerState<ExpenseReportView> {
  Period _period = Period.thisMonth;

  Future<void> _excel(ExpenseReport report) async {
    try {
      final bytes = Uint8List.fromList(buildExpenseReportExcel(report));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save expense report',
        fileName: 'expenses-${DateFormat('yyyy-MM').format(report.from)}.xlsx',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Expense report saved to $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text("Couldn't save the report: ${friendlyError(e)}")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final state = ref.watch(expensesProvider);
    final all = state.valueOrNull ?? const <Expense>[];
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    final (from, to) = _period.range(DateTime.now());
    final report = buildExpenseReport(all, categories, from, to);
    final biggestMonth = report.byMonth.fold(0.0, (m, x) => x.$2 > m ? x.$2 : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<Period>(
              key: const Key('report-period'),
              showSelectedIcon: false,
              segments: [for (final p in Period.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            OutlinedButton.icon(
              key: const Key('report-pdf'),
              onPressed: () => ref.read(documentOpenerProvider).open(
                    context,
                    ref,
                    title: 'Expense report',
                    fileName: 'expenses-${DateFormat('yyyy-MM').format(report.from)}.pdf',
                    build: (kit) => buildExpenseReportPdf(kit, report),
                  ),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print / PDF'),
            ),
            OutlinedButton.icon(
              key: const Key('report-excel'),
              onPressed: () => _excel(report),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Excel'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${currencyFormat.format(report.total)} on ${report.count} expense${report.count == 1 ? '' : 's'}'
          '${report.budget > 0 ? ' · budget ${currencyFormat.format(report.budget)}' : ''}',
          key: const Key('report-total'),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('By category', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (report.byCategory.isEmpty) Text('Nothing spent in this period.', style: muted),
                for (final c in report.byCategory)
                  Padding(
                    key: ValueKey('report-category-${c.name}'),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(currencyFormat.format(c.total)),
                            if (c.hasBudget)
                              Text(
                                ' of ${currencyFormat.format(c.budget)}',
                                style: muted,
                              ),
                          ],
                        ),
                        if (c.hasBudget) ...[
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: (c.used ?? 0).clamp(0, 1).toDouble(),
                            color: c.overBudget ? theme.colorScheme.error : const Color(0xFF2F8F5B),
                            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.overBudget
                                ? 'Over budget by ${currencyFormat.format(-c.left)}'
                                : '${currencyFormat.format(c.left)} left',
                            style: c.overBudget ? TextStyle(color: theme.colorScheme.error, fontSize: 12) : muted,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('By month', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final (month, total) in report.byMonth)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(width: 80, child: Text(DateFormat('MMM yyyy').format(month))),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: biggestMonth == 0 ? 0 : total / biggestMonth,
                                  backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                                ),
                              ),
                              SizedBox(width: 120, child: Text(currencyFormat.format(total), textAlign: TextAlign.end)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('By warehouse', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final (warehouse, total) in report.byWarehouse)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text(warehouse)),
                              Text(currencyFormat.format(total)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text('By payment method', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final (method, total) in report.byMethod)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text(method.label)),
                              Text(currencyFormat.format(total)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
