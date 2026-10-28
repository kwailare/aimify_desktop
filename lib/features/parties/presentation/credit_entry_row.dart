import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../sales/domain/sale.dart';
import '../domain/party.dart';
import 'credit_entry_dialog.dart';

/// One ledger line: what it was, when and by whom, and how it moved the
/// balance. A debt shows what is still open on it and when it is due; a
/// payment shows how it was paid and what it settled. Pass [party] to offer
/// a customer's receipt for printing.
class CreditEntryRow extends ConsumerWidget {
  const CreditEntryRow({super.key, required this.entry, required this.myId, required this.theme, this.party});

  final CreditEntry entry;
  final String? myId;
  final ThemeData theme;
  final Party? party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Positive raised what is owed (bad for a customer's debt, or more you
    // owe); negative lowered it.
    final raised = entry.amount > 0;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55));
    final title = [
      entry.receiptNumber ?? entry.kind.label,
      if (entry.method != null) SalePaymentMethodX.fromApi(entry.method).label,
      ?entry.note,
    ].join(' · ');
    final p = party;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
                    if (entry.isPending) ...[
                      const SizedBox(width: 8),
                      const StatusPill(label: 'Pending sync', tone: StatusTone.neutral),
                    ],
                    if (entry.isOverdue) ...[
                      const SizedBox(width: 8),
                      StatusPill(
                        label: '${DateTime.now().difference(entry.dueDate!).inDays} days overdue',
                        tone: StatusTone.negative,
                      ),
                    ],
                  ],
                ),
                Text(
                  [
                    dateTimeFormat.format(entry.createdAt),
                    if (entry.userId != null) entry.userId == myId ? 'You' : 'Team member',
                    if (raised && entry.openAmount > 0 && entry.dueDate != null)
                      '${currencyFormat.format(entry.openAmount)} open, due ${dateFormat.format(entry.dueDate!)}',
                    if (raised && entry.openAmount <= 0 && !entry.isPending) 'Settled',
                  ].join(' · '),
                  style: muted,
                ),
                if (entry.allocations.isNotEmpty)
                  Text(
                    'Settled ${entry.allocations.map((a) => '${a.reference} ${currencyFormat.format(a.amount)}').join(', ')}',
                    style: muted,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${raised ? '+' : '−'}${currencyFormat.format(entry.amount.abs())}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: raised ? theme.colorScheme.error : const Color(0xFF2F8F5B),
            ),
          ),
          if (p != null && entry.receiptNumber != null)
            IconButton(
              key: ValueKey('print-receipt-${entry.id}'),
              tooltip: 'Receipt (PDF)',
              icon: const Icon(Icons.print_outlined, size: 18),
              onPressed: () => printAccountReceipt(context, ref, p, entry),
            ),
        ],
      ),
    );
  }
}
