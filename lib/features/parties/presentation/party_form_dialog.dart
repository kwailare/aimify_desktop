import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/friendly_error.dart';
import '../data/parties_repository.dart';
import '../domain/party.dart';

/// Add or edit a customer or supplier against the real API. Pass [party] to
/// edit. With a poor or missing connection the change is saved on this
/// computer and synced later — the person is told so.
class PartyFormDialog extends ConsumerStatefulWidget {
  const PartyFormDialog({super.key, required this.type, this.party});

  final PartyType type;
  final Party? party;

  @override
  ConsumerState<PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends ConsumerState<PartyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.party?.name);
  late final _contact = TextEditingController(text: widget.party?.contactPerson);
  late final _phone = TextEditingController(text: widget.party?.phone);
  late final _email = TextEditingController(text: widget.party?.email);
  late final _address = TextEditingController(text: widget.party?.address);
  late final _notes = TextEditingController(text: widget.party?.notes);
  late final _creditLimit = TextEditingController(
    text: _num(widget.party?.creditLimit ?? 0),
  );

  bool _saving = false;
  String? _error;

  bool get _editing => widget.party != null;
  bool get _isCustomer => widget.type == PartyType.customer;

  static String _num(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _email, _address, _notes, _creditLimit]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final input = PartyInput(
      type: widget.type,
      name: _name.text.trim(),
      contactPerson: _isCustomer ? null : _optional(_contact),
      phone: _optional(_phone),
      email: _optional(_email),
      address: _optional(_address),
      notes: _optional(_notes),
      creditLimit: _isCustomer ? (double.tryParse(_creditLimit.text.trim()) ?? 0) : 0,
    );

    setState(() {
      _saving = true;
      _error = null;
    });

    final notifier = ref.read(partiesProvider(widget.type).notifier);
    try {
      final outcome = _editing
          ? await notifier.edit(widget.party!.id, input)
          : await notifier.add(input);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      if (outcome.queued) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Saved on this computer — it will sync when the connection is good.'),
            ),
          );
      }
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
    final noun = widget.type.label.toLowerCase();

    return AlertDialog(
      title: Text(_editing ? 'Edit $noun' : 'Add $noun'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: _isCustomer ? 'Customer name *' : 'Business name *'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (v.trim().length > 200) return 'At most 200 characters';
                    return null;
                  },
                ),
                if (!_isCustomer) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contact,
                    decoration: const InputDecoration(labelText: 'Contact person'),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                if (_isCustomer) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _creditLimit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Credit limit',
                      helperText: 'The most this customer may owe you. 0 means no limit is set.',
                    ),
                    validator: (v) {
                      final parsed = double.tryParse((v ?? '').trim());
                      if (parsed == null || parsed < 0) return 'Enter 0 or more';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_editing ? 'Save changes' : 'Add $noun'),
        ),
      ],
    );
  }
}
