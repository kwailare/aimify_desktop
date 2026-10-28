import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../customers/data/customer_excel.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';

/// Things done to suppliers from both the list and a supplier's page.

void _toast(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

StatusPill supplierStatusPill(Party s) {
  if (!s.isActive) return const StatusPill(label: 'Archived', tone: StatusTone.neutral);
  if (s.isPending) return const StatusPill(label: 'Pending sync', tone: StatusTone.neutral);
  if (s.overdue > 0) return const StatusPill(label: 'Overdue', tone: StatusTone.negative);
  if (s.balanceOwed > 0) return const StatusPill(label: 'Owing', tone: StatusTone.warning);
  return const StatusPill(label: 'Settled', tone: StatusTone.positive);
}

/// Asks first; returns whether the supplier was archived (or queued).
Future<bool> archiveSupplier(BuildContext context, WidgetRef ref, Party s) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Archive supplier?'),
      content: Text(
        '${s.name} will leave the active list and can no longer be picked on new purchases. '
        'Their history is kept${s.balanceOwed > 0 ? ', and the ${currencyFormat.format(s.balanceOwed)} you owe stays on record' : ''}. '
        'You can restore them from the Archived filter.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          key: const Key('supplier-confirm-archive'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    final outcome = await ref.read(partiesProvider(PartyType.supplier).notifier).archive(s.id);
    if (context.mounted) {
      _toast(
        context,
        outcome.queued ? 'Saved on this computer — it will sync when the connection is good.' : '${s.name} archived.',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return false;
  }
}

Future<void> restoreSupplier(BuildContext context, WidgetRef ref, Party s) async {
  try {
    await ref.read(partiesProvider(PartyType.supplier).notifier).restore(s.id);
    if (context.mounted) _toast(context, '${s.name} is active again.');
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// Saves [suppliers] (what the list shows) as an `.xlsx` the person picks.
Future<void> exportSuppliers(BuildContext context, List<Party> suppliers) async {
  try {
    final bytes = Uint8List.fromList(buildSupplierExport(suppliers));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save supplier list',
      fileName: 'suppliers.xlsx',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path == null) return;
    await File(path).writeAsBytes(bytes);
    if (context.mounted) _toast(context, '${suppliers.length} supplier${suppliers.length == 1 ? '' : 's'} saved to $path');
  } catch (e) {
    if (context.mounted) _toast(context, "Couldn't save the list: ${friendlyError(e)}");
  }
}
