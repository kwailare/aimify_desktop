import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../products/data/products_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/inventory_repository.dart';
import '../domain/stock_movement.dart';

class StockMovementDialog extends ConsumerStatefulWidget {
  const StockMovementDialog({super.key});

  @override
  ConsumerState<StockMovementDialog> createState() => _StockMovementDialogState();
}

class _StockMovementDialogState extends ConsumerState<StockMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();

  String? _selectedProductId;
  String? _selectedWarehouseId;
  StockMovementType _type = StockMovementType.stockIn;

  @override
  void initState() {
    super.initState();
    _selectedWarehouseId = ref.read(selectedWarehouseIdProvider);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final product = ref.read(productsProvider).firstWhere((p) => p.id == _selectedProductId);
    final warehouse = ref.read(warehousesProvider).firstWhere((w) => w.id == _selectedWarehouseId);

    ref.read(inventoryProvider.notifier).addMovement(
          productId: product.id,
          productName: product.name,
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
          type: _type,
          quantity: int.parse(_quantityController.text),
          reason: _reasonController.text.trim(),
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final warehouses = ref.watch(warehousesProvider);

    return AlertDialog(
      title: const Text('Record stock movement'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedWarehouseId,
                decoration: const InputDecoration(labelText: 'Warehouse'),
                items: [
                  for (final warehouse in warehouses)
                    DropdownMenuItem(value: warehouse.id, child: Text(warehouse.name)),
                ],
                onChanged: (value) => setState(() => _selectedWarehouseId = value),
                validator: (value) => value == null ? 'Select a warehouse' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedProductId,
                decoration: const InputDecoration(labelText: 'Product'),
                items: [
                  for (final product in products)
                    DropdownMenuItem(value: product.id, child: Text(product.name)),
                ],
                onChanged: (value) => setState(() => _selectedProductId = value),
                validator: (value) => value == null ? 'Select a product' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StockMovementType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Movement type'),
                items: [
                  for (final type in StockMovementType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final parsed = int.tryParse(v);
                  if (parsed == null || parsed <= 0) return 'Enter a positive whole number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason / reference'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
