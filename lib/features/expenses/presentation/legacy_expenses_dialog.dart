import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';

/// Expenses saved on this computer by older versions of the app: upload them
/// all to the server (each category matched by name, else "Other"), or
/// dismiss one. Uploading uses `legacy:<id>` as the clientRef, so one sent
/// twice is recorded once.
class LegacyExpensesDialog extends ConsumerStatefulWidget {
  const LegacyExpensesDialog({super.key});

  @override
  ConsumerState<LegacyExpensesDialog> createState() => _LegacyExpensesDialogState();
}

class _LegacyExpensesDialogState extends ConsumerState<LegacyExpensesDialog> {
  bool _busy = false;
  int _done = 0;
  final List<String> _problems = [];

  Future<void> _uploadAll() async {
    setState(() {
      _busy = true;
      _done = 0;
      _problems.clear();
    });
    List<ExpenseCategory> categories;
    try {
      categories = await ref.read(expenseCategoriesProvider.future);
    } catch (e) {
      setState(() {
        _busy = false;
        _problems.add(friendlyError(e));
      });
      return;
    }
    for (final e in List.of(ref.read(legacyExpensesProvider))) {
      final input = legacyExpenseInput(e, categories);
      if (input == null) {
        _problems.add('No expense categories to put them in.');
        break;
      }
      try {
        final result = await ref.read(expensesProvider.notifier).add(input, clientRef: 'legacy:${e.id}');
        if (result.queued) {
          _problems.add("You're offline — the rest will wait. Try again when connected.");
          break;
        }
        ref.read(legacyExpensesProvider.notifier).remove(e.id);
        if (mounted) setState(() => _done++);
      } catch (err) {
        _problems.add('${dateFormat.format(e.date)} ${e.category}: ${friendlyError(err)}');
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final legacy = ref.watch(legacyExpensesProvider);
    return AlertDialog(
      title: const Text('Expenses saved on this computer'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Older versions of Aimify kept expenses on this computer only. Upload them so they are on your '
              'account with everything else. Each goes into the category with the same name, or Other.',
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in legacy)
                    ListTile(
                      key: ValueKey('legacy-expense-${e.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${e.category} · ${currencyFormat.format(e.amount)}'),
                      subtitle: Text([dateFormat.format(e.date), if (e.note.isNotEmpty) e.note].join(' · ')),
                      trailing: IconButton(
                        tooltip: 'Dismiss (not uploaded)',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _busy ? null : () => ref.read(legacyExpensesProvider.notifier).remove(e.id),
                      ),
                    ),
                ],
              ),
            ),
            if (_done > 0) Text('$_done uploaded.', key: const Key('legacy-expenses-done')),
            for (final p in _problems) Text(p, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
        ElevatedButton(
          key: const Key('legacy-expenses-upload'),
          onPressed: _busy || legacy.isEmpty ? null : _uploadAll,
          child: Text(_busy ? 'Uploading…' : 'Upload ${legacy.length}'),
        ),
      ],
    );
  }
}
