import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/offline/outbox.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../data/customer_excel.dart';
import '../data/customer_types.dart';

enum _Step { pick, preview, importing, done }

/// Adds customers from an `.xlsx`: download the template, pick a file, check
/// the preview (rows with problems and names already in the list are left
/// out), then import. Each customer is added like "Add customer" would (so
/// offline they wait to sync), and an Opening balance is recorded as a
/// charge on their account when the role may record credit.
class CustomerImportDialog extends ConsumerStatefulWidget {
  const CustomerImportDialog({super.key, this.pickFile});

  /// Stands in for the file picker in tests.
  final Future<({String name, List<int> bytes})?> Function()? pickFile;

  @override
  ConsumerState<CustomerImportDialog> createState() => _CustomerImportDialogState();
}

class _CustomerImportDialogState extends ConsumerState<CustomerImportDialog> {
  _Step _step = _Step.pick;
  String? _fileName;
  CustomerImport? _parsed;
  String? _pickError;
  int _done = 0;
  int _added = 0;
  int _queued = 0;
  final List<String> _problems = [];

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveTemplate() async {
    try {
      final bytes = Uint8List.fromList(buildCustomerImportTemplate());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save customer template',
        fileName: 'aimify-customer-import-template.xlsx',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      if (mounted) _toast('Template saved.');
    } catch (e) {
      if (mounted) _toast("Couldn't save the template: ${friendlyError(e)}");
    }
  }

  Future<({String name, List<int> bytes})?> _pickWithDialog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    return file == null || bytes == null ? null : (name: file.name, bytes: bytes);
  }

  Future<void> _pick() async {
    setState(() => _pickError = null);
    final file = await (widget.pickFile ?? _pickWithDialog)();
    if (file == null || !mounted) return;
    List<CustomerType> types;
    try {
      types = await ref.read(customerTypesProvider.future);
    } catch (_) {
      types = const [];
    }
    // Names already in the list are skipped, so the list must be loaded.
    try {
      await ref.read(partiesProvider(PartyType.customer).future);
    } catch (_) {}
    if (!mounted) return;
    final parsed = parseCustomerWorkbook(
      file.bytes,
      types: types,
      existing: ref.read(partyListProvider(PartyType.customer)),
    );
    if (parsed.sheetError != null) {
      setState(() => _pickError = parsed.sheetError);
      return;
    }
    setState(() {
      _fileName = file.name;
      _parsed = parsed;
      _step = _Step.preview;
    });
  }

  Future<void> _import() async {
    final rows = _parsed?.rows ?? const <ImportedCustomerRow>[];
    final canRecord = hasPermission(ref, Permissions.creditRecord);
    setState(() => _step = _Step.importing);
    final customers = ref.read(partiesProvider(PartyType.customer).notifier);

    for (final row in rows) {
      if (!mounted) return;
      try {
        final result = await customers.add(row.input);
        final id = result.queued
            ? ref.read(outboxOpsProvider).where((o) => o.kind == OpKind.partyCreate).lastOrNull?.localId
            : result.value?.id;
        result.queued ? _queued++ : _added++;
        if (row.openingBalance > 0 && canRecord && id != null) {
          try {
            await ref.read(creditServiceProvider).record(
                  partyType: PartyType.customer,
                  partyId: id,
                  kind: CreditKind.charge,
                  amount: row.openingBalance,
                  note: 'Opening balance (imported)',
                );
          } catch (e) {
            _problems.add('Row ${row.rowNumber}: ${row.input.name} added, but the opening balance was not: ${friendlyError(e)}');
          }
        }
      } catch (e) {
        _problems.add('Row ${row.rowNumber}: ${row.input.name} — ${friendlyError(e)}');
      }
      if (mounted) setState(() => _done++);
    }
    if (mounted) setState(() => _step = _Step.done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final parsed = _parsed;
    final canRecord = hasPermission(ref, Permissions.creditRecord);

    final Widget content = switch (_step) {
      _Step.pick => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use the template, or any sheet whose first row has the headers: Name (required), Type, Phone, '
              'Email, Address, Credit limit, Opening balance, Notes.',
            ),
            const SizedBox(height: 8),
            Text(
              'A Type must match one of your customer types. An empty Credit limit takes the type\'s default. '
              'Names already in your customer list are skipped.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saveTemplate,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download template'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  key: const Key('customer-import-pick'),
                  onPressed: _pick,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Choose file'),
                ),
              ],
            ),
            if (_pickError != null) ...[
              const SizedBox(height: 12),
              Text(_pickError!, key: const Key('customer-import-error'), style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      _Step.preview => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$_fileName: ${parsed!.rows.length} ready'
              '${parsed.skipped.isEmpty ? '' : ' · ${parsed.skipped.length} already in your list'}'
              '${parsed.errors.isEmpty ? '' : ' · ${parsed.errors.length} with problems'}',
              key: const Key('customer-import-summary'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!canRecord && parsed.rows.any((r) => r.openingBalance > 0))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "Your role can't record credit, so opening balances will be left out.",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in parsed.rows)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline, color: Color(0xFF2F8F5B), size: 18),
                      title: Text(r.input.name),
                      subtitle: Text(
                        [
                          'Row ${r.rowNumber}',
                          if (r.input.creditLimit > 0) 'limit ${currencyFormat.format(r.input.creditLimit)}',
                          if (r.openingBalance > 0) 'owes ${currencyFormat.format(r.openingBalance)}',
                          ...r.warnings,
                        ].join(' · '),
                      ),
                    ),
                  for (final e in [...parsed.skipped, ...parsed.errors])
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.remove_circle_outline, color: theme.colorScheme.error, size: 18),
                      title: Text('Row ${e.rowNumber} left out'),
                      subtitle: Text(e.messages.join(' · ')),
                    ),
                ],
              ),
            ),
          ],
        ),
      _Step.importing => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: parsed!.rows.isEmpty ? null : _done / parsed.rows.length),
            const SizedBox(height: 10),
            Text('Adding $_done of ${parsed.rows.length}…'),
          ],
        ),
      _Step.done => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                '$_added customer${_added == 1 ? '' : 's'} added',
                if (_queued > 0) '$_queued saved on this computer to sync later',
              ].join(' · '),
              key: const Key('customer-import-done'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final p in _problems) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p)),
          ],
        ),
    };

    return AlertDialog(
      title: const Text('Import customers'),
      content: SizedBox(width: 560, child: content),
      actions: [
        if (_step == _Step.preview)
          TextButton(onPressed: () => setState(() => _step = _Step.pick), child: const Text('Choose another file')),
        if (_step != _Step.importing)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_step == _Step.done ? 'Close' : 'Cancel'),
          ),
        if (_step == _Step.preview)
          ElevatedButton(
            key: const Key('customer-import-run'),
            onPressed: parsed!.rows.isEmpty ? null : _import,
            child: Text('Import ${parsed.rows.length}'),
          ),
      ],
    );
  }
}
