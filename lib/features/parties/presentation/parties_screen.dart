import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../data/parties_repository.dart';
import '../domain/party.dart';
import 'party_form_dialog.dart';
import 'party_history_dialog.dart';

/// The customers or suppliers list, live from the API. Customers and
/// suppliers are the same kind of record, so one screen serves both.
///
/// Reading needs `customers.read` / `suppliers.read`; adding, editing and
/// archiving need the matching `.write`. A role without read access sees a
/// plain explanation instead of a wall of 403s. Tapping a row opens the
/// party's credit ledger.
class PartiesScreen extends ConsumerWidget {
  const PartiesScreen({super.key, required this.type});

  final PartyType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isCustomer = type == PartyType.customer;
    final canRead = hasPermission(
      ref,
      isCustomer ? Permissions.customersRead : Permissions.suppliersRead,
    );
    final canWrite = hasPermission(
      ref,
      isCustomer ? Permissions.customersWrite : Permissions.suppliersWrite,
    );
    final state = ref.watch(partiesProvider(type));
    final parties = ref.watch(partyListProvider(type));
    final noun = type.label.toLowerCase();

    Widget body;
    if (!canRead) {
      body = Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text("Your role can't view ${type.plural}.")),
        ),
      );
    } else if (state.isLoading && !state.hasValue) {
      body = const LoadingPanel(label: 'Loading…');
    } else if (state.hasError && !state.hasValue) {
      body = ErrorRetryCard(
        error: state.error!,
        onRetry: () => ref.read(partiesProvider(type).notifier).refresh(),
      );
    } else if (parties.isEmpty) {
      body = Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              canWrite
                  ? 'No ${type.plural} yet. Use "Add $noun" to add one.'
                  : 'No ${type.plural} yet.',
            ),
          ),
        ),
      );
    } else {
      body = Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(
              theme.colorScheme.onSurface.withValues(alpha: 0.03),
            ),
            columns: [
              DataColumn(label: Text(type.label)),
              if (!isCustomer) const DataColumn(label: Text('Contact person')),
              const DataColumn(label: Text('Phone')),
              if (isCustomer) const DataColumn(label: Text('Credit limit'), numeric: true),
              DataColumn(label: Text(isCustomer ? 'Owes you' : 'You owe'), numeric: true),
              const DataColumn(label: Text('Status')),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (var i = 0; i < parties.length; i++)
                DataRow(
                  color: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return theme.colorScheme.primary.withValues(alpha: 0.06);
                    }
                    return i.isOdd ? theme.colorScheme.onSurface.withValues(alpha: 0.025) : null;
                  }),
                  onSelectChanged: (_) => showDialog(
                    context: context,
                    builder: (_) => PartyHistoryDialog(party: parties[i]),
                  ),
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(parties[i].name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    if (!isCustomer) DataCell(Text(parties[i].contactPerson ?? '—')),
                    DataCell(Text(parties[i].phone ?? '—')),
                    if (isCustomer)
                      DataCell(
                        Text(parties[i].creditLimit > 0 ? currencyFormat.format(parties[i].creditLimit) : '—'),
                      ),
                    DataCell(Text(currencyFormat.format(parties[i].balanceOwed))),
                    DataCell(_statusPill(parties[i])),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: canWrite ? 'Edit' : "Your role can't edit ${type.plural}",
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: !canWrite
                                ? null
                                : () => showDialog(
                                      context: context,
                                      builder: (_) => PartyFormDialog(type: type, party: parties[i]),
                                    ),
                          ),
                          IconButton(
                            tooltip: canWrite ? 'Archive' : "Your role can't archive ${type.plural}",
                            icon: const Icon(Icons.archive_outlined, size: 18),
                            onPressed: !canWrite ? null : () => _confirmArchive(context, ref, parties[i]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: '${type.label}s',
              subtitle: canRead
                  ? '${parties.length} ${parties.length == 1 ? noun : type.plural} · tap a row for the credit history'
                  : 'Not available for your role',
              actions: [
                Tooltip(
                  message: canWrite ? '' : "Your role can't add ${type.plural}",
                  child: ElevatedButton.icon(
                    onPressed: canWrite
                        ? () => showDialog(
                              context: context,
                              builder: (_) => PartyFormDialog(type: type),
                            )
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('Add $noun'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            body,
          ],
        ),
      ),
    );
  }

  Widget _statusPill(Party party) {
    if (party.isPending) return const StatusPill(label: 'Pending sync', tone: StatusTone.neutral);
    if (party.isAtCreditLimit) return const StatusPill(label: 'At limit', tone: StatusTone.negative);
    if (party.balanceOwed > 0) return const StatusPill(label: 'Owing', tone: StatusTone.warning);
    return StatusPill(
      label: type == PartyType.customer ? 'Clear' : 'Settled',
      tone: StatusTone.positive,
    );
  }

  void _confirmArchive(BuildContext context, WidgetRef ref, Party party) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archive ${type.label.toLowerCase()}?'),
        content: Text(
          '${party.name} will leave the list. Their credit history is kept'
          '${party.balanceOwed > 0 ? ', and the ${currencyFormat.format(party.balanceOwed)} still owed stays on record' : ''}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                final outcome = await ref.read(partiesProvider(type).notifier).archive(party.id);
                if (outcome.queued && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Saved on this computer — it will sync when the connection is good.'),
                      ),
                    );
                }
              } catch (e) {
                if (context.mounted) showErrorSnack(context, e);
              }
            },
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}
