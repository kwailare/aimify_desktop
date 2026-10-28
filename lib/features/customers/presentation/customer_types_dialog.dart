import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../data/customer_types.dart';

String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// The organization's customer types (needs customers.types): add one, change
/// its name or default credit limit, or remove one no customer has. Changes
/// need a connection.
class CustomerTypesDialog extends ConsumerStatefulWidget {
  const CustomerTypesDialog({super.key});

  @override
  ConsumerState<CustomerTypesDialog> createState() => _CustomerTypesDialogState();
}

class _CustomerTypesDialogState extends ConsumerState<CustomerTypesDialog> {
  final _name = TextEditingController();
  final _limit = TextEditingController(text: '0');
  final _terms = TextEditingController(text: '30');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    final limit = double.tryParse(_limit.text.trim());
    final terms = int.tryParse(_terms.text.trim());
    if (name.isEmpty) return setState(() => _error = 'Enter a name for the type.');
    if (limit == null || limit < 0) return setState(() => _error = 'The default limit must be 0 or more.');
    if (terms == null || terms < 0 || terms > 365) return setState(() => _error = 'Terms must be 0 to 365 days.');
    await _run(() async {
      await ref.read(customerTypesProvider.notifier).add(name, defaultCreditLimit: limit, defaultPaymentTermsDays: terms);
      _name.clear();
      _limit.text = '0';
      _terms.text = '30';
    });
  }

  Future<void> _edit(CustomerType type) async {
    final result = await showDialog<({String name, double limit, int terms})>(
      context: context,
      builder: (_) => _EditTypeDialog(type: type),
    );
    if (result == null) return;
    await _run(
      () => ref.read(customerTypesProvider.notifier).edit(
            type.id,
            name: result.name,
            defaultCreditLimit: result.limit,
            defaultPaymentTermsDays: result.terms,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(customerTypesProvider);
    final types = state.valueOrNull ?? const <CustomerType>[];
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AlertDialog(
      title: const Text('Customer types'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Group customers (Retail, Wholesale, …). A default credit limit is filled in for new customers of the type; '
              'changing it later never changes existing customers.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            if (state.isLoading && !state.hasValue)
              const LoadingPanel(label: 'Loading types…')
            else if (types.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No types yet.'))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in types)
                      ListTile(
                        key: ValueKey('customer-type-${t.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${t.defaultCreditLimit > 0 ? 'Default limit ${currencyFormat.format(t.defaultCreditLimit)}' : 'No default limit'}'
                          ' · ${t.defaultPaymentTermsDays}-day terms'
                          ' · ${t.customerCount} customer${t.customerCount == 1 ? '' : 's'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Change',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: _busy ? null : () => _edit(t),
                            ),
                            IconButton(
                              key: ValueKey('customer-type-delete-${t.id}'),
                              tooltip: t.customerCount > 0 ? 'Customers have this type' : 'Remove',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: _busy || t.customerCount > 0
                                  ? null
                                  : () => _run(() => ref.read(customerTypesProvider.notifier).remove(t.id)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('customer-type-name'),
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'New type', isDense: true),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('customer-type-limit'),
                    controller: _limit,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Default limit', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('customer-type-terms'),
                    controller: _terms,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Terms (days)', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('customer-type-add'),
                  onPressed: _busy ? null : _add,
                  child: const Text('Add'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, key: const Key('customer-type-error'), style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

class _EditTypeDialog extends StatefulWidget {
  const _EditTypeDialog({required this.type});

  final CustomerType type;

  @override
  State<_EditTypeDialog> createState() => _EditTypeDialogState();
}

class _EditTypeDialogState extends State<_EditTypeDialog> {
  late final _name = TextEditingController(text: widget.type.name);
  late final _limit = TextEditingController(text: _plain(widget.type.defaultCreditLimit));
  late final _terms = TextEditingController(text: '${widget.type.defaultPaymentTermsDays}');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    _terms.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final limit = double.tryParse(_limit.text.trim());
    if (name.isEmpty) return setState(() => _error = 'Enter a name.');
    if (limit == null || limit < 0) return setState(() => _error = 'The default limit must be 0 or more.');
    final terms = int.tryParse(_terms.text.trim());
    if (terms == null || terms < 0 || terms > 365) return setState(() => _error = 'Terms must be 0 to 365 days.');
    Navigator.of(context).pop((name: name, limit: limit, terms: terms));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Change ${widget.type.name}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('edit-type-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('edit-type-limit'),
                controller: _limit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Default credit limit',
                  helperText: 'For customers added from now on',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('edit-type-terms'),
                controller: _terms,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Default payment terms (days)',
                  helperText: 'For customers added from now on',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(key: const Key('edit-type-save'), onPressed: _save, child: const Text('Save')),
        ],
      );
}
