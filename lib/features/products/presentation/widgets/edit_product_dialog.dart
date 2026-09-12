import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/products_repository.dart';
import '../../domain/product.dart';

/// Catalog-only edit — SKU/name/category/unit/pricing. Stock is deliberately
/// not editable here; it's changed through the Inventory module's stock
/// movements instead, which keeps a record of *why* it changed.
class EditProductDialog extends ConsumerStatefulWidget {
  const EditProductDialog({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends ConsumerState<EditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.product.name);
  late final _categoryController = TextEditingController(text: widget.product.category);
  late final _uomController = TextEditingController(text: widget.product.unitOfMeasure);
  late final _purchasePriceController =
      TextEditingController(text: widget.product.purchasePrice.toStringAsFixed(0));
  late final _sellingPriceController =
      TextEditingController(text: widget.product.sellingPrice.toStringAsFixed(0));

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _uomController.dispose();
    _purchasePriceController.dispose();
    _sellingPriceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(productsProvider.notifier).updateProduct(
          Product(
            id: widget.product.id,
            sku: widget.product.sku,
            barcode: widget.product.barcode,
            name: _nameController.text.trim(),
            category: _categoryController.text.trim(),
            unitOfMeasure: _uomController.text.trim(),
            purchasePrice: double.parse(_purchasePriceController.text),
            sellingPrice: double.parse(_sellingPriceController.text),
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.product.sku}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save changes')),
      ],
    );
  }
}

String? _numberValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  if (num.tryParse(value) == null) return 'Enter a number';
  return null;
}
