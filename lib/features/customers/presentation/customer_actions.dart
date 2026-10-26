import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../data/customer_excel.dart';
import '../data/customer_types.dart';

/// Things done to customers from both the list and a customer's page.

void _toast(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

StatusPill customerStatusPill(Party c) {
  if (!c.isActive) return const StatusPill(label: 'Archived', tone: StatusTone.neutral);
  if (c.isPending) return const StatusPill(label: 'Pending sync', tone: StatusTone.neutral);
  if (c.isAtCreditLimit) return const StatusPill(label: 'At limit', tone: StatusTone.negative);
  if (c.balanceOwed > 0) return const StatusPill(label: 'Owing', tone: StatusTone.warning);
  return const StatusPill(label: 'Clear', tone: StatusTone.positive);
}

/// Asks first; returns whether the customer was archived (or queued).
Future<bool> archiveCustomer(BuildContext context, WidgetRef ref, Party c) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Archive customer?'),
      content: Text(
        '${c.name} will leave the active list and can no longer be sold to on credit. '
        'Their history is kept${c.balanceOwed > 0 ? ', and the ${currencyFormat.format(c.balanceOwed)} still owed stays on record' : ''}. '
        'You can restore them from the Archived filter.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          key: const Key('customer-confirm-archive'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    final outcome = await ref.read(partiesProvider(PartyType.customer).notifier).archive(c.id);
    if (context.mounted) {
      _toast(
        context,
        outcome.queued ? 'Saved on this computer — it will sync when the connection is good.' : '${c.name} archived.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return false;
  }
}

Future<void> restoreCustomer(BuildContext context, WidgetRef ref, Party c) async {
  try {
    await ref.read(partiesProvider(PartyType.customer).notifier).restore(c.id);
    if (context.mounted) _toast(context, '${c.name} is active again.');
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// Saves [customers] (what the list shows) as an `.xlsx` the person picks.
Future<void> exportCustomers(BuildContext context, WidgetRef ref, List<Party> customers) async {
  try {
    final bytes = Uint8List.fromList(
      buildCustomerExport(customers, (c) => ref.read(customerTypeNameProvider(c))),
    );
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save customer list',
      fileName: 'customers.xlsx',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path == null) return;
    // On desktop the save dialog only picks the path.
    await File(path).writeAsBytes(bytes);
    if (context.mounted) _toast(context, '${customers.length} customer${customers.length == 1 ? '' : 's'} saved to $path');
  } catch (e) {
    if (context.mounted) _toast(context, "Couldn't save the list: ${friendlyError(e)}");
  }
}
