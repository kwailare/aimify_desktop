import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/data/warehouse_stock_repository.dart';
import '../../inventory/domain/warehouse_stock.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/products_repository.dart';
import '../domain/product.dart';

/// Add-product dialog. Writes into the in-memory [productsProvider] (the
/// catalog) plus a [WarehouseStock] row for whichever warehouse the opening
/// stock is being added to — see the MOCK repository notes on both. Good
/// enough to make the screen feel interactive without pretending there's a
/// real backend behind it.
class ProductFormDialog extends ConsumerStatefulWidget {
  const ProductFormDialog({super.key});

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _uomController = TextEditingController(text: 'Unit');
  final _purchasePriceController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _lowStockController = TextEditingController(text: '5');

  String? _warehouseId;

  @override
  void initState() {
    super.initState();
    // Default to whatever scope the Products screen is currently filtered
    // to, if it's a specific warehouse rather than "All warehouses."
    _warehouseId = ref.read(selectedWarehouseIdProvider);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _uomController.dispose();
    _purchasePriceController.dispose();
    _sellingPriceController.dispose();
    _stockController.dispose();
    _lowStockController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_warehouseId == null) return;

    final existing = ref.read(productsProvider);
    final nextIndex = existing.length + 1;
    final productId = 'p${DateTime.now().microsecondsSinceEpoch}';

    ref.read(productsProvider.notifier).addProduct(
          Product(
            id: productId,
            sku: 'SAMPLE-SKU-${nextIndex.toString().padLeft(3, '0')}',
            barcode: '—',
            name: _nameController.text.trim(),
            category: _categoryController.text.trim(),
            unitOfMeasure: _uomController.text.trim(),
            purchasePrice: double.parse(_purchasePriceController.text),
            sellingPrice: double.parse(_sellingPriceController.text),
          ),
        );

    ref.read(warehouseStockProvider.notifier).setStock(
          WarehouseStock(
            productId: productId,
            warehouseId: _warehouseId!,
            quantity: int.parse(_stockController.text),
            lowStockThreshold: int.parse(_lowStockController.text),
          ),
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(warehousesProvider);

    return AlertDialog(
      title: const Text('Add product'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'Add to warehouse'),
                  items: [
                    for (final warehouse in warehouses)
                      DropdownMenuItem(value: warehouse.id, child: Text(warehouse.name)),
                  ],
                  onChanged: (value) => setState(() => _warehouseId = value),
                  validator: (value) => value == null ? 'Select a warehouse' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _uomController,
                  decoration: const InputDecoration(labelText: 'Unit of measure'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _purchasePriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Purchase price'),
                        validator: _numberValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sellingPriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Selling price'),
                        validator: _numberValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Opening stock'),
                        validator: _numberValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lowStockController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Low-stock alert at'),
                        validator: _numberValidator,
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Add product')),
      ],
    );
  }
}

String? _numberValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  if (num.tryParse(value) == null) return 'Enter a number';
  return null;
}
