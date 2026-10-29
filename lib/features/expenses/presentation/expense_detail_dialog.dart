import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../sales/domain/sale.dart';
import '../data/expenses_repository.dart';
import '../domain/expense.dart';
import 'expense_form_dialog.dart';

/// Opens [url] outside the app (the receipt in the browser or PDF viewer).
/// Tests replace it.
final openUrlProvider = Provider<Future<void> Function(String url)>(
  (ref) => (url) async => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
);

StatusPill expenseStatusPill(Expense e) => e.isVoided
    ? const StatusPill(label: 'Voided', tone: StatusTone.neutral)
    : const StatusPill(label: 'Recorded', tone: StatusTone.positive);

/// One expense: what, how much, when, how it was paid, who recorded or
/// changed it, and its receipt (a photo is shown, a PDF opens). Edit,
/// attach or remove the receipt, and void, as the role allows.
class ExpenseDetailDialog extends ConsumerStatefulWidget {
  const ExpenseDetailDialog({super.key, required this.expenseId});

  final String expenseId;

  @override
  ConsumerState<ExpenseDetailDialog> createState() => _ExpenseDetailDialogState();
}

class _ExpenseDetailDialogState extends ConsumerState<ExpenseDetailDialog> {
  bool _busy = false;

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach(Expense e) async {
    final picked = await ref.read(receiptPickerProvider)();
    if (picked == null) return;
    await _run(() async {
      await ref.read(expensesProvider.notifier).attach(e.id, bytes: picked.bytes, filename: picked.name);
      _toast('Receipt attached to ${e.reference}.');
    });
  }

  Future<void> _void(Expense e) async {
    final reason = await showDialog<String>(context: context, builder: (_) => _VoidDialog(expense: e));
    if (reason == null) return;
    await _run(() async {
      await ref.read(expensesProvider.notifier).voidExpense(e.id, reason: reason);
      _toast('${e.reference} voided.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6));
    final e = (ref.watch(expensesProvider).valueOrNull ?? const <Expense>[]).where((x) => x.id == widget.expenseId).firstOrNull;
    if (e == null) {
      return AlertDialog(
        content: const Text('This expense is no longer listed.'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
    }
    final myId = ref.watch(sessionUserIdProvider);
    final canEdit = hasPermission(ref, Permissions.expensesEdit) && !e.isVoided;
    final canAttach = !e.isVoided &&
        (hasPermission(ref, Permissions.expensesEdit) ||
            (hasPermission(ref, Permissions.expensesCreate) && e.createdById == myId));
    final canVoid = hasPermission(ref, Permissions.expensesVoid) && !e.isVoided;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 130, child: Text(label, style: muted)),
              Expanded(child: Text(value)),
            ],
          ),
        );

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('${e.reference} · ${currencyFormat.format(e.amount)}')),
          expenseStatusPill(e),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (e.isVoided)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Voided${e.voidedByName == null ? '' : ' by ${e.voidedByName}'}'
                    '${e.voidedAt == null ? '' : ' on ${dateFormat.format(e.voidedAt!)}'}: ${e.voidReason ?? ''}',
                    key: const Key('expense-voided-note'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              row('Category', e.categoryName),
              row('Date', dateFormat.format(e.expenseDate)),
              row('Paid by', e.paymentMethod.label),
              if (e.payee != null) row('Paid to', e.payee!),
              if (e.receiptNumber != null) row('Their receipt no.', e.receiptNumber!),
              row('For', e.warehouseName ?? 'The whole business'),
              if (e.description != null) row('Description', e.description!),
              row(
                'Recorded',
                [
                  if (e.createdByName != null) e.createdByName!,
                  if (e.createdAt != null) dateTimeFormat.format(e.createdAt!),
                  if (e.recurringId != null) 'from a recurring expense',
                ].join(' · '),
              ),
              if (e.updatedByName != null && e.updatedAt != null)
                row('Last changed', '${e.updatedByName} · ${dateTimeFormat.format(e.updatedAt!)}'),
              const Divider(height: 24),
              Row(
                children: [
                  Text('Receipt', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (e.hasAttachment)
                    TextButton.icon(
                      key: const Key('expense-open-receipt'),
                      onPressed: () => ref.read(openUrlProvider)(e.attachmentUrl!),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(e.attachmentIsPdf ? 'Open PDF' : 'Open'),
                    ),
                  if (canAttach)
                    TextButton.icon(
                      key: const Key('expense-attach'),
                      onPressed: _busy ? null : () => _attach(e),
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: Text(e.hasAttachment ? 'Replace' : 'Attach'),
                    ),
                  if (canAttach && e.hasAttachment)
                    TextButton(
                      key: const Key('expense-remove-receipt'),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await ref.read(expensesProvider.notifier).removeAttachment(e.id);
                                _toast('Receipt removed.');
                              }),
                      child: const Text('Remove'),
                    ),
                ],
              ),
              if (!e.hasAttachment)
                Text('No receipt attached.', style: muted)
              else if (e.attachmentIsPdf)
                Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.attachmentName ?? 'receipt.pdf', overflow: TextOverflow.ellipsis)),
                  ],
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Image.network(
                      e.attachmentUrl!,
                      key: const Key('expense-receipt-image'),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text("Couldn't load the picture — use Open.", style: muted),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (canVoid)
          TextButton(
            key: const Key('expense-void'),
            onPressed: _busy ? null : () => _void(e),
            child: Text('Void', style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (canEdit)
          ElevatedButton(
            key: const Key('expense-edit'),
            onPressed: _busy
                ? null
                : () async {
                    Navigator.of(context).pop();
                    await showDialog(context: context, builder: (_) => ExpenseFormDialog(expense: e));
                  },
            child: const Text('Edit'),
          ),
      ],
    );
  }
}

class _VoidDialog extends StatefulWidget {
  const _VoidDialog({required this.expense});

  final Expense expense;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Void ${widget.expense.reference}?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'It stays on record, marked voided, and no longer counts in totals or budgets. '
                "This can't be undone.",
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('expense-void-reason'),
                controller: _reason,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Recorded twice'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep it')),
          ElevatedButton(
            key: const Key('expense-void-confirm'),
            onPressed: _reason.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_reason.text.trim()),
            child: const Text('Void'),
          ),
        ],
      );
}
