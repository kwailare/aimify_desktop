import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/offline/outbox.dart';
import '../../../../shared/services/api_exception.dart';
import '../../../../shared/utils/friendly_error.dart';
import '../../../../shared/widgets/manage_billing_link.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../../inventory/domain/stock_movement.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/catalog_repository.dart';
import '../../data/product_excel_import.dart';
import '../../data/products_repository.dart';

enum _Step { pick, preview, importing, done }

enum _RowOutcome { created, queued, skippedDuplicate, failed }

class _ImportedRowResult {
  const _ImportedRowResult({required this.row, required this.outcome, this.message});

  final ImportedProductRow row;
  final _RowOutcome outcome;
  final String? message;
}

/// Bulk-adds products from an uploaded `.xlsx` spreadsheet. Each row is
/// created one at a time against the real API — there is no bulk-create
/// endpoint — so a row with a duplicate SKU is skipped (not fatal) and a
/// plan-limit refusal stops the rest early with a clear reason. A row with
/// opening stock also records a stock-in movement right after its product
/// is created, in the warehouse chosen for the whole import.
///
/// Everything here goes through the same offline-aware notifiers as "Add
/// product" / "Record movement", so a row created while offline is queued
/// and synced later exactly like a single manual add would be.
class BulkImportDialog extends ConsumerStatefulWidget {
  const BulkImportDialog({super.key});

  @override
  ConsumerState<BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends ConsumerState<BulkImportDialog> {
  _Step _step = _Step.pick;
  String? _fileName;
  ImportResult? _result;
  String? _pickError;
  String? _selectedWarehouseId;

  int _progress = 0;
  String? _stopReason;
  final List<_ImportedRowResult> _outcomes = [];

  bool get _needsWarehouse => (_result?.validRows ?? const []).any((r) => r.openingStock > 0);

  Future<void> _downloadTemplate() async {
    try {
      final bytes = Uint8List.fromList(buildProductImportTemplate());
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save import template',
        fileName: 'aimify-product-import-template.xlsx',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (path == null) return;
      // Desktop's save dialog only returns the chosen path — it doesn't
      // write the file, unlike mobile/web, so this does it here.
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Template saved.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text("Couldn't save the template: ${friendlyError(e)}")));
    }
  }

  Future<void> _pickFile() async {
    setState(() => _pickError = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    final parsed = parseProductWorkbook(bytes);
    if (parsed.hasFatalError) {
      setState(() => _pickError = parsed.sheetError);
      return;
    }

    setState(() {
      _fileName = file.name;
      _result = parsed;
      _step = _Step.preview;
    });
  }

  /// What's chosen, or — once there's exactly one active warehouse — that
  /// one by default. Watches the provider (for use during `build`) so the
  /// dialog rebuilds, and the Import button re-enables, the moment the
  /// warehouse list finishes loading rather than staying stuck on whatever
  /// it had (possibly still empty) back when the file was picked.
  String? get _effectiveWarehouseId => _resolveWarehouseId(ref.watch(activeWarehousesProvider));

  /// Same fallback, but reading rather than watching — for [_runImport],
  /// which runs outside `build` where `ref.watch` isn't allowed. Safe to
  /// read here: the Import button that starts it is only enabled once
  /// [_effectiveWarehouseId] has already resolved a warehouse during build.
  String? _resolveWarehouseIdForImport() => _resolveWarehouseId(ref.read(activeWarehousesProvider));

  String? _resolveWarehouseId(List<Warehouse> warehouses) {
    if (_selectedWarehouseId != null) return _selectedWarehouseId;
    return warehouses.length == 1 ? warehouses.single.id : null;
  }

  Future<void> _runImport() async {
    final result = _result;
    if (result == null) return;

    setState(() {
      _step = _Step.importing;
      _progress = 0;
      _stopReason = null;
      _outcomes.clear();
    });

    final products = ref.read(productsProvider.notifier);
    final movements = ref.read(movementsProvider.notifier);
    final warehouseId = _resolveWarehouseIdForImport();

    for (final row in result.validRows) {
      if (!mounted) return;

      try {
        final created = await products.add(row.input);
        String? productId = created.value?.id;
        var outcome = _RowOutcome.created;
        String? message;

        if (created.queued) {
          outcome = _RowOutcome.queued;
          productId = ref
              .read(outboxOpsProvider)
              .where((o) => o.kind == OpKind.productCreate)
              .lastOrNull
              ?.localId;
        }

        if (row.openingStock > 0 && warehouseId != null && productId != null) {
          try {
            await movements.record(
              productId: productId,
              warehouseId: warehouseId,
              type: StockMovementType.stockIn,
              quantity: row.openingStock,
              reason: 'Opening stock (bulk import)',
            );
          } catch (e) {
            message = 'Created, but opening stock could not be recorded: ${friendlyError(e)}';
          }
        } else if (row.openingStock > 0 && warehouseId == null) {
          message = 'Created without opening stock — no warehouse was available to record it in.';
        }

        _outcomes.add(_ImportedRowResult(row: row, outcome: outcome, message: message));
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          _outcomes.add(
            _ImportedRowResult(
              row: row,
              outcome: _RowOutcome.skippedDuplicate,
              message: 'A product with SKU "${row.input.sku}" already exists — skipped.',
            ),
          );
          continue;
        }
        if (e.isPlanLimit) {
          setState(() => _stopReason = friendlyError(e));
          break;
        }
        _outcomes.add(
          _ImportedRowResult(row: row, outcome: _RowOutcome.failed, message: friendlyError(e)),
        );
        if (e.isForbiddenRole || e.isSubscriptionInactive) break;
      } catch (e) {
        _outcomes.add(
          _ImportedRowResult(row: row, outcome: _RowOutcome.failed, message: friendlyError(e)),
        );
      }

      if (mounted) setState(() => _progress = _outcomes.length);
    }

    ref.invalidate(catalogProvider);
    if (mounted) setState(() => _step = _Step.done);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bulk import products'),
      content: SizedBox(
        width: 620,
        child: switch (_step) {
          _Step.pick => _PickStep(error: _pickError, onDownloadTemplate: _downloadTemplate),
          _Step.preview => _PreviewStep(
              fileName: _fileName!,
              result: _result!,
              needsWarehouse: _needsWarehouse,
              selectedWarehouseId: _effectiveWarehouseId,
              onWarehouseChanged: (id) => setState(() => _selectedWarehouseId = id),
            ),
          _Step.importing => _ImportingStep(total: _result!.validRows.length, done: _progress),
          _Step.done => _DoneStep(outcomes: _outcomes, stopReason: _stopReason),
        },
      ),
      actions: _actions(context),
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (_step) {
      case _Step.pick:
        return [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('Choose file…'),
          ),
        ];
      case _Step.preview:
        final hasValidRows = (_result?.validRows ?? const []).isNotEmpty;
        final canImport = hasValidRows && (!_needsWarehouse || _effectiveWarehouseId != null);
        return [
          TextButton(
            onPressed: () => setState(() {
              _step = _Step.pick;
              _result = null;
              _fileName = null;
            }),
            child: const Text('Choose a different file'),
          ),
          ElevatedButton(
            onPressed: canImport ? _runImport : null,
            child: Text(
              hasValidRows ? 'Import ${_result!.validRows.length} product(s)' : 'Nothing to import',
            ),
          ),
        ];
      case _Step.importing:
        return const [];
      case _Step.done:
        return [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_outcomes.any((o) => o.outcome != _RowOutcome.failed)),
            child: const Text('Done'),
          ),
        ];
    }
  }
}

class _PickStep extends StatelessWidget {
  const _PickStep({required this.error, required this.onDownloadTemplate});

  final String? error;
  final VoidCallback onDownloadTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload a .xlsx spreadsheet with one product per row. The first row must have column '
          'headers; SKU and Name are required, everything else is optional.',
        ),
        const SizedBox(height: 10),
        Text(
          'Recognized columns: SKU, Name, Barcode, Brand, Category, Unit, Description, Purchase '
          'price, Selling price, Reorder level, Maximum stock, Opening stock.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onDownloadTemplate,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Download template'),
        ),
        if (error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ],
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.fileName,
    required this.result,
    required this.needsWarehouse,
    required this.selectedWarehouseId,
    required this.onWarehouseChanged,
  });

  final String fileName;
  final ImportResult result;
  final bool needsWarehouse;
  final String? selectedWarehouseId;
  final ValueChanged<String?> onWarehouseChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(fileName, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              _CountChip(
                label: '${result.validRows.length} ready to import',
                color: const Color(0xFF2F8F5B),
                icon: Icons.check_circle_outline,
              ),
              if (result.invalidRows.isNotEmpty)
                _CountChip(
                  label: '${result.invalidRows.length} with errors',
                  color: theme.colorScheme.error,
                  icon: Icons.error_outline,
                ),
            ],
          ),
          if (needsWarehouse) ...[
            const SizedBox(height: 14),
            Consumer(
              builder: (context, ref, _) {
                final warehouses = ref.watch(activeWarehousesProvider);
                return DropdownButtonFormField<String>(
                  initialValue: selectedWarehouseId,
                  decoration: const InputDecoration(
                    labelText: 'Record opening stock in',
                    helperText: 'Used for every row with an opening stock value',
                  ),
                  items: [
                    for (final w in warehouses) DropdownMenuItem(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: onWarehouseChanged,
                  validator: (_) => warehouses.isEmpty ? 'No active warehouse available' : null,
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final row in result.validRows)
                  _RowTile(
                    ok: true,
                    title: '${row.input.sku} — ${row.input.name}',
                    subtitle: row.openingStock > 0
                        ? 'Row ${row.rowNumber} · opening stock ${row.openingStock}'
                        : 'Row ${row.rowNumber}',
                  ),
                for (final row in result.invalidRows)
                  _RowTile(
                    ok: false,
                    title: 'Row ${row.rowNumber}',
                    subtitle: row.messages.join('; '),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportingStep extends StatelessWidget {
  const _ImportingStep({required this.total, required this.done});

  final int total;
  final int done;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Importing $done of $total…'),
        ],
      ),
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.outcomes, required this.stopReason});

  final List<_ImportedRowResult> outcomes;
  final String? stopReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = outcomes.where((o) => o.outcome == _RowOutcome.created).length;
    final queued = outcomes.where((o) => o.outcome == _RowOutcome.queued).length;
    final skipped = outcomes.where((o) => o.outcome == _RowOutcome.skippedDuplicate).length;
    final failed = outcomes.where((o) => o.outcome == _RowOutcome.failed).length;
    final me = ProviderScope.containerOf(context, listen: false).read(authControllerProvider).valueOrNull;
    final atCap = stopReason != null;

    return SizedBox(
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failed == 0 && !atCap ? Icons.check_circle_outline : Icons.info_outline,
            size: 36,
            color: failed == 0 && !atCap ? const Color(0xFF2F8F5B) : theme.colorScheme.error,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (created > 0) _CountChip(label: '$created created', color: const Color(0xFF2F8F5B), icon: Icons.check_circle_outline),
              if (queued > 0) _CountChip(label: '$queued saved offline', color: theme.colorScheme.secondary, icon: Icons.cloud_off_outlined),
              if (skipped > 0) _CountChip(label: '$skipped duplicate SKU, skipped', color: theme.colorScheme.secondary, icon: Icons.content_copy_outlined),
              if (failed > 0) _CountChip(label: '$failed failed', color: theme.colorScheme.error, icon: Icons.error_outline),
            ],
          ),
          if (stopReason != null) ...[
            const SizedBox(height: 12),
            Text(
              'Import stopped early: $stopReason',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            if (me?.role == 'Owner') ...[
              const SizedBox(height: 4),
              const ManageBillingLink(),
            ],
          ],
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                for (final o in outcomes.where((o) => o.message != null))
                  _RowTile(
                    ok: o.outcome != _RowOutcome.failed,
                    title: '${o.row.input.sku} — ${o.row.input.name}',
                    subtitle: o.message!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.ok, required this.title, required this.subtitle});

  final bool ok;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = ok ? const Color(0xFF2F8F5B) : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
