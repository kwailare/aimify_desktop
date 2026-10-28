import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/sync_engine.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../documents/debt_documents.dart';
import '../../documents/document_preview.dart';
import '../../sales/domain/sale.dart';
import '../data/parties_repository.dart';
import '../domain/party.dart';

typedef CreditEntryResult = SubmitResult<({CreditEntry entry, double balanceOwed})>;

/// Opens the receipt for a payment a customer made on their account.
void printAccountReceipt(BuildContext context, WidgetRef ref, Party customer, CreditEntry entry) {
  ref.read(documentOpenerProvider).open(
        context,
        ref,
        title: 'Receipt ${entry.receiptNumber ?? ''}'.trim(),
        fileName: '${entry.receiptNumber ?? 'receipt'}.pdf',
        build: (kit) => buildAccountReceipt(kit, customer, entry),
      );
}

/// Opens the form for [kind] on [party]'s account, then says what happened:
/// the new balance, which invoices a payment settled (oldest first), and for
/// a customer's payment a "Print receipt" action. Offline, that it was saved
/// on this computer.
Future<void> recordCreditEntry(BuildContext context, WidgetRef ref, Party party, CreditKind kind) async {
  final result = await showDialog<CreditEntryResult>(
    context: context,
    builder: (_) => CreditEntryDialog(party: party, kind: kind),
  );
  if (result == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final value = result.value;
  if (result.queued || value == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('${kind.label} saved on this computer — it will sync when the connection is good.'),
      ),
    );
    return;
  }
  final entry = value.entry;
  final settled = entry.allocations.map((a) => '${a.reference} ${currencyFormat.format(a.amount)}').join(', ');
  messenger.showSnackBar(
    SnackBar(
      duration: Duration(seconds: entry.receiptNumber != null ? 8 : 4),
      content: Text(
        [
          '${entry.receiptNumber ?? kind.label} recorded — balance is now ${currencyFormat.format(value.balanceOwed)}.',
          if (settled.isNotEmpty) 'Settled: $settled.',
        ].join(' '),
      ),
      action: entry.receiptNumber == null
          ? null
          : SnackBarAction(label: 'Print receipt', onPressed: () => printAccountReceipt(context, ref, party, entry)),
    ),
  );
}

/// Record a payment, a charge or an adjustment on one party's credit ledger.
///
/// For a customer a *charge* is money they owe outside a sale (an opening
/// balance, a fee) and a *payment* is money received; for a supplier a
/// *charge* is an invoice from them and a *payment* is money you paid. A
/// payment settles the oldest debts first. The balance is what is still owed
/// either way. The entry is sent now on a good connection, otherwise saved on
/// this computer and synced later. Pops with the outcome.
class CreditEntryDialog extends ConsumerStatefulWidget {
  const CreditEntryDialog({super.key, required this.party, required this.kind});

  final Party party;
  final CreditKind kind;

  @override
  ConsumerState<CreditEntryDialog> createState() => _CreditEntryDialogState();
}

class _CreditEntryDialogState extends ConsumerState<CreditEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  SalePaymentMethod _method = SalePaymentMethod.cash;
  bool _decrease = false;
  bool _saving = false;
  String? _error;

  bool get _isCustomer => widget.party.type == PartyType.customer;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
        CreditKind.payment => _isCustomer
            ? 'Record payment from ${widget.party.name}'
            : 'Record payment to ${widget.party.name}',
        CreditKind.charge =>
          _isCustomer ? 'Add a charge for ${widget.party.name}' : 'Add an invoice from ${widget.party.name}',
        CreditKind.adjustment => 'Adjust ${widget.party.name}\'s balance',
      };

  String get _amountLabel => switch (widget.kind) {
        CreditKind.payment => 'Payment amount',
        CreditKind.charge => 'Amount',
        CreditKind.adjustment => 'Adjustment amount',
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final entered = double.parse(_amount.text.trim());
    // An adjustment is signed; charges and payments are sent positive.
    final amount = widget.kind == CreditKind.adjustment && _decrease ? -entered : entered;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final outcome = await ref.read(creditServiceProvider).record(
            partyType: widget.party.type,
            partyId: widget.party.id,
            kind: widget.kind,
            amount: amount,
            note: _note.text,
            method: widget.kind == CreditKind.payment ? _method.apiValue : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop<CreditEntryResult>(outcome);
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
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    // The party as the screens show it, including entries still waiting to sync.
    final live = ref
            .watch(partyListProvider(widget.party.type))
            .where((p) => p.id == widget.party.id)
            .firstOrNull ??
        widget.party;
    final balance = live.balanceOwed;

    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Currently owed: ${currencyFormat.format(balance)}'),
              if (_isCustomer && widget.kind == CreditKind.charge && live.creditLimit > 0)
                Text(
                  'Credit limit: ${currencyFormat.format(live.creditLimit)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              if (widget.kind == CreditKind.payment)
                Text(
                  'Settles the oldest invoices first.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              if (widget.kind == CreditKind.charge)
                Text(
                  'Due in ${live.paymentTermsDays} days (their payment terms).',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              const SizedBox(height: 16),
              if (widget.kind == CreditKind.adjustment) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Increase'), icon: Icon(Icons.add)),
                    ButtonSegment(value: true, label: Text('Decrease'), icon: Icon(Icons.remove)),
                  ],
                  selected: {_decrease},
                  onSelectionChanged: (s) => setState(() => _decrease = s.first),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('credit-amount'),
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: _amountLabel),
                validator: (v) {
                  final parsed = double.tryParse((v ?? '').trim());
                  if (parsed == null || parsed <= 0) return 'Enter an amount above zero';
                  if (widget.kind == CreditKind.payment && parsed > balance) {
                    return "Can't be more than what is owed";
                  }
                  return null;
                },
              ),
              if (widget.kind == CreditKind.payment) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<SalePaymentMethod>(
                  key: const Key('credit-method'),
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: 'Paid by'),
                  items: [for (final m in SalePaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
                  onChanged: _saving ? null : (v) => setState(() => _method = v ?? SalePaymentMethod.cash),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: widget.kind == CreditKind.adjustment ? 'Reason' : 'Note (optional)',
                  counterText: '',
                ),
                validator: (v) => widget.kind == CreditKind.adjustment && (v ?? '').trim().isEmpty
                    ? 'Say why — it goes in the audit trail'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('credit-save'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Record ${widget.kind.label.toLowerCase()}'),
        ),
      ],
    );
  }
}
