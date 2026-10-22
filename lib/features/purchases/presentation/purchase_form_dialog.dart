import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../parties/data/supplier_options.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';

/// One editable line in the form.
class _LineDraft {
  _LineDraft({required this.productId, required int quantity, required double unitCost})
    : quantity = TextEditingController(text: '$quantity'),
      unitCost = TextEditingController(text: _plain(unitCost));

  final String productId;
  final TextEditingController quantity;
  final TextEditingController unitCost;

  int? get quantityValue => int.tryParse(quantity.text.trim());
  double? get unitCostValue => double.tryParse(unitCost.text.trim());

  void dispose() {
    quantity.dispose();
    unitCost.dispose();
  }
}

String _plain(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

/// Records a purchase, or edits one nothing has been received on. A new
/// purchase can be saved as a draft, placed as an order, or (for goods
/// bought and collected on the spot) received straight away.
class PurchaseFormDialog extends ConsumerStatefulWidget {
  const PurchaseFormDialog({super.key, this.purchase, this.initialSupplierId});

  /// The purchase being edited, or `null` for a new one.
  final Purchase? purchase;
  final String? initialSupplierId;

  @override
  ConsumerState<PurchaseFormDialog> createState() => _PurchaseFormDialogState();
}

class _PurchaseFormDialogState extends ConsumerState<PurchaseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late String? _supplierId = widget.purchase?.supplierId ?? widget.initialSupplierId;
  late String? _warehouseId = widget.purchase?.warehouseId;
  late DateTime _orderDate = widget.purchase?.orderDate.toLocal() ?? DateTime.now();
  late DateTime? _expectedDate = widget.purchase?.expectedDate?.toLocal();
  late final _notes = TextEditingController(text: widget.purchase?.notes);
  late final _discount = TextEditingController(text: _plain(widget.purchase?.discount ?? 0));
  late final _tax = TextEditingController(text: _plain(widget.purchase?.tax ?? 0));
  final _amountPaid = TextEditingController(text: '0');
  late final List<_LineDraft> _lines = [
    for (final line in widget.purchase?.lines ?? const <PurchaseLine>[])
      _LineDraft(productId: line.productId, quantity: line.quantity, unitCost: line.unitCost),
  ];
  String? _pickedProductId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.purchase != null;

  @override
  void dispose() {
    _notes.dispose();
    _discount.dispose();
    _tax.dispose();
    _amountPaid.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double _money(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  double get _subtotal =>
      _lines.fold(0.0, (sum, l) => sum + (l.quantityValue ?? 0) * (l.unitCostValue ?? 0));
  double get _total => _subtotal - _money(_discount) + _money(_tax);

  void _addLine(Product product) {
    setState(() {
      final existing = _lines.where((l) => l.productId == product.id).firstOrNull;
      if (existing != null) {
        existing.quantity.text = '${(existing.quantityValue ?? 0) + 1}';
      } else {
        _lines.add(_LineDraft(productId: product.id, quantity: 1, unitCost: product.purchasePrice));
      }
      _pickedProductId = null;
      _error = null;
    });
  }

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );

  PurchaseInput? _input({required bool placeOrder, required bool receive}) {
    if (!_formKey.currentState!.validate()) return null;
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return null;
    }
    if (_total < 0) {
      setState(() => _error = "The discount can't be more than the purchase is worth.");
      return null;
    }
    final paid = _money(_amountPaid);
    if (paid > _total + 0.001) {
      setState(() => _error = "The amount paid can't be more than the total.");
      return null;
    }
    return PurchaseInput(
      supplierId: _supplierId!,
      warehouseId: _warehouseId!,
      lines: [
        for (final l in _lines)
          PurchaseLineInput(
            productId: l.productId,
            quantity: l.quantityValue!,
            unitCost: l.unitCostValue!,
          ),
      ],
      placeOrder: placeOrder,
      orderDate: _orderDate,
      expectedDate: _expectedDate,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      discount: _money(_discount),
      tax: _money(_tax),
      amountPaid: _editing ? 0 : paid,
      receive: receive,
    );
  }

  Future<void> _save({required bool placeOrder, bool receive = false}) async {
    final input = _input(placeOrder: placeOrder, receive: receive);
    if (input == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final notifier = ref.read(purchasesProvider.notifier);
    try {
      String message;
      if (_editing) {
        final saved = await notifier.edit(widget.purchase!.id, input);
        message = '${saved.reference} saved.';
      } else {
        final result = await notifier.add(input);
        message = result.queued
            ? "Purchase saved on this computer — it will be sent when you're back online."
            : receive
            ? '${result.value!.reference} recorded and received — the stock is in.'
            : '${result.value!.reference} ${placeOrder ? 'ordered' : 'saved as a draft'}.';
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

  String? _wholeAboveZero(String? v) {
    final parsed = int.tryParse((v ?? '').trim());
    return parsed == null || parsed <= 0 ? 'Whole number above 0' : null;
  }

  String? _moneyField(String? v) {
    final parsed = double.tryParse((v ?? '').trim());
    return parsed == null || parsed < 0 ? '0 or more' : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suppliers = (ref.watch(supplierOptionsProvider).valueOrNull ?? const <SupplierOption>[])
        .where((s) => !s.isArchived || s.id == _supplierId)
        .toList();
    final warehouses = ref.watch(activeWarehousesProvider);
    final products =
        ref.watch(productListProvider).where((p) => !p.isArchived && !p.isPending).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final productById = {for (final p in products) p.id: p};
    final canReceive = hasPermission(ref, Permissions.purchasesReceive);
    final canPay = hasPermission(ref, Permissions.creditRecord);

    if (_warehouseId == null && warehouses.isNotEmpty) _warehouseId = warehouses.first.id;
    if (_supplierId != null && suppliers.isNotEmpty && !suppliers.any((s) => s.id == _supplierId)) {
      _supplierId = null;
    }

    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      title: Text(_editing ? 'Edit ${widget.purchase!.reference}' : 'Record purchase'),
      content: SizedBox(
        width: 720,
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
                      child: DropdownButtonFormField<String>(
                        key: const Key('purchase-supplier'),
                        initialValue: _supplierId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Supplier'),
                        items: [
                          for (final s in suppliers)
                            DropdownMenuItem(
                              value: s.id,
                              child: Text(s.label, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: _saving ? null : (v) => setState(() => _supplierId = v),
                        validator: (v) => v == null
                            ? (suppliers.isEmpty ? 'Add a supplier first' : 'Choose a supplier')
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('purchase-warehouse'),
                        initialValue: _warehouseId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Deliver to'),
                        items: [
                          for (final w in warehouses)
                            DropdownMenuItem(
                              value: w.id,
                              child: Text(w.name, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: _saving ? null : (v) => setState(() => _warehouseId = v),
                        validator: (v) => v == null ? 'Choose a warehouse' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final picked = await _pickDate(_orderDate);
                                if (picked != null) setState(() => _orderDate = picked);
                              },
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text('Ordered ${dateFormat.format(_orderDate)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                final picked = await _pickDate(_expectedDate);
                                setState(() => _expectedDate = picked);
                              },
                        icon: const Icon(Icons.local_shipping_outlined, size: 18),
                        label: Text(
                          _expectedDate == null
                              ? 'Expected date (optional)'
                              : 'Expected ${dateFormat.format(_expectedDate!)}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Products',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                DropdownMenu<String>(
                  key: ValueKey('purchase-add-product-${_lines.length}-$_pickedProductId'),
                  width: 672,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  enabled: !_saving,
                  hintText: products.isEmpty ? 'No products yet' : 'Add a product — type to search',
                  leadingIcon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                  dropdownMenuEntries: [
                    for (final p in products)
                      DropdownMenuEntry(value: p.id, label: '${p.name} · ${p.sku}'),
                  ],
                  onSelected: (id) {
                    final product = id == null ? null : productById[id];
                    if (product != null) _addLine(product);
                  },
                ),
                const SizedBox(height: 8),
                if (_lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No products added yet.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  )
                else
                  for (final line in _lines)
                    Padding(
                      key: ValueKey('purchase-line-${line.productId}'),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(
                                productById[line.productId]?.name ??
                                    widget.purchase?.lines
                                        .where((l) => l.productId == line.productId)
                                        .firstOrNull
                                        ?.productName ??
                                    'Product',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              key: ValueKey('purchase-qty-${line.productId}'),
                              controller: line.quantity,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(
                                labelText: 'Qty',
                                isDense: true,
                                suffixText: productById[line.productId]?.unit,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: _wholeAboveZero,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 130,
                            child: TextFormField(
                              key: ValueKey('purchase-cost-${line.productId}'),
                              controller: line.unitCost,
                              enabled: !_saving,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Unit cost',
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: _moneyField,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(
                                currencyFormat.format(
                                  (line.quantityValue ?? 0) * (line.unitCostValue ?? 0),
                                ),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _lines.remove(line);
                                    line.dispose();
                                  }),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                const Divider(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('purchase-discount'),
                        controller: _discount,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Discount'),
                        onChanged: (_) => setState(() {}),
                        validator: _moneyField,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('purchase-tax'),
                        controller: _tax,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: orgTaxRate > 0 ? orgTaxName : 'Tax',
                          suffixIcon: orgTaxRate > 0
                              ? IconButton(
                                  tooltip:
                                      'Apply ${_plain(orgTaxRate)}% on the goods after discount',
                                  icon: const Icon(Icons.percent, size: 18),
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() {
                                          final base = (_subtotal - _money(_discount)).clamp(
                                            0,
                                            double.infinity,
                                          );
                                          _tax.text = (base * orgTaxRate / 100).toStringAsFixed(2);
                                        }),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _moneyField,
                      ),
                    ),
                    if (!_editing && canPay) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('purchase-paid'),
                          controller: _amountPaid,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Paid now',
                            helperText: 'Leave 0 if on credit',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: _moneyField,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Goods ${currencyFormat.format(_subtotal)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                      Text(
                        'Total ${currencyFormat.format(_total)}',
                        key: const Key('purchase-total'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (!_editing && _money(_amountPaid) > 0)
                        Text(
                          'Still owed ${currencyFormat.format(_total - _money(_amountPaid))}',
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  enabled: !_saving,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  validator: (v) => (v ?? '').length > 1000 ? 'At most 1000 characters' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('purchase-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_editing) ...[
          if (widget.purchase!.status == PurchaseStatus.draft)
            OutlinedButton(
              onPressed: _saving ? null : () => _save(placeOrder: true),
              child: const Text('Save & place order'),
            ),
          ElevatedButton(
            key: const Key('purchase-save'),
            onPressed: _saving
                ? null
                : () => _save(placeOrder: widget.purchase!.status == PurchaseStatus.pending),
            child: const Text('Save changes'),
          ),
        ] else ...[
          OutlinedButton(
            key: const Key('purchase-save-draft'),
            onPressed: _saving ? null : () => _save(placeOrder: false),
            child: const Text('Save draft'),
          ),
          ElevatedButton(
            key: const Key('purchase-place-order'),
            onPressed: _saving ? null : () => _save(placeOrder: true),
            child: const Text('Place order'),
          ),
          if (canReceive)
            Tooltip(
              message:
                  'For goods bought and collected now: records the purchase and adds the stock.',
              child: ElevatedButton.icon(
                key: const Key('purchase-receive-now'),
                onPressed: _saving ? null : () => _save(placeOrder: true, receive: true),
                icon: const Icon(Icons.inventory_outlined, size: 18),
                label: const Text('Received now'),
              ),
            ),
        ],
      ],
    );
  }
}
