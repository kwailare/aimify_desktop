import 'package:flutter/material.dart';
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
import '../domain/legacy_purchase.dart';
import '../domain/purchase.dart';

String _norm(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// The product an old purchase line names, matched ignoring case and spacing.
Product? matchProductByName(List<Product> products, String name) {
  final wanted = _norm(name);
  for (final p in products) {
    if (!p.isArchived && !p.isPending && (_norm(p.name) == wanted || _norm(p.sku) == wanted)) {
      return p;
    }
  }
  return null;
}

/// Offers purchases saved on this computer by older versions of the app for
/// import. Each becomes a Draft on the server (nothing touches stock until
/// it's received); supplier and product names are matched to real ones, and
/// anything unmatched can be picked by hand or the line left out.
class ImportLegacyPurchasesDialog extends ConsumerStatefulWidget {
  const ImportLegacyPurchasesDialog({super.key});

  @override
  ConsumerState<ImportLegacyPurchasesDialog> createState() => _ImportLegacyPurchasesDialogState();
}

class _ImportLegacyPurchasesDialogState extends ConsumerState<ImportLegacyPurchasesDialog> {
  /// Purchase id to chosen supplier id.
  final Map<String, String?> _supplier = {};

  /// `purchaseId#lineIndex` to the chosen product id (null = leave out).
  final Map<String, String?> _product = {};
  String? _warehouseId;
  String? _busyId;
  final Map<String, String> _errors = {};
  /// Each list is matched once, as soon as it has loaded; choices made by
  /// hand afterwards are kept.
  bool _suppliersMatched = false;
  bool _productsMatched = false;

  void _seed(List<LegacyPurchase> legacy, List<SupplierOption> suppliers, List<Product> products) {
    if (!_suppliersMatched && suppliers.isNotEmpty) {
      for (final p in legacy) {
        _supplier[p.id] = matchSupplierByName(suppliers, p.supplierName)?.id;
      }
      _suppliersMatched = true;
    }
    if (!_productsMatched && products.isNotEmpty) {
      for (final p in legacy) {
        for (var i = 0; i < p.items.length; i++) {
          _product['${p.id}#$i'] = matchProductByName(products, p.items[i].productName)?.id;
        }
      }
      _productsMatched = true;
    }
  }

  Future<void> _import(LegacyPurchase p) async {
    final supplierId = _supplier[p.id];
    final warehouseId = _warehouseId;
    final lines = [
      for (var i = 0; i < p.items.length; i++)
        if (_product['${p.id}#$i'] != null)
          PurchaseLineInput(
            productId: _product['${p.id}#$i']!,
            quantity: p.items[i].quantity,
            unitCost: p.items[i].unitCost,
          ),
    ];
    if (supplierId == null || warehouseId == null || lines.isEmpty) {
      setState(
        () => _errors[p.id] = supplierId == null
            ? 'Choose the supplier.'
            : lines.isEmpty
            ? 'Match at least one product.'
            : 'Choose a warehouse.',
      );
      return;
    }
    final canPay = hasPermission(ref, Permissions.creditRecord);
    final total = lines.fold(0.0, (s, l) => s + l.lineTotal);
    setState(() {
      _busyId = p.id;
      _errors.remove(p.id);
    });
    try {
      await ref
          .read(purchasesRepositoryProvider)
          .create(
            PurchaseInput(
              supplierId: supplierId,
              warehouseId: warehouseId,
              lines: lines,
              orderDate: p.date,
              notes: 'Imported from this computer',
              amountPaid: canPay ? p.amountPaid.clamp(0, total).toDouble() : 0,
            ),
            clientRef: 'legacy:${p.id}',
          );
      ref.read(legacyPurchasesProvider.notifier).remove(p.id);
      await ref.read(purchasesProvider.notifier).refresh();
    } catch (e) {
      if (mounted) setState(() => _errors[p.id] = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _discard(LegacyPurchase p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this purchase?'),
        content: Text(
          'The purchase from "${p.supplierName}" on ${dateFormat.format(p.date)} will be deleted from '
          'this computer. It was never sent to the server, so this can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            key: const Key('legacy-confirm-discard'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) ref.read(legacyPurchasesProvider.notifier).remove(p.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final legacy = ref.watch(legacyPurchasesProvider);
    final suppliers = (ref.watch(supplierOptionsProvider).valueOrNull ?? const <SupplierOption>[])
        .where((s) => !s.isArchived)
        .toList();
    final products =
        ref.watch(productListProvider).where((p) => !p.isArchived && !p.isPending).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final warehouses = ref.watch(activeWarehousesProvider);
    _warehouseId ??= warehouses.isEmpty ? null : warehouses.first.id;
    _seed(legacy, suppliers, products);
    final canPay = hasPermission(ref, Permissions.creditRecord);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      title: const Text('Purchases saved on this computer'),
      content: SizedBox(
        width: 720,
        child: legacy.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text('All done — nothing left to import.'),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Earlier versions of the app saved these purchases only on this computer. Each one '
                      'imports as a Draft: nothing touches stock until you receive it.'
                      '${canPay ? '' : ' Amounts paid aren\'t imported, because your role can\'t record payments.'}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 300,
                      child: DropdownButtonFormField<String>(
                        initialValue: _warehouseId,
                        decoration: const InputDecoration(labelText: 'Deliver to'),
                        items: [
                          for (final w in warehouses)
                            DropdownMenuItem(value: w.id, child: Text(w.name)),
                        ],
                        onChanged: (v) => setState(() => _warehouseId = v),
                      ),
                    ),
                    for (final p in legacy)
                      Card(
                        key: ValueKey('legacy-${p.id}'),
                        margin: const EdgeInsets.only(top: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${dateFormat.format(p.date)} · "${p.supplierName}" · ${currencyFormat.format(p.totalCost)}'
                                '${p.amountPaid > 0 ? ' · ${currencyFormat.format(p.amountPaid)} paid' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                key: ValueKey('legacy-supplier-${p.id}-$_suppliersMatched'),
                                initialValue: _supplier[p.id],
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Supplier',
                                  isDense: true,
                                ),
                                items: [
                                  for (final s in suppliers)
                                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                                ],
                                onChanged: (v) => setState(() => _supplier[p.id] = v),
                              ),
                              for (var i = 0; i < p.items.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '"${p.items[i].productName}" × ${p.items[i].quantity} at '
                                          '${currencyFormat.format(p.items[i].unitCost)}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 260,
                                        child: DropdownButtonFormField<String?>(
                                          key: ValueKey('legacy-product-${p.id}-$i-$_productsMatched'),
                                          initialValue: _product['${p.id}#$i'],
                                          isExpanded: true,
                                          decoration: const InputDecoration(isDense: true),
                                          items: [
                                            const DropdownMenuItem<String?>(
                                              value: null,
                                              child: Text('Leave this line out'),
                                            ),
                                            for (final prod in products)
                                              DropdownMenuItem<String?>(
                                                value: prod.id,
                                                child: Text(
                                                  prod.name,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                          onChanged: (v) =>
                                              setState(() => _product['${p.id}#$i'] = v),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_errors[p.id] != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _errors[p.id]!,
                                  style: TextStyle(color: theme.colorScheme.error),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    key: ValueKey('legacy-dismiss-${p.id}'),
                                    onPressed: _busyId != null ? null : () => _discard(p),
                                    child: const Text('Discard'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    key: ValueKey('legacy-import-${p.id}'),
                                    onPressed: _busyId != null ? null : () => _import(p),
                                    child: Text(_busyId == p.id ? 'Importing…' : 'Import as draft'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
