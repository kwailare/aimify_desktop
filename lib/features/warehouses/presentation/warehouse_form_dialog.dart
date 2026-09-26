import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/friendly_error.dart';
import '../data/warehouses_repository.dart';
import '../domain/warehouse.dart';

/// Create or edit a warehouse via `/api/v1/warehouses`. Pass [warehouse] to
/// edit. Only the name is required. Creating past the plan's active-warehouse
/// cap comes back as a friendly `plan_limit` message shown inline.
class WarehouseFormDialog extends ConsumerStatefulWidget {
  const WarehouseFormDialog({super.key, this.warehouse});

  final Warehouse? warehouse;

  @override
  ConsumerState<WarehouseFormDialog> createState() => _WarehouseFormDialogState();
}

class _WarehouseFormDialogState extends ConsumerState<WarehouseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.warehouse?.name);
  late final _address = TextEditingController(text: widget.warehouse?.address);
  late final _manager = TextEditingController(text: widget.warehouse?.managerName);
  late final _phone = TextEditingController(text: widget.warehouse?.phone);

  bool _saving = false;
  String? _error;

  bool get _editing => widget.warehouse != null;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _manager.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final notifier = ref.read(warehousesProvider.notifier);
    try {
      if (_editing) {
        // Empty text clears an optional field (sent as null).
        await notifier.edit(widget.warehouse!.id, {
          'name': _name.text.trim(),
          'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
          'managerName': _manager.text.trim().isEmpty ? null : _manager.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        });
      } else {
        await notifier.add(
          name: _name.text.trim(),
          address: _address.text.trim(),
          managerName: _manager.text.trim(),
          phone: _phone.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
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
    return AlertDialog(
      title: Text(_editing ? 'Edit warehouse' : 'Add warehouse'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _manager,
                decoration: const InputDecoration(labelText: 'Manager'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
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
              : Text(_editing ? 'Save changes' : 'Add warehouse'),
        ),
      ],
    );
  }
}
