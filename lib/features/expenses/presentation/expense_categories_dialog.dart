import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';

String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// Expense categories and their monthly budgets (needs expenses.manage): add
/// one, rename it or set its budget, or remove one no expense uses.
class ExpenseCategoriesDialog extends ConsumerStatefulWidget {
  const ExpenseCategoriesDialog({super.key});

  @override
  ConsumerState<ExpenseCategoriesDialog> createState() => _ExpenseCategoriesDialogState();
}

class _ExpenseCategoriesDialogState extends ConsumerState<ExpenseCategoriesDialog> {
  final _name = TextEditingController();
  final _budget = TextEditingController(text: '0');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
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
    final budget = double.tryParse(_budget.text.trim().replaceAll(',', ''));
    if (name.isEmpty) return setState(() => _error = 'Enter a name for the category.');
    if (budget == null || budget < 0) return setState(() => _error = 'The budget must be 0 or more.');
    await _run(() async {
      await ref.read(expenseCategoriesProvider.notifier).add(name, monthlyBudget: budget);
      _name.clear();
      _budget.text = '0';
    });
  }

  Future<void> _edit(ExpenseCategory c) async {
    final result = await showDialog<({String name, double budget})>(
      context: context,
      builder: (_) => _EditCategoryDialog(category: c),
    );
    if (result == null) return;
    await _run(() => ref.read(expenseCategoriesProvider.notifier).edit(c.id, name: result.name, monthlyBudget: result.budget));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(expenseCategoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    return AlertDialog(
      title: const Text('Expense categories & budgets'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A monthly budget is compared with what is spent each month (0 for none).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in categories)
                    ListTile(
                      key: ValueKey('expense-category-${c.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${c.hasBudget ? 'Budget ${currencyFormat.format(c.monthlyBudget)} a month' : 'No budget'}'
                        ' · ${c.expenseCount} expense${c.expenseCount == 1 ? '' : 's'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('expense-category-edit-${c.id}'),
                            tooltip: 'Change',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: _busy ? null : () => _edit(c),
                          ),
                          IconButton(
                            key: ValueKey('expense-category-delete-${c.id}'),
                            tooltip: c.expenseCount > 0 ? 'Expenses use this category' : 'Remove',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: _busy || c.expenseCount > 0
                                ? null
                                : () => _run(() => ref.read(expenseCategoriesProvider.notifier).remove(c.id)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('expense-category-name'),
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'New category', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('expense-category-budget'),
                    controller: _budget,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Monthly budget', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(key: const Key('expense-category-add'), onPressed: _busy ? null : _add, child: const Text('Add')),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, key: const Key('expense-category-error'), style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

class _EditCategoryDialog extends StatefulWidget {
  const _EditCategoryDialog({required this.category});

  final ExpenseCategory category;

  @override
  State<_EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<_EditCategoryDialog> {
  late final _name = TextEditingController(text: widget.category.name);
  late final _budget = TextEditingController(text: _plain(widget.category.monthlyBudget));
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Change ${widget.category.name}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(key: const Key('edit-category-name'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                key: const Key('edit-category-budget'),
                controller: _budget,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monthly budget (0 for none)'),
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
          ElevatedButton(
            key: const Key('edit-category-save'),
            onPressed: () {
              final name = _name.text.trim();
              final budget = double.tryParse(_budget.text.trim().replaceAll(',', ''));
              if (name.isEmpty) return setState(() => _error = 'Enter a name.');
              if (budget == null || budget < 0) return setState(() => _error = 'The budget must be 0 or more.');
              Navigator.of(context).pop((name: name, budget: budget));
            },
            child: const Text('Save'),
          ),
        ],
      );
}
