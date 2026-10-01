import 'package:excel/excel.dart';

import '../domain/product.dart';

/// One row successfully parsed from an imported spreadsheet, ready to become
/// a product via the real `POST /api/v1/products`.
class ImportedProductRow {
  const ImportedProductRow({
    required this.rowNumber,
    required this.input,
    required this.openingStock,
  });

  /// The spreadsheet row this came from (1-based, matching what a
  /// spreadsheet program shows — row 1 is the header).
  final int rowNumber;
  final ProductInput input;

  /// Units to record as a `stock_in` movement right after the product is
  /// created. Zero means "no opening stock" — the product is just created
  /// with nothing on hand yet.
  final int openingStock;
}

/// A row that failed validation — shown in the preview so it can be fixed in
/// the spreadsheet and re-imported, rather than silently dropped.
class ImportRowError {
  const ImportRowError({required this.rowNumber, required this.messages, required this.rawCells});

  final int rowNumber;
  final List<String> messages;
  final List<String> rawCells;
}

class ImportResult {
  const ImportResult({required this.validRows, required this.invalidRows, this.sheetError});

  final List<ImportedProductRow> validRows;
  final List<ImportRowError> invalidRows;

  /// Set when the file itself couldn't be read at all — not even a header
  /// row — so there is nothing to preview (wrong file type, no sheets, a
  /// missing required column).
  final String? sheetError;

  bool get hasFatalError => sheetError != null;
}

/// Column headers this recognizes, matched case- and punctuation-insensitive
/// (`"Selling Price"`, `"selling_price"` and `"SellingPrice"` all match).
/// Only `sku` and `name` are required — everything else mirrors a field on
/// [ProductInput], plus `openingStock` for the post-create stock-in.
const _headerSynonyms = <String, List<String>>{
  'sku': ['sku'],
  'name': ['name', 'productname', 'product'],
  'barcode': ['barcode', 'upc', 'ean'],
  'brand': ['brand'],
  'category': ['category'],
  'unit': ['unit', 'unitofmeasure', 'uom'],
  'description': ['description', 'notes'],
  'purchasePrice': ['purchaseprice', 'cost', 'costprice'],
  'sellingPrice': ['sellingprice', 'price', 'saleprice'],
  'minStock': ['minstock', 'reorderlevel', 'lowstockthreshold', 'threshold', 'reorderpoint'],
  'maxStock': ['maxstock', 'maximumstock', 'upperlimit'],
  'openingStock': ['openingstock', 'stock', 'quantity', 'qty', 'initialstock'],
};

const _requiredFields = ['sku', 'name'];

String _normalizeHeader(String raw) => raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _cellText(Data? cell) {
  final value = cell?.value;
  if (value == null) return '';
  return value.toString().trim();
}

/// Parses an uploaded `.xlsx` file's first sheet into products ready to
/// import. Column order doesn't matter — headers are matched by name (see
/// [_headerSynonyms]); unrecognized columns are ignored. Fully blank rows
/// are skipped.
ImportResult parseProductWorkbook(List<int> bytes) {
  final Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } catch (_) {
    return const ImportResult(
      validRows: [],
      invalidRows: [],
      sheetError: "That file couldn't be read. Choose a .xlsx spreadsheet.",
    );
  }

  final sheetName = workbook.sheets.keys.firstOrNull;
  if (sheetName == null) {
    return const ImportResult(validRows: [], invalidRows: [], sheetError: 'The workbook has no sheets.');
  }
  final rows = workbook.sheets[sheetName]!.rows;
  if (rows.isEmpty) {
    return const ImportResult(validRows: [], invalidRows: [], sheetError: 'The sheet is empty.');
  }

  final header = rows.first;
  final columnByField = <String, int>{};
  for (var col = 0; col < header.length; col++) {
    final text = _normalizeHeader(_cellText(header[col]));
    if (text.isEmpty) continue;
    for (final entry in _headerSynonyms.entries) {
      if (!columnByField.containsKey(entry.key) && entry.value.contains(text)) {
        columnByField[entry.key] = col;
      }
    }
  }

  final missing = [for (final f in _requiredFields) if (!columnByField.containsKey(f)) f];
  if (missing.isNotEmpty) {
    return ImportResult(
      validRows: const [],
      invalidRows: const [],
      sheetError: 'Missing required column(s): ${missing.join(', ')}. The first row must have '
          'headers, and both SKU and Name are required.',
    );
  }

  String cellAt(List<Data?> row, String field) {
    final col = columnByField[field];
    if (col == null || col >= row.length) return '';
    return _cellText(row[col]);
  }

  final validRows = <ImportedProductRow>[];
  final invalidRows = <ImportRowError>[];

  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    final rawCells = [for (final c in row) _cellText(c)];
    if (rawCells.every((c) => c.isEmpty)) continue;

    final rowNumber = r + 1;
    final messages = <String>[];

    final sku = cellAt(row, 'sku');
    final name = cellAt(row, 'name');
    if (sku.isEmpty) messages.add('SKU is required');
    if (name.isEmpty) messages.add('Name is required');

    final unitText = cellAt(row, 'unit');
    final unit = unitText.isEmpty ? 'piece' : unitText;

    double parsePrice(String field, String label) {
      final raw = cellAt(row, field);
      if (raw.isEmpty) return 0;
      final parsed = double.tryParse(raw);
      if (parsed == null || parsed < 0) {
        messages.add('$label must be a number, 0 or more');
        return 0;
      }
      return parsed;
    }

    final purchasePrice = parsePrice('purchasePrice', 'Purchase price');
    final sellingPrice = parsePrice('sellingPrice', 'Selling price');

    int? parseWhole(String field, String label, {required bool addMessage}) {
      final raw = cellAt(row, field);
      if (raw.isEmpty) return null;
      final parsed = int.tryParse(raw) ?? double.tryParse(raw)?.round();
      if (parsed == null || parsed < 0) {
        if (addMessage) messages.add('$label must be a whole number, 0 or more');
        return null;
      }
      return parsed;
    }

    final minStockRaw = parseWhole('minStock', 'Reorder level', addMessage: true);
    final minStock = minStockRaw ?? 0;
    final maxStock = parseWhole('maxStock', 'Maximum stock', addMessage: true);
    if (maxStock != null && maxStock < minStock) {
      messages.add("Maximum stock can't be below the reorder level");
    }
    final openingStock = parseWhole('openingStock', 'Opening stock', addMessage: true) ?? 0;

    if (messages.isNotEmpty) {
      invalidRows.add(ImportRowError(rowNumber: rowNumber, messages: messages, rawCells: rawCells));
      continue;
    }

    validRows.add(
      ImportedProductRow(
        rowNumber: rowNumber,
        input: ProductInput(
          sku: sku,
          name: name,
          barcode: _orNull(cellAt(row, 'barcode')),
          description: _orNull(cellAt(row, 'description')),
          brand: _orNull(cellAt(row, 'brand')),
          category: _orNull(cellAt(row, 'category')),
          unit: unit,
          purchasePrice: purchasePrice,
          sellingPrice: sellingPrice,
          minStock: minStock,
          maxStock: maxStock,
        ),
        openingStock: openingStock,
      ),
    );
  }

  // A SKU repeated within the file itself — flagged here with a clear
  // reason, rather than letting every repeat past the first fail at the
  // server with a generic "SKU already exists".
  final seenAtRow = <String, int>{};
  final deduped = <ImportedProductRow>[];
  for (final row in validRows) {
    final key = row.input.sku.toLowerCase();
    final firstRowNumber = seenAtRow[key];
    if (firstRowNumber != null) {
      invalidRows.add(
        ImportRowError(
          rowNumber: row.rowNumber,
          messages: ['SKU "${row.input.sku}" is repeated — it was already used on row $firstRowNumber'],
          rawCells: [for (final c in rows[row.rowNumber - 1]) _cellText(c)],
        ),
      );
      continue;
    }
    seenAtRow[key] = row.rowNumber;
    deduped.add(row);
  }

  invalidRows.sort((a, b) => a.rowNumber.compareTo(b.rowNumber));
  return ImportResult(validRows: deduped, invalidRows: invalidRows);
}

String? _orNull(String value) => value.isEmpty ? null : value;

const _templateHeaders = [
  'SKU', 'Name', 'Barcode', 'Brand', 'Category', 'Unit', 'Description',
  'Purchase price', 'Selling price', 'Reorder level', 'Maximum stock', 'Opening stock',
];

/// A starter `.xlsx` with the header row this parser expects, plus one
/// example row — what "Download template" saves.
List<int> buildProductImportTemplate() {
  final workbook = Excel.createExcel();
  final sheetName = workbook.getDefaultSheet()!;
  final sheet = workbook[sheetName];

  sheet.appendRow([for (final h in _templateHeaders) TextCellValue(h)]);
  sheet.appendRow([
    TextCellValue('RICE-50KG'),
    TextCellValue('Rice, 50kg bag'),
    TextCellValue(''),
    TextCellValue('Golden Harvest'),
    TextCellValue('Grains'),
    TextCellValue('bag'),
    TextCellValue(''),
    DoubleCellValue(32000),
    DoubleCellValue(38000),
    IntCellValue(10),
    TextCellValue(''),
    IntCellValue(50),
  ]);

  return workbook.encode() ?? const [];
}
