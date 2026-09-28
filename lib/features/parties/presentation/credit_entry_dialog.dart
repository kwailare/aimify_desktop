import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../data/parties_repository.dart';
import '../domain/party.dart';

/// Record a payment, a charge or an adjustment on one party's credit ledger.
///
/// For a customer a *charge* is a sale on credit and a *payment* is money
/// received; for a supplier a *charge* is an invoice from them and a *payment*
/// is money you paid. The balance is what is still owed either way. The entry
/// is sent now on a good connection, otherwise saved on this computer and
/// synced later.
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
          _isCustomer ? 'Add a credit sale for ${widget.party.name}' : 'Add an invoice from ${widget.party.name}',
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
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              outcome.queued
                  ? '${widget.kind.label} saved on this computer — it will sync when the '
                      'connection is good.'
                  : '${widget.kind.label} recorded — balance is now '
                      '${currencyFormat.format(outcome.value!.balanceOwed)}.',
            ),
          ),
        );
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Record ${widget.kind.label.toLowerCase()}'),
        ),
      ],
    );
  }
}
