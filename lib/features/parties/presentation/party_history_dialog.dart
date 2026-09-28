import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../data/parties_repository.dart';
import '../domain/party.dart';
import 'credit_entry_dialog.dart';

/// One customer's or supplier's credit ledger: every charge, payment and
/// adjustment, newest first, with the balance still owed. Anyone with
/// `credit.record` can add entries from here.
class PartyHistoryDialog extends ConsumerWidget {
  const PartyHistoryDialog({super.key, required this.party});

  final Party party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = (type: party.type, id: party.id);
    final state = ref.watch(creditEntriesProvider(key));
    final entries = ref.watch(creditLedgerProvider(key));
    final myId = ref.watch(sessionUserIdProvider);
    final canRecord = hasPermission(ref, Permissions.creditRecord);
    final live = ref.watch(partyListProvider(party.type)).where((p) => p.id == party.id).firstOrNull ?? party;
    final isCustomer = party.type == PartyType.customer;

    void open(CreditKind kind) =>
        showDialog(context: context, builder: (_) => CreditEntryDialog(party: live, kind: kind));

    return AlertDialog(
      title: Text(live.name),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isCustomer ? 'Owes you' : 'You owe',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  currencyFormat.format(live.balanceOwed),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (live.isAtCreditLimit) ...[
                  const SizedBox(width: 8),
                  const StatusPill(label: 'At credit limit', tone: StatusTone.negative),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: state.isLoading && !state.hasValue && entries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : state.hasError && !state.hasValue && entries.isEmpty
                        ? Text(friendlyError(state.error!))
                        : entries.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('Nothing recorded yet.'),
                              )
                            : ListView(
                                shrinkWrap: true,
                                children: [
                                  for (final entry in entries)
                                    _EntryRow(entry: entry, myId: myId, theme: theme),
                                ],
                              ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (canRecord) ...[
          TextButton(onPressed: () => open(CreditKind.adjustment), child: const Text('Adjust')),
          OutlinedButton(
            onPressed: () => open(CreditKind.charge),
            child: Text(isCustomer ? 'Add credit sale' : 'Add invoice'),
          ),
          ElevatedButton(
            onPressed: live.balanceOwed > 0 ? () => open(CreditKind.payment) : null,
            child: const Text('Record payment'),
          ),
        ],
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.myId, required this.theme});

  final CreditEntry entry;
  final String? myId;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Positive raised what is owed (bad for a customer's debt, or more you
    // owe); negative lowered it.
    final raised = entry.amount > 0;
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
                    Flexible(
                      child: Text(
                        entry.note == null ? entry.kind.label : '${entry.kind.label} · ${entry.note}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (entry.isPending) ...[
                      const SizedBox(width: 8),
                      const StatusPill(label: 'Pending sync', tone: StatusTone.neutral),
                    ],
                  ],
                ),
                Text(
                  '${dateTimeFormat.format(entry.createdAt)}'
                  '${entry.userId == null ? '' : entry.userId == myId ? ' · You' : ' · Team member'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
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
        ],
      ),
    );
  }
}
