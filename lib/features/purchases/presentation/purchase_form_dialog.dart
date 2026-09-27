import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';

class PurchaseFormDialog extends ConsumerStatefulWidget {
  const PurchaseFormDialog({super.key});

  @override
  ConsumerState<PurchaseFormDialog> createState() => _PurchaseFormDialogState();
}

class _PurchaseFormDialogState extends ConsumerState<PurchaseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _amountPaidController = TextEditingController(text: '0');

  String? _supplierName;
  PaymentStatus _status = PaymentStatus.unpaid;
  final List<PurchaseLineItem> _items = [];

  @override
  void dispose() {
    _productController.dispose();
    _quantityController.dispose();
    _unitCostController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }

  void _addLine() {
    final product = _productController.text.trim();
    final quantity = int.tryParse(_quantityController.text);
    final unitCost = double.tryParse(_unitCostController.text);
    if (product.isEmpty || quantity == null || quantity <= 0 || unitCost == null) return;

    setState(() {
      _items.add(PurchaseLineItem(productName: product, quantity: quantity, unitCost: unitCost));
      _productController.clear();
      _quantityController.clear();
      _unitCostController.clear();
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_supplierName == null || _items.isEmpty) return;

    ref.read(purchasesProvider.notifier).addPurchase(
          Purchase(
            id: 'SAMPLE-PO-${DateTime.now().microsecondsSinceEpoch}',
            supplierName: _supplierName!,
            date: DateTime.now(),
            items: List.of(_items),
            paymentStatus: _status,
            amountPaid: double.tryParse(_amountPaidController.text) ?? 0,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(partyListProvider(PartyType.supplier));

    return AlertDialog(
      title: const Text('Record purchase'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _supplierName,
                  decoration: InputDecoration(
                    labelText: 'Supplier',
                    helperText: suppliers.isEmpty
                        ? 'No suppliers to choose from — add one on the Suppliers screen.'
                        : null,
                  ),
                  items: [
                    for (final supplier in suppliers)
                      DropdownMenuItem(value: supplier.name, child: Text(supplier.name)),
                  ],
                  onChanged: (value) => setState(() => _supplierName = value),
                  validator: (value) => value == null ? 'Select a supplier' : null,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Line items', style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 8),
                for (final item in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${item.productName}  ×${item.quantity}'),
                        ),
                        Text(currencyFormat.format(item.lineTotal)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _items.remove(item)),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _productController,
                        decoration: const InputDecoration(labelText: 'Product'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _unitCostController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Unit cost'),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _addLine),
                  ],
                ),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Add at least one line item',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<PaymentStatus>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Payment status'),
                        items: [
                          for (final status in PaymentStatus.values)
                            DropdownMenuItem(value: status, child: Text(status.label)),
                        ],
                        onChanged: (value) => setState(() => _status = value!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _amountPaidController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Amount paid'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save purchase')),
      ],
    );
  }
}
