import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../sales/domain/sale.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';

String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Records the occurrence of [r] that is due, after asking the amount (it
/// can differ from usual).
Future<void> recordDueRecurring(BuildContext context, WidgetRef ref, RecurringExpense r) async {
  final amount = await showDialog<double>(context: context, builder: (_) => _RecordDialog(recurring: r));
  if (amount == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final expense = await ref.read(expensesProvider.notifier).recordRecurring(r, amount: amount == r.amount ? null : amount);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${expense.reference} recorded · ${r.description} ${currencyFormat.format(expense.amount)}.')));
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// Rent, salaries and the like: what comes round again, when it is next due,
/// with Record for the ones due now. Owners and Administrators add, change,
/// pause and remove them.
class RecurringExpensesView extends ConsumerWidget {
  const RecurringExpensesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage = hasPermission(ref, Permissions.expensesManage);
    final state = ref.watch(recurringExpensesProvider);
    final rows = state.valueOrNull ?? const <RecurringExpense>[];
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Expenses that come round again. When one is due, record it here.', style: muted)),
            if (canManage)
              ElevatedButton.icon(
                key: const Key('recurring-add'),
                onPressed: () => showDialog(context: context, builder: (_) => const RecurringFormDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add recurring'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.isLoading && !state.hasValue)
          const LoadingPanel(label: 'Loading recurring expenses…')
        else if (state.hasError && !state.hasValue)
          ErrorRetryCard(error: state.error!, onRetry: () => ref.read(recurringExpensesProvider.notifier).refresh())
        else if (rows.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No recurring expenses yet.'))))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('What')),
                  DataColumn(label: Text('Category')),
                  DataColumn(label: Text('How often')),
                  DataColumn(label: Text('Amount'), numeric: true),
                  DataColumn(label: Text('Next due')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(
                      key: ValueKey('recurring-row-${r.id}'),
                      cells: [
                        DataCell(Text(r.description, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(r.categoryName)),
                        DataCell(Text(r.frequency.label)),
                        DataCell(Text(currencyFormat.format(r.amount))),
                        DataCell(
                          !r.active
                              ? const StatusPill(label: 'Paused', tone: StatusTone.neutral)
                              : r.due
                                  ? StatusPill(label: 'Due ${dateFormat.format(r.nextDueDate.toLocal())}', tone: StatusTone.warning)
                                  : Text(dateFormat.format(r.nextDueDate.toLocal())),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (r.due)
                                ElevatedButton(
                                  key: ValueKey('recurring-record-${r.id}'),
                                  onPressed: () => recordDueRecurring(context, ref, r),
                                  child: const Text('Record'),
                                ),
                              if (canManage) ...[
                                IconButton(
                                  tooltip: 'Change',
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => showDialog(context: context, builder: (_) => RecurringFormDialog(recurring: r)),
                                ),
                                IconButton(
                                  key: ValueKey('recurring-pause-${r.id}'),
                                  tooltip: r.active ? 'Pause' : 'Resume',
                                  icon: Icon(r.active ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
                                  onPressed: () => ref.read(recurringExpensesProvider.notifier).save(r.id, {'active': !r.active}),
                                ),
                                IconButton(
                                  key: ValueKey('recurring-delete-${r.id}'),
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: () => ref.read(recurringExpensesProvider.notifier).remove(r.id),
                                ),
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

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.recurring});

  final RecurringExpense recurring;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  late final _amount = TextEditingController(text: _plain(widget.recurring.amount));
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recurring;
    return AlertDialog(
      title: Text('Record ${r.description}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Due ${dateFormat.format(r.nextDueDate.toLocal())} · ${r.categoryName} · ${r.paymentMethod.label}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recurring-record-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount this time'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          key: const Key('recurring-record-confirm'),
          onPressed: () {
            final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
            if (amount == null || amount <= 0) return setState(() => _error = 'Enter an amount above 0.');
            Navigator.of(context).pop(amount);
          },
          child: const Text('Record expense'),
        ),
      ],
    );
  }
}

/// Adds or changes a recurring expense.
class RecurringFormDialog extends ConsumerStatefulWidget {
  const RecurringFormDialog({super.key, this.recurring});

  final RecurringExpense? recurring;

  @override
  ConsumerState<RecurringFormDialog> createState() => _RecurringFormDialogState();
}

class _RecurringFormDialogState extends ConsumerState<RecurringFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late String? _categoryId = widget.recurring?.categoryId;
  late final _description = TextEditingController(text: widget.recurring?.description);
  late final _amount = TextEditingController(text: widget.recurring == null ? '' : _plain(widget.recurring!.amount));
  late final _payee = TextEditingController(text: widget.recurring?.payee);
  late Frequency _frequency = widget.recurring?.frequency ?? Frequency.monthly;
  late SalePaymentMethod _method = widget.recurring?.paymentMethod ?? SalePaymentMethod.transfer;
  late String? _warehouseId = widget.recurring?.warehouseId;
  late DateTime _next = (widget.recurring?.nextDueDate.toLocal()) ?? DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_description, _amount, _payee]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(recurringExpensesProvider.notifier).save(widget.recurring?.id, {
        'categoryId': _categoryId,
        'description': _description.text.trim(),
        'amount': double.parse(_amount.text.trim().replaceAll(',', '')),
        'frequency': _frequency.name,
        'paymentMethod': _method.apiValue,
        'warehouseId': _warehouseId,
        'payee': _payee.text.trim().isEmpty ? null : _payee.text.trim(),
        'nextDueDate': DateTime.utc(_next.year, _next.month, _next.day).toIso8601String(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    final warehouses = ref.watch(activeWarehousesProvider);
    return AlertDialog(
      title: Text(widget.recurring == null ? 'Add recurring expense' : 'Change ${widget.recurring!.description}'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('recurring-description'),
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'What is it? *', hintText: 'e.g. Shop rent'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('recurring-category'),
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Category *'),
                        items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                        onChanged: (v) => setState(() => _categoryId = v),
                        validator: (v) => v == null ? 'Choose one' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('recurring-amount'),
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Usual amount *'),
                        validator: (v) {
                          final a = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                          return a == null || a <= 0 ? 'Above 0' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<Frequency>(
                        key: const Key('recurring-frequency'),
                        initialValue: _frequency,
                        decoration: const InputDecoration(labelText: 'How often'),
                        items: [for (final f in Frequency.values) DropdownMenuItem(value: f, child: Text(f.label))],
                        onChanged: (v) => setState(() => _frequency = v ?? Frequency.monthly),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        key: const Key('recurring-next'),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _next,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setState(() => _next = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Next due'),
                          child: Text(dateFormat.format(_next)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<SalePaymentMethod>(
                        initialValue: _method,
                        decoration: const InputDecoration(labelText: 'Paid by'),
                        items: [for (final m in SalePaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
                        onChanged: (v) => setState(() => _method = v ?? SalePaymentMethod.transfer),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(controller: _payee, decoration: const InputDecoration(labelText: 'Paid to (optional)')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'For warehouse (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('The whole business')),
                    for (final w in warehouses) DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (v) => setState(() => _warehouseId = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(key: const Key('recurring-save'), onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
