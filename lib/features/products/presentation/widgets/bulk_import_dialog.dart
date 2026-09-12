import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/formatters.dart';
import '../../../inventory/data/warehouse_stock_repository.dart';
import '../../../inventory/domain/warehouse_stock.dart';
import '../../../warehouses/data/warehouses_repository.dart';
import '../../../warehouses/domain/warehouse.dart';
import '../../data/product_excel_import.dart';
import '../../data/products_repository.dart';
import '../../domain/product.dart';

/// Bulk-imports a product catalog (plus opening stock for one warehouse)
/// from an .xlsx file. Parsing is real (see `product_excel_import.dart`
/// and its round-trip tests); the write side is the same MOCK
/// [productsProvider] / [warehouseStockProvider] every other add-product
/// flow in the app uses.
class BulkImportDialog extends ConsumerStatefulWidget {
  const BulkImportDialog({super.key});

  @override
  ConsumerState<BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends ConsumerState<BulkImportDialog> {
  ImportResult? _result;
  String? _fileName;
  String? _pickError;
  bool _picking = false;
  bool _imported = false;
  String? _warehouseId;

  @override
  void initState() {
    super.initState();
    _warehouseId = ref.read(selectedWarehouseIdProvider);
  }

  Future<void> _pickFile() async {
    setState(() {
      _picking = true;
      _pickError = null;
    });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        setState(() => _picking = false);
        return;
      }

      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _picking = false;
          _pickError = "Couldn't read that file's contents.";
        });
        return;
      }

      final result = parseProductWorkbook(bytes);
      setState(() {
        _picking = false;
        _fileName = file.name;
        _result = result;
      });
    } catch (_) {
      setState(() {
        _picking = false;
        _pickError = "Couldn't open that file. Make sure it's a .xlsx spreadsheet.";
      });
    }
  }

  void _confirmImport() {
    final result = _result;
    final warehouseId = _warehouseId;
    if (result == null || warehouseId == null || result.validRows.isEmpty) return;

    final existingCount = ref.read(productsProvider).length;
    var nextIndex = existingCount + 1;

    for (final row in result.validRows) {
      final productId = 'p${DateTime.now().microsecondsSinceEpoch}-${row.rowNumber}';
      ref.read(productsProvider.notifier).addProduct(
            Product(
              id: productId,
              sku: row.sku ?? 'SAMPLE-SKU-${(nextIndex++).toString().padLeft(3, '0')}',
              barcode: '—',
              name: row.name,
              category: row.category,
              unitOfMeasure: row.unitOfMeasure,
              purchasePrice: row.purchasePrice,
              sellingPrice: row.sellingPrice,
            ),
          );
      ref.read(warehouseStockProvider.notifier).setStock(
            WarehouseStock(
              productId: productId,
              warehouseId: warehouseId,
              quantity: row.openingStock,
              lowStockThreshold: row.lowStockThreshold,
            ),
          );
    }

    setState(() => _imported = true);
  }

  @override
  Widget build(BuildContext context) {
    final warehouses = ref.watch(warehousesProvider);

    return AlertDialog(
      title: const Text('Import products from Excel'),
      content: SizedBox(
        width: 520,
        child: _imported
            ? _ImportSuccess(count: _result!.validRows.length)
            : _result == null
                ? _PickStep(
                    picking: _picking,
                    error: _pickError,
                    onPick: _pickFile,
                  )
                : _PreviewStep(
                    fileName: _fileName!,
                    result: _result!,
                    warehouses: warehouses,
                    warehouseId: _warehouseId,
                    onWarehouseChanged: (id) => setState(() => _warehouseId = id),
                    onPickDifferentFile: () => setState(() {
                      _result = null;
                      _fileName = null;
                    }),
                  ),
      ),
      actions: _imported
          ? [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              if (_result != null && !_result!.hasFatalError)
                ElevatedButton(
                  onPressed: _result!.validRows.isEmpty || _warehouseId == null
                      ? null
                      : _confirmImport,
                  child: Text('Import ${_result!.validRows.length} product(s)'),
                ),
            ],
    );
  }
}

class _PickStep extends StatelessWidget {
  const _PickStep({required this.picking, required this.error, required this.onPick});

  final bool picking;
  final String? error;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Expected columns (any order): Name, Category, Unit, Purchase Price, '
          'Selling Price, Opening Stock, Low Stock Threshold. SKU is optional — '
          "one's generated if left blank.",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: picking ? null : onPick,
          icon: picking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file_outlined),
          label: Text(picking ? 'Reading file…' : 'Choose .xlsx file'),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.fileName,
    required this.result,
    required this.warehouses,
    required this.warehouseId,
    required this.onWarehouseChanged,
    required this.onPickDifferentFile,
  });

  final String fileName;
  final ImportResult result;
  final List<Warehouse> warehouses;
  final String? warehouseId;
  final ValueChanged<String?> onWarehouseChanged;
  final VoidCallback onPickDifferentFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (result.hasFatalError) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(fileName, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 12),
          Text(result.sheetError!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onPickDifferentFile, child: const Text('Choose a different file')),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(fileName, overflow: TextOverflow.ellipsis)),
            TextButton(onPressed: onPickDifferentFile, child: const Text('Change file')),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _CountChip(
              label: '${result.validRows.length} ready',
              color: const Color(0xFF2F8F5B),
              icon: Icons.check_circle_outline,
            ),
            if (result.invalidRows.isNotEmpty)
              _CountChip(
                label: '${result.invalidRows.length} need fixing',
                color: theme.colorScheme.error,
                icon: Icons.error_outline,
              ),
          ],
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: warehouseId,
          decoration: const InputDecoration(labelText: 'Import into warehouse'),
          items: [
            for (final warehouse in warehouses)
              DropdownMenuItem(value: warehouse.id, child: Text(warehouse.name)),
          ],
          onChanged: onWarehouseChanged,
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final row in result.validRows)
                  _RowTile(
                    ok: true,
                    title: row.name,
                    subtitle:
                        '${row.category} · ${currencyFormat.format(row.sellingPrice)} · '
                        '${row.openingStock} ${row.unitOfMeasure}(s)',
                  ),
                for (final error in result.invalidRows)
                  _RowTile(
                    ok: false,
                    title: 'Row ${error.rowNumber}',
                    subtitle: error.messages.join('; '),
                  ),
              ],
            ),
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
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

class _ImportSuccess extends StatelessWidget {
  const _ImportSuccess({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF2F8F5B), size: 40),
        const SizedBox(height: 12),
        Text('$count product(s) imported', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
