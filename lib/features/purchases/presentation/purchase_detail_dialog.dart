import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../products/data/products_repository.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';
import 'purchase_form_dialog.dart';

StatusPill purchaseStatusPill(PurchaseStatus status) => StatusPill(
  label: status.label,
  tone: switch (status) {
    PurchaseStatus.draft => StatusTone.neutral,
    PurchaseStatus.pending => StatusTone.warning,
    PurchaseStatus.partiallyReceived => StatusTone.warning,
    PurchaseStatus.received => StatusTone.positive,
    PurchaseStatus.cancelled => StatusTone.negative,
  },
);

StatusPill purchasePaymentPill(Purchase purchase) {
  if (purchase.status == PurchaseStatus.cancelled) {
    return const StatusPill(label: '—', tone: StatusTone.neutral);
  }
  if (purchase.isPaid) return const StatusPill(label: 'Paid', tone: StatusTone.positive);
  if (purchase.amountPaid > 0) {
    return const StatusPill(label: 'Part paid', tone: StatusTone.warning);
  }
  return const StatusPill(label: 'Unpaid', tone: StatusTone.negative);
}

/// One purchase in full: its lines with how much has arrived, totals and
/// payments, each delivery received, and the actions its status allows.
class PurchaseDetailDialog extends ConsumerWidget {
  const PurchaseDetailDialog({super.key, required this.purchaseId});

  final String purchaseId;

  void _toast(BuildContext context, String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _placeOrder(BuildContext context, WidgetRef ref, Purchase p) async {
    try {
      await ref.read(purchasesProvider.notifier).placeOrder(p.id);
      if (context.mounted) _toast(context, '${p.reference} is now ordered.');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Purchase p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Cancel ${p.reference}?'),
        content: Text(
          p.amountPaid > 0
              ? '${currencyFormat.format(p.amountPaid)} was paid on this purchase. It will be recorded as '
                    'owed back to ${p.supplierName}, and shown as a credit on their account.'
              : 'Nothing has been received or paid, so nothing else changes. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            key: const Key('purchase-confirm-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel purchase'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final refund = await ref.read(purchasesProvider.notifier).cancel(p.id);
      if (!context.mounted) return;
      _toast(
        context,
        refund > 0
            ? '${p.reference} cancelled. ${p.supplierName} owes back ${currencyFormat.format(refund)}.'
            : '${p.reference} cancelled.',
      );
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(purchaseDetailProvider(purchaseId));
    final theme = Theme.of(context);

    return state.when(
      loading: () => const AlertDialog(
        content: SizedBox(width: 640, child: LoadingPanel(label: 'Loading purchase…')),
      ),
      error: (error, _) => AlertDialog(
        content: SizedBox(
          width: 640,
          child: ErrorRetryCard(
            error: error,
            onRetry: () => ref.invalidate(purchaseDetailProvider(purchaseId)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
      data: (p) {
        final canCreate = hasPermission(ref, Permissions.purchasesCreate);
        final canReceive = hasPermission(ref, Permissions.purchasesReceive) && p.status.canReceive;
        final canCancel = hasPermission(ref, Permissions.purchasesCancel) && p.canCancel;
        final canPay =
            hasPermission(ref, Permissions.creditRecord) &&
            p.status != PurchaseStatus.cancelled &&
            p.balance > 0.004;
        final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
        final productName = {for (final l in p.lines) l.productId: l.productName};

        Widget money(String label, double value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
              SizedBox(
                width: 130,
                child: Text(
                  currencyFormat.format(value),
                  textAlign: TextAlign.end,
                  style: strong ? const TextStyle(fontWeight: FontWeight.w800) : null,
                ),
              ),
            ],
          ),
        );

        return AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text('${p.reference} · ${p.supplierName}', overflow: TextOverflow.ellipsis),
              ),
              purchaseStatusPill(p.status),
            ],
          ),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    [
                      'Into ${p.warehouseName}',
                      'ordered ${dateFormat.format(p.orderDate)}',
                      if (p.expectedDate != null) 'expected ${dateFormat.format(p.expectedDate!)}',
                      if (p.createdByName != null) 'by ${p.createdByName}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  if (p.notes != null) ...[const SizedBox(height: 6), Text(p.notes!)],
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 24,
                      headingRowHeight: 36,
                      dataRowMinHeight: 36,
                      dataRowMaxHeight: 44,
                      columns: const [
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('Ordered'), numeric: true),
                        DataColumn(label: Text('Received'), numeric: true),
                        DataColumn(label: Text('Unit cost'), numeric: true),
                        DataColumn(label: Text('Line total'), numeric: true),
                      ],
                      rows: [
                        for (final l in p.lines)
                          DataRow(
                            key: ValueKey('purchase-detail-line-${l.id}'),
                            cells: [
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 220),
                                  child: Text(
                                    '${l.productName} · ${l.sku}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(Text('${l.quantity} ${l.unit}')),
                              DataCell(
                                Text(
                                  '${l.receivedQuantity}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: l.outstanding == 0 ? const Color(0xFF2F8F5B) : null,
                                  ),
                                ),
                              ),
                              DataCell(Text(currencyFormat.format(l.unitCost))),
                              DataCell(Text(currencyFormat.format(l.lineTotal))),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        money('Goods', p.subtotal),
                        if (p.discount > 0) money('Discount', -p.discount),
                        if (p.tax > 0) money(orgTaxRate > 0 ? orgTaxName : 'Tax', p.tax),
                        money('Total', p.total, strong: true),
                        money('Paid', p.amountPaid),
                        if (p.status != PurchaseStatus.cancelled)
                          money('Still owed', p.balance, strong: true),
                      ],
                    ),
                  ),
                  if (p.status == PurchaseStatus.draft || p.status == PurchaseStatus.pending) ...[
                    const SizedBox(height: 8),
                    Text(
                      p.amountPaid > 0
                          ? 'The total goes on ${p.supplierName}\'s account when the first goods arrive, with what was paid.'
                          : 'The total goes on ${p.supplierName}\'s account when the first goods arrive.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                  if (p.receipts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Deliveries',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    for (final r in p.receipts)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${dateTimeFormat.format(r.createdAt)}${r.userName == null ? '' : ' · ${r.userName}'} — '
                          '${r.lines.map((l) => '${l.quantity} ${productName[l.productId] ?? 'units'}').join(', ')}',
                        ),
                      ),
                  ],
                  if (p.payments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Payments',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    for (final pay in p.payments)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${dateTimeFormat.format(pay.createdAt)} — ${currencyFormat.format(pay.amount)}'
                          '${pay.note == null ? '' : ' · ${pay.note}'}${pay.userName == null ? '' : ' · ${pay.userName}'}',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            if (canCancel)
              TextButton(
                key: const Key('purchase-cancel'),
                onPressed: () => _cancel(context, ref, p),
                child: Text('Cancel purchase', style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (canCreate && p.canEdit)
              OutlinedButton(
                key: const Key('purchase-edit'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PurchaseFormDialog(purchase: p),
                ),
                child: const Text('Edit'),
              ),
            if (canCreate && p.status == PurchaseStatus.draft)
              OutlinedButton(
                key: const Key('purchase-place'),
                onPressed: () => _placeOrder(context, ref, p),
                child: const Text('Place order'),
              ),
            if (canPay)
              OutlinedButton(
                key: const Key('purchase-pay'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => PurchasePaymentDialog(purchase: p),
                ),
                child: const Text('Record payment'),
              ),
            if (canReceive)
              ElevatedButton.icon(
                key: const Key('purchase-receive'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => ReceivePurchaseDialog(purchase: p),
                ),
                icon: const Icon(Icons.inventory_outlined, size: 18),
                label: const Text('Receive goods'),
              ),
          ],
        );
      },
    );
  }
}

/// Records what arrived, line by line. Each line starts at what is still
/// outstanding; lower it for a short delivery.
class ReceivePurchaseDialog extends ConsumerStatefulWidget {
  const ReceivePurchaseDialog({super.key, required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<ReceivePurchaseDialog> createState() => _ReceivePurchaseDialogState();
}

class _ReceivePurchaseDialogState extends ConsumerState<ReceivePurchaseDialog> {
  late final Map<String, TextEditingController> _quantities = {
    for (final l in widget.purchase.lines)
      if (l.outstanding > 0) l.id: TextEditingController(text: '${l.outstanding}'),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _receive() async {
    final lines = <String, int>{};
    for (final l in widget.purchase.lines) {
      final controller = _quantities[l.id];
      if (controller == null) continue;
      final qty = int.tryParse(controller.text.trim()) ?? 0;
      if (qty < 0 || qty > l.outstanding) {
        setState(() => _error = '${l.productName}: enter 0 to ${l.outstanding}.');
        return;
      }
      if (qty > 0) lines[l.id] = qty;
    }
    if (lines.isEmpty) {
      setState(() => _error = 'Enter how many of at least one product arrived.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(purchasesProvider.notifier)
          .receive(widget.purchase.id, lines: lines);
      if (!mounted) return;
      final names = {for (final p in ref.read(productListProvider)) p.id: p.name};
      final units = lines.values.fold(0, (a, b) => a + b);
      final priceNote = outcome.priceChanges.isEmpty
          ? ''
          : ' Purchase price updated for ${outcome.priceChanges.map((c) => names[c.productId] ?? 'a product').join(', ')}.';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '$units unit${units == 1 ? '' : 's'} received into ${widget.purchase.warehouseName}.$priceNote',
            ),
          ),
        );
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
    final open = widget.purchase.lines.where((l) => l.outstanding > 0).toList();
    return AlertDialog(
      title: Text('Receive ${widget.purchase.reference}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Into ${widget.purchase.warehouseName}. Lower a number if less arrived; the rest stays on order.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final l in open)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.productName} · ${l.outstanding} of ${l.quantity} outstanding',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        key: ValueKey('receive-qty-${l.id}'),
                        controller: _quantities[l.id],
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(isDense: true, suffixText: l.unit),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('receive-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('receive-confirm'),
          onPressed: _saving ? null : _receive,
          child: Text(_saving ? 'Receiving…' : 'Receive'),
        ),
      ],
    );
  }
}

class PurchasePaymentDialog extends ConsumerStatefulWidget {
  const PurchasePaymentDialog({super.key, required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<PurchasePaymentDialog> createState() => _PurchasePaymentDialogState();
}

class _PurchasePaymentDialogState extends ConsumerState<PurchasePaymentDialog> {
  late final _amount = TextEditingController(
    text: widget.purchase.balance == widget.purchase.balance.roundToDouble()
        ? widget.purchase.balance.toInt().toString()
        : widget.purchase.balance.toStringAsFixed(2),
  );
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount above 0.');
      return;
    }
    if (amount > widget.purchase.balance + 0.004) {
      setState(
        () => _error = 'Only ${currencyFormat.format(widget.purchase.balance)} is still owed.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(purchasesProvider.notifier)
          .pay(widget.purchase.id, amount: amount, note: _note.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${currencyFormat.format(amount)} paid on ${widget.purchase.reference}.'),
          ),
        );
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
    final posted = widget.purchase.postedAt != null;
    return AlertDialog(
      title: Text('Pay ${widget.purchase.supplierName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.purchase.reference} · ${currencyFormat.format(widget.purchase.balance)} still owed',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('payment-amount'),
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. Bank transfer',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              posted
                  ? 'Also recorded as a payment on the supplier\'s account.'
                  : 'Nothing has arrived yet, so this goes on the supplier\'s account with the first delivery.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const Key('payment-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('payment-confirm'),
          onPressed: _saving ? null : _pay,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}
