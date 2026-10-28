import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../data/reorder.dart';
import '../domain/purchase.dart';
import 'purchase_form_dialog.dart';

/// Products at or below their reorder level, grouped by usual supplier, each
/// with a suggested quantity (up to its maximum stock, or twice its reorder
/// level). Untick or change quantities, then "Create purchase order" opens a
/// new purchase for that supplier with those lines at the product's cost.
/// Pass [supplierId] to show one supplier's products only.
class ReorderDialog extends ConsumerStatefulWidget {
  const ReorderDialog({super.key, this.supplierId});

  final String? supplierId;

  @override
  ConsumerState<ReorderDialog> createState() => _ReorderDialogState();
}

class _ReorderDialogState extends ConsumerState<ReorderDialog> {
  final Map<String, TextEditingController> _qty = {};
  final Set<String> _skipped = {};

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(ReorderLine line) =>
      _qty.putIfAbsent(line.product.id, () => TextEditingController(text: '${line.suggested}'));

  void _order(ReorderGroup group) {
    final lines = [
      for (final l in group.lines)
        if (!_skipped.contains(l.product.id) && (int.tryParse(_controller(l).text.trim()) ?? 0) > 0)
          PurchaseLineInput(
            productId: l.product.id,
            quantity: int.parse(_controller(l).text.trim()),
            unitCost: l.product.purchasePrice,
          ),
    ];
    if (lines.isEmpty) return;
    Navigator.of(context).pop();
    showDialog(
      context: context,
      builder: (_) => PurchaseFormDialog(initialSupplierId: group.supplierId, initialLines: lines),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final canCreate = hasPermission(ref, Permissions.purchasesCreate);
    final groups = ref
        .watch(reorderGroupsProvider)
        .where((g) => widget.supplierId == null || g.supplierId == widget.supplierId)
        .toList();

    return AlertDialog(
      title: const Text('Reorder suggestions'),
      content: SizedBox(
        width: 680,
        child: groups.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nothing is at or below its reorder level. 👍', key: Key('reorder-empty')),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Products at or below their reorder level, by usual supplier. Suggested: up to the maximum stock, '
                      'or twice the reorder level.',
                      style: muted,
                    ),
                    for (final g in groups) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.supplierName,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (canCreate)
                            ElevatedButton.icon(
                              key: ValueKey('reorder-order-${g.supplierId ?? 'none'}'),
                              onPressed: () => _order(g),
                              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                              label: const Text('Create purchase order'),
                            ),
                        ],
                      ),
                      for (final l in g.lines)
                        Row(
                          key: ValueKey('reorder-line-${l.product.id}'),
                          children: [
                            Checkbox(
                              value: !_skipped.contains(l.product.id),
                              onChanged: (v) => setState(() {
                                v == true ? _skipped.remove(l.product.id) : _skipped.add(l.product.id);
                              }),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${l.product.name} · ${l.product.sku}', overflow: TextOverflow.ellipsis),
                                  Text(
                                    [
                                      l.product.currentStock <= 0
                                          ? 'Out of stock'
                                          : '${l.product.currentStock} ${l.product.unit} left',
                                      'reorder at ${l.product.minStock}',
                                      if (l.product.maxStock != null) 'max ${l.product.maxStock}',
                                      'cost ${currencyFormat.format(l.product.purchasePrice)}',
                                    ].join(' · '),
                                    style: muted,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                key: ValueKey('reorder-qty-${l.product.id}'),
                                controller: _controller(l),
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: InputDecoration(isDense: true, suffixText: l.product.unit),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
