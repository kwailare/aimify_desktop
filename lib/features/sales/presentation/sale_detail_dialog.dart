import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../documents/document_preview.dart';
import '../../documents/sale_documents.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import 'sale_form_dialog.dart';

StatusPill salePaymentPill(Sale sale) {
  if (sale.isVoided) return const StatusPill(label: 'Voided', tone: StatusTone.neutral);
  if (sale.isPaid) return const StatusPill(label: 'Paid', tone: StatusTone.positive);
  if (sale.amountPaid > 0) return const StatusPill(label: 'Part paid', tone: StatusTone.warning);
  return const StatusPill(label: 'Unpaid', tone: StatusTone.negative);
}

/// When an unpaid sale is due: the date, or how many days overdue.
Widget saleDueCell(Sale s, ThemeData theme) {
  if (s.isVoided || s.balance <= 0.004 || s.dueDate == null) return const Text('—');
  if (s.daysOverdue > 0) {
    return Text(
      '${s.daysOverdue}d overdue',
      style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w700),
    );
  }
  return Text(dateFormat.format(s.dueDate!));
}

Party? _customerOf(WidgetRef ref, Sale s) => s.customerId == null
    ? null
    : ref.read(partyListProvider(PartyType.customer)).where((c) => c.id == s.customerId).firstOrNull;

void printInvoice(BuildContext context, WidgetRef ref, Sale s) {
  final customer = _customerOf(ref, s);
  ref.read(documentOpenerProvider).open(
        context,
        ref,
        title: 'Invoice ${s.reference}',
        fileName: '${s.reference}.pdf',
        build: (kit) => buildInvoice(kit, s, customer: customer),
      );
}

/// Opens the new-sale form and, once it's completed, says so with a
/// "Print invoice" action (or that it was saved offline), and warns about
/// any product the sale took low or out of stock.
Future<void> recordSale(BuildContext context, WidgetRef ref, {String? customerId}) async {
  final result = await showDialog<SaleFormResult>(
    context: context,
    builder: (_) => SaleFormDialog(initialCustomerId: customerId),
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final outcome = result.outcome;
  if (result.queued || outcome == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Sale saved on this computer — it will be sent when you're back online.")),
    );
    return;
  }
  final sale = outcome.sale;
  final low = outcome.alerts.length;
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(
        '${sale.reference} completed · ${currencyFormat.format(sale.total)}'
        '${sale.balance > 0.004 ? ' · ${currencyFormat.format(sale.balance)} on credit' : ''}'
        '${low > 0 ? ' · $low product${low == 1 ? '' : 's'} now low or out of stock' : ''}',
      ),
      action: SnackBarAction(label: 'Print invoice', onPressed: () => printInvoice(context, ref, sale)),
    ),
  );
}

/// One sale in full: its lines, totals and payments (each with a receipt),
/// and Print invoice, Record payment and Void as the role allows.
class SaleDetailDialog extends ConsumerWidget {
  const SaleDetailDialog({super.key, required this.saleId});

  final String saleId;

  Future<void> _void(BuildContext context, WidgetRef ref, Sale s) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _VoidSaleDialog(sale: s));
    if (reason == null || !context.mounted) return;
    try {
      final result = await ref.read(salesProvider.notifier).voidSale(s.id, reason: reason);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              [
                '${s.reference} voided — the stock is back.',
                if (result.creditedToAccount > 0)
                  '${currencyFormat.format(result.creditedToAccount)} they paid went to their other invoices.',
                if (result.refundOwed > 0) 'Refund ${currencyFormat.format(result.refundOwed)} to ${s.customerName}.',
              ].join(' '),
            ),
          ),
        );
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(saleDetailProvider(saleId));
    final theme = Theme.of(context);

    return state.when(
      loading: () => const AlertDialog(
        content: SizedBox(width: 640, child: LoadingPanel(label: 'Loading sale…')),
      ),
      error: (error, _) => AlertDialog(
        content: SizedBox(
          width: 640,
          child: ErrorRetryCard(error: error, onRetry: () => ref.invalidate(saleDetailProvider(saleId))),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
      data: (s) {
        final canPay = hasPermission(ref, Permissions.creditRecord) && !s.isVoided && s.balance > 0.004;
        final canVoid = hasPermission(ref, Permissions.salesVoid) && !s.isVoided;
        final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

        Widget money(String label, double value, {bool strong = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted))),
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
              Expanded(child: Text('${s.reference} · ${s.customerName}', overflow: TextOverflow.ellipsis)),
              salePaymentPill(s),
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
                      'From ${s.warehouseName}',
                      dateTimeFormat.format(s.saleDate),
                      if (s.dueDate != null && !s.isVoided && s.balance > 0.004) 'due ${dateFormat.format(s.dueDate!)}',
                      if (s.createdByName != null) 'by ${s.createdByName}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  if (s.daysOverdue > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${currencyFormat.format(s.balance)} is ${s.daysOverdue} day${s.daysOverdue == 1 ? '' : 's'} overdue.',
                        key: const Key('sale-overdue-note'),
                        style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (s.isVoided)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Voided${s.voidReason == null ? '' : ': ${s.voidReason}'} — the stock went back.',
                        key: const Key('sale-voided-note'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (s.overLimit)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Allowed over the customer\'s credit limit.',
                          style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    ),
                  if (s.notes != null) ...[const SizedBox(height: 6), Text(s.notes!)],
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
                        DataColumn(label: Text('Qty'), numeric: true),
                        DataColumn(label: Text('Price'), numeric: true),
                        DataColumn(label: Text('Line total'), numeric: true),
                      ],
                      rows: [
                        for (final l in s.lines)
                          DataRow(
                            key: ValueKey('sale-detail-line-${l.id}'),
                            cells: [
                              DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 260),
                                  child: Text('${l.productName} · ${l.sku}', overflow: TextOverflow.ellipsis),
                                ),
                              ),
                              DataCell(Text('${l.quantity} ${l.unit}')),
                              DataCell(
                                Text(
                                  l.discounted
                                      ? '${currencyFormat.format(l.unitPrice)} (was ${currencyFormat.format(l.listPrice)})'
                                      : currencyFormat.format(l.unitPrice),
                                ),
                              ),
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
                        money('Goods', s.subtotal),
                        if (s.discount > 0) money('Discount', -s.discount),
                        if (s.tax > 0) money(orgTaxRate > 0 ? orgTaxName : 'Tax', s.tax),
                        money('Total', s.total, strong: true),
                        money('Paid', s.amountPaid),
                        if (!s.isVoided) money('Still due', s.balance, strong: true),
                      ],
                    ),
                  ),
                  if (s.payments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Payments', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    for (final (i, pay) in s.payments.indexed)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${dateTimeFormat.format(pay.createdAt)} — ${currencyFormat.format(pay.amount)} · ${pay.method.label}'
                              '${pay.note == null ? '' : ' · ${pay.note}'}${pay.userName == null ? '' : ' · ${pay.userName}'}'
                              '${pay.receiptNumber == null || (pay.note ?? '').contains(pay.receiptNumber!) ? '' : ' · ${pay.receiptNumber}'}',
                            ),
                          ),
                          IconButton(
                            key: Key('print-sale-receipt-$i'),
                            tooltip: 'Receipt (PDF)',
                            icon: const Icon(Icons.print_outlined, size: 18),
                            onPressed: () {
                              final customer = _customerOf(ref, s);
                              ref.read(documentOpenerProvider).open(
                                    context,
                                    ref,
                                    title: 'Receipt ${s.reference}-RCPT-${i + 1}',
                                    fileName: '${s.reference}-RCPT-${i + 1}.pdf',
                                    build: (kit) => buildSaleReceipt(kit, s, i, customer: customer),
                                  );
                            },
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            TextButton.icon(
              key: const Key('print-invoice'),
              onPressed: () => printInvoice(context, ref, s),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Print invoice'),
            ),
            if (canVoid)
              TextButton(
                key: const Key('sale-void'),
                onPressed: () => _void(context, ref, s),
                child: Text('Void sale', style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (canPay)
              ElevatedButton(
                key: const Key('sale-pay'),
                onPressed: () => showDialog(context: context, builder: (_) => SalePaymentDialog(sale: s)),
                child: const Text('Record payment'),
              ),
          ],
        );
      },
    );
  }
}

/// Asks why the sale is being voided; returns the reason.
class _VoidSaleDialog extends StatefulWidget {
  const _VoidSaleDialog({required this.sale});

  final Sale sale;

  @override
  State<_VoidSaleDialog> createState() => _VoidSaleDialogState();
}

class _VoidSaleDialogState extends State<_VoidSaleDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sale;
    return AlertDialog(
      title: Text('Void ${s.reference}?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                'The ${s.units} unit${s.units == 1 ? '' : 's'} go back into ${s.warehouseName}.',
                if (!s.isWalkIn) "The sale comes off ${s.customerName}'s account.",
                if (s.amountPaid > 0 && s.isWalkIn)
                  '${currencyFormat.format(s.amountPaid)} was paid — refund it to ${s.customerName}.',
                if (s.amountPaid > 0 && !s.isWalkIn)
                  '${currencyFormat.format(s.amountPaid)} was paid: it first settles their other invoices, and anything left is to refund.',
                "This can't be undone.",
              ].join(' '),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('void-reason'),
              controller: _reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Entered by mistake'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep it')),
        ElevatedButton(
          key: const Key('void-confirm'),
          onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_reason.text.trim()),
          child: const Text('Void sale'),
        ),
      ],
    );
  }
}

/// Takes a later payment on a sale (part or all of what is still due).
class SalePaymentDialog extends ConsumerStatefulWidget {
  const SalePaymentDialog({super.key, required this.sale});

  final Sale sale;

  @override
  ConsumerState<SalePaymentDialog> createState() => _SalePaymentDialogState();
}

class _SalePaymentDialogState extends ConsumerState<SalePaymentDialog> {
  late final _amount = TextEditingController(
    text: widget.sale.balance == widget.sale.balance.roundToDouble()
        ? widget.sale.balance.toInt().toString()
        : widget.sale.balance.toStringAsFixed(2),
  );
  final _note = TextEditingController();
  SalePaymentMethod _method = SalePaymentMethod.cash;
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
    if (amount > widget.sale.balance + 0.004) {
      setState(() => _error = 'Only ${currencyFormat.format(widget.sale.balance)} is still due.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(salesProvider.notifier).pay(widget.sale.id, amount: amount, method: _method, note: _note.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${currencyFormat.format(amount)} received on ${widget.sale.reference}.')),
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
    final s = widget.sale;
    return AlertDialog(
      title: Text('Payment from ${s.customerName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.reference} · ${currencyFormat.format(s.balance)} still due'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sale-payment-amount'),
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SalePaymentMethod>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: [for (final m in SalePaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
              onChanged: _saving ? null : (v) => setState(() => _method = v ?? SalePaymentMethod.cash),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (!s.isWalkIn) ...[
              const SizedBox(height: 8),
              Text("Also recorded as a payment on the customer's account.",
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  key: const Key('sale-payment-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          key: const Key('sale-payment-confirm'),
          onPressed: _saving ? null : _pay,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}
