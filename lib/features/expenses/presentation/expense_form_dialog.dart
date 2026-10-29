import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../sales/domain/sale.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';

String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// A receipt picked to attach: its bytes and file name.
typedef PickedReceipt = ({String name, List<int> bytes});

/// Lets tests stand in for the file picker.
final receiptPickerProvider = Provider<Future<PickedReceipt?> Function()>((ref) => () async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      return file == null || bytes == null ? null : (name: file.name, bytes: bytes);
    });

/// Records an expense, or changes one ([expense]): category, amount, date,
/// how it was paid, optionally the warehouse it was for, who was paid, their
/// receipt number and a description, and a photo or PDF of the receipt. A
/// new expense can be recorded offline (the receipt is then attached when
/// the connection is back, from the expense).
class ExpenseFormDialog extends ConsumerStatefulWidget {
  const ExpenseFormDialog({super.key, this.expense});

  final Expense? expense;

  @override
  ConsumerState<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late String? _categoryId = widget.expense?.categoryId;
  late final _amount = TextEditingController(text: widget.expense == null ? '' : _plain(widget.expense!.amount));
  late DateTime _date = widget.expense?.expenseDate ?? DateTime.now();
  late SalePaymentMethod _method = widget.expense?.paymentMethod ?? SalePaymentMethod.cash;
  late String? _warehouseId = widget.expense?.warehouseId;
  late final _payee = TextEditingController(text: widget.expense?.payee);
  late final _receiptNo = TextEditingController(text: widget.expense?.receiptNumber);
  late final _description = TextEditingController(text: widget.expense?.description);
  PickedReceipt? _receipt;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.expense != null;

  @override
  void dispose() {
    for (final c in [_amount, _payee, _receiptNo, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
  }

  Future<void> _pickReceipt() async {
    final picked = await ref.read(receiptPickerProvider)();
    if (picked == null) return;
    if (picked.bytes.length > 5 * 1024 * 1024) {
      setState(() => _error = 'The receipt must be 5 MB or smaller.');
      return;
    }
    setState(() {
      _receipt = picked;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final input = ExpenseInput(
      categoryId: _categoryId!,
      amount: double.parse(_amount.text.trim().replaceAll(',', '')),
      expenseDate: _date,
      paymentMethod: _method,
      warehouseId: _warehouseId,
      payee: _optional(_payee),
      receiptNumber: _optional(_receiptNo),
      description: _optional(_description),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final notifier = ref.read(expensesProvider.notifier);
    try {
      String message;
      Expense? saved;
      if (_editing) {
        saved = await notifier.edit(widget.expense!.id, input);
        message = '${saved.reference} saved.';
      } else {
        final result = await notifier.add(input);
        saved = result.value;
        message = result.queued
            ? "Expense saved on this computer — it will be sent when you're back online."
            : '${saved!.reference} recorded · ${currencyFormat.format(saved.amount)}.';
      }
      final receipt = _receipt;
      if (receipt != null && saved != null) {
        try {
          await notifier.attach(saved.id, bytes: receipt.bytes, filename: receipt.name);
        } catch (e) {
          message = '$message The receipt could not be attached: ${friendlyError(e)}';
        }
      } else if (receipt != null) {
        message = '$message Attach the receipt from the expense once it has been sent.';
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    final warehouses = ref.watch(activeWarehousesProvider);
    final knownCategory = categories.any((c) => c.id == _categoryId);

    return AlertDialog(
      title: Text(_editing ? 'Edit ${widget.expense!.reference}' : 'Record expense'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        key: const Key('expense-category'),
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Category *'),
                        items: [
                          for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                          if (_categoryId != null && !knownCategory)
                            DropdownMenuItem(value: _categoryId, child: Text(widget.expense?.categoryName ?? 'Category')),
                        ],
                        onChanged: _saving ? null : (v) => setState(() => _categoryId = v),
                        validator: (v) => v == null ? 'Choose a category' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: const Key('expense-amount'),
                        controller: _amount,
                        enabled: !_saving,
                        autofocus: !_editing,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Amount *', prefixText: '${currencyFormat.currencySymbol} '),
                        validator: (v) {
                          final parsed = double.tryParse((v ?? '').trim().replaceAll(',', ''));
                          return parsed == null || parsed <= 0 ? 'Above 0' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: const Key('expense-date'),
                        onTap: _saving ? null : _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Date'),
                          child: Text(dateFormat.format(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<SalePaymentMethod>(
                        key: const Key('expense-method'),
                        initialValue: _method,
                        decoration: const InputDecoration(labelText: 'Paid by'),
                        items: [for (final m in SalePaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
                        onChanged: _saving ? null : (v) => setState(() => _method = v ?? SalePaymentMethod.cash),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const Key('expense-warehouse'),
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'For warehouse (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('The whole business')),
                    for (final w in warehouses) DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                    if (_warehouseId != null && !warehouses.any((w) => w.id == _warehouseId))
                      DropdownMenuItem<String?>(value: _warehouseId, child: Text(widget.expense?.warehouseName ?? 'Warehouse')),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _warehouseId = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('expense-payee'),
                        controller: _payee,
                        enabled: !_saving,
                        decoration: const InputDecoration(labelText: 'Paid to (optional)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('expense-receipt-number'),
                        controller: _receiptNo,
                        enabled: !_saving,
                        decoration: const InputDecoration(labelText: 'Their receipt no. (optional)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('expense-description'),
                  controller: _description,
                  enabled: !_saving,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Description (optional)', counterText: ''),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const Key('expense-pick-receipt'),
                      onPressed: _saving ? null : _pickReceipt,
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: Text(_receipt == null
                          ? (widget.expense?.hasAttachment == true ? 'Replace receipt' : 'Attach receipt')
                          : 'Change receipt'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _receipt?.name ??
                            (widget.expense?.hasAttachment == true
                                ? 'Has: ${widget.expense!.attachmentName ?? 'receipt'}'
                                : 'Photo or PDF, up to 5 MB'),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, key: const Key('expense-error'), style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          key: const Key('expense-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_editing ? 'Save changes' : 'Record expense'),
        ),
      ],
    );
  }
}
