import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../warehouses/data/warehouses_repository.dart';
import '../data/staff_repository.dart';
import '../domain/staff.dart';

/// Admin-only "add staff" dialog. Per the current scope, this creates a
/// local record only — there is no way for this person to actually sign in
/// with these details yet (no staff-login backend or local auth path).
class StaffFormDialog extends ConsumerStatefulWidget {
  const StaffFormDialog({super.key});

  @override
  ConsumerState<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends ConsumerState<StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String? _warehouseId;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(staffProvider.notifier).addStaff(
          Staff(
            id: 'st${DateTime.now().microsecondsSinceEpoch}',
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            warehouseId: _warehouseId!,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(warehousesProvider);

    return AlertDialog(
      title: const Text('Add staff'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email address';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _warehouseId,
                decoration: const InputDecoration(labelText: 'Assigned warehouse'),
                items: [
                  for (final warehouse in warehouses)
                    DropdownMenuItem(value: warehouse.id, child: Text(warehouse.name)),
                ],
                onChanged: (value) => setState(() => _warehouseId = value),
                validator: (value) => value == null ? 'Select a warehouse' : null,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "This adds a staff record for tracking and warehouse assignment. "
                        "There's no staff sign-in yet — see the Credits/notes for why.",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Add staff')),
      ],
    );
  }
}
