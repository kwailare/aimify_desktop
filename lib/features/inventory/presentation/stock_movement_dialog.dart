import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../data/inventory_repository.dart';
import '../domain/allowed_movement_types.dart';
import '../domain/stock_movement.dart';

/// Record a stock movement against the real API.
///
/// The server takes a *signed* delta, so this dialog does the translation
/// people shouldn't have to think about: "Stock out 30" is sent as -30, an
/// adjustment goes up or down as chosen, and a stock count is sent as the
/// difference between what was counted and what the system shows.
///
/// Which types appear comes from the role's permissions (`stock.out` for
/// stock out, `stock.adjust` for the rest) — Sales Staff only ever see
/// "Stock out".
class StockMovementDialog extends ConsumerStatefulWidget {
  const StockMovementDialog({super.key, this.initialProductId});

  final String? initialProductId;

  @override
  ConsumerState<StockMovementDialog> createState() => _StockMovementDialogState();
}

class _StockMovementDialogState extends ConsumerState<StockMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();

  String? _productId;
  String? _warehouseId;
  StockMovementType? _type;
  bool _adjustDown = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _productId = widget.initialProductId;
    // `ref.read`, not `ref.watch` — a watch can't be established before
    // `initState()` finishes, and this is a one-time initial pick anyway.
    final permissions = ref.read(authControllerProvider).valueOrNull?.permissions ?? const [];
    final allowed = allowedMovementTypes(permissions);
    _type = allowed.isEmpty ? null : allowed.first;
    final active = ref.read(activeWarehousesProvider);
    _warehouseId = active.isEmpty ? null : active.first.id;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Product? _product(List<Product> products) {
    for (final p in products) {
      if (p.id == _productId) return p;
    }
    return null;
  }

  /// The signed change to send, or `null` if the input doesn't describe one.
  int? _delta(Product product) {
    final entered = int.tryParse(_quantity.text.trim());
    final type = _type;
    if (entered == null || type == null) return null;
    return signedMovementDelta(
      type: type,
      entered: entered,
      currentStock: product.currentStock,
      adjustDown: _adjustDown,
    );
  }

  Future<void> _save(List<Product> products, List<StockMovementType> allowedTypes) async {
    if (!_formKey.currentState!.validate()) return;
    final product = _product(products);
    final type = _type;
    final warehouseId = _warehouseId;
    if (product == null || type == null || warehouseId == null || !allowedTypes.contains(type)) {
      return;
    }
    final delta = _delta(product);
    if (delta == null || delta == 0) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final outcome = await ref.read(movementsProvider.notifier).record(
            productId: product.id,
            warehouseId: warehouseId,
            type: type,
            quantity: delta,
            reason: _reason.text,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      final result = outcome.value;
      final note = outcome.queued
          ? '${type.label} saved on this computer — ${product.name} now shows '
              '${product.currentStock + delta}. It will sync when the connection is good.'
          : switch (result!.alert) {
              'out_of_stock' => '${product.name} is now out of stock.',
              'low_stock' => '${product.name} is running low (${result.currentStock} left).',
              _ => '${type.label} recorded — ${product.name} now has ${result.currentStock}.',
            };
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(note)));
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
    final theme = Theme.of(context);
    final productsState = ref.watch(productsProvider);
    final warehousesState = ref.watch(warehousesProvider);

    // The dropdowns below read their initial value once, so wait until the
    // products and warehouses are actually here rather than building them
    // empty and never picking up the selection afterwards.
    if (!productsState.hasValue || !warehousesState.hasValue) {
      final failure = productsState.hasError ? productsState.error : warehousesState.error;
      return AlertDialog(
        title: const Text('Record stock movement'),
        content: SizedBox(
          width: 440,
          child: failure == null
              ? const LoadingPanel(label: 'Loading products and warehouses…')
              : ErrorRetryCard(
                  error: failure,
                  onRetry: () {
                    ref.read(productsProvider.notifier).refresh();
                    ref.read(warehousesProvider.notifier).refresh();
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ],
      );
    }

    final products = ref.watch(productListProvider);
    final warehouses = ref.watch(activeWarehousesProvider);
    if (_warehouseId == null && warehouses.isNotEmpty) _warehouseId = warehouses.first.id;
    if (_productId != null && products.isNotEmpty && !products.any((p) => p.id == _productId)) {
      _productId = null;
    }
    final permissions = ref.watch(authControllerProvider).valueOrNull?.permissions ?? const [];
    final allowedTypes = allowedMovementTypes(permissions);
    final product = _product(products);

    // Keep the chosen type valid if the permission set changes (or arrives
    // after the dialog opened).
    if (_type == null || !allowedTypes.contains(_type)) {
      _type = allowedTypes.isEmpty ? null : allowedTypes.first;
    }

    // Warehouses can be disabled from another window while this is open.
    if (_warehouseId != null && !warehouses.any((w) => w.id == _warehouseId)) {
      _warehouseId = warehouses.isEmpty ? null : warehouses.first.id;
    }

    final blocker = allowedTypes.isEmpty
        ? "Your role isn't allowed to record any kind of stock movement."
        : warehouses.isEmpty
            ? 'There is no active warehouse. An owner or administrator needs to add or enable '
                'one before stock can be recorded.'
            : products.isEmpty
                ? 'There are no products yet. Add a product first.'
                : null;

    final entered = int.tryParse(_quantity.text.trim());
    String? preview;
    if (product != null && entered != null) {
      final delta = _delta(product);
      if (delta != null) {
        final after = product.currentStock + delta;
        preview = _type == StockMovementType.count
            ? 'System shows ${product.currentStock}; counted $entered → '
                '${delta == 0 ? 'no difference' : '${delta > 0 ? '+' : ''}$delta'}'
            : 'Stock will go from ${product.currentStock} to $after';
      }
    }

    return AlertDialog(
      title: const Text('Record stock movement'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (blocker != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(blocker),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'Warehouse'),
                  isExpanded: true,
                  items: [
                    for (final warehouse in warehouses)
                      DropdownMenuItem(
                        value: warehouse.id,
                        child: Text(warehouse.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) => setState(() => _warehouseId = value),
                  validator: (value) => value == null ? 'Select a warehouse' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _productId,
                  decoration: const InputDecoration(labelText: 'Product'),
                  isExpanded: true,
                  items: [
                    for (final p in products)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.name} · ${p.currentStock} ${p.unit}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) => setState(() => _productId = value),
                  validator: (value) => value == null ? 'Select a product' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<StockMovementType>(
                  key: ValueKey(allowedTypes.length),
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Movement type'),
                  isExpanded: true,
                  items: [
                    for (final type in allowedTypes)
                      DropdownMenuItem(
                        value: type,
                        child: Text(type.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: allowedTypes.isEmpty ? null : (value) => setState(() => _type = value),
                  validator: (value) => value == null ? 'Select a movement type' : null,
                ),
                if (_type == StockMovementType.adjustment) ...[
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Increase'), icon: Icon(Icons.add)),
                      ButtonSegment(value: true, label: Text('Decrease'), icon: Icon(Icons.remove)),
                    ],
                    selected: {_adjustDown},
                    onSelectionChanged: (s) => setState(() => _adjustDown = s.first),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _type == StockMovementType.count ? 'Counted quantity' : 'Quantity',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final parsed = int.tryParse((v ?? '').trim());
                    if (parsed == null) return 'Enter a whole number';
                    if (_type == StockMovementType.count) {
                      if (parsed < 0) return "Can't be negative";
                      if (product != null && parsed == product.currentStock) {
                        return 'That matches the system figure — nothing to record';
                      }
                      return null;
                    }
                    if (parsed <= 0) return 'Enter a number above zero';
                    if (product != null &&
                        (_type == StockMovementType.stockOut ||
                            (_type == StockMovementType.adjustment && _adjustDown)) &&
                        parsed > product.currentStock) {
                      return 'Only ${product.currentStock} in stock';
                    }
                    return null;
                  },
                ),
                if (preview != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      preview,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  decoration: InputDecoration(
                    labelText: (_type == StockMovementType.adjustment ||
                            _type == StockMovementType.count)
                        ? 'Reason'
                        : 'Reason / reference (optional)',
                  ),
                  validator: (v) {
                    final needed = _type == StockMovementType.adjustment ||
                        _type == StockMovementType.count;
                    return needed && (v == null || v.trim().isEmpty)
                        ? 'Say why — it goes in the audit trail'
                        : null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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
        ElevatedButton(
          onPressed: (_saving || blocker != null) ? null : () => _save(products, allowedTypes),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
