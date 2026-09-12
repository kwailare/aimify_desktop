import 'package:excel/excel.dart';

/// One successfully-parsed row from an imported spreadsheet, ready to
/// become a [Product] + opening [WarehouseStock] once a target warehouse
/// is chosen (see `bulk_import_dialog.dart`).
class ImportedProductRow {
  const ImportedProductRow({
    required this.rowNumber,
    required this.sku,
    required this.name,
    required this.category,
    required this.unitOfMeasure,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.openingStock,
    required this.lowStockThreshold,
  });

  /// 1-based row number as it appears in the spreadsheet (header is row 1).
  final int rowNumber;
  final String? sku;
  final String name;
  final String category;
  final String unitOfMeasure;
  final double purchasePrice;
  final double sellingPrice;
  final int openingStock;
  final int lowStockThreshold;
}

/// A row that failed validation, plus what raw text was in it so the
/// preview table can show the admin exactly what needs fixing.
class ImportRowError {
  const ImportRowError({
    required this.rowNumber,
    required this.messages,
    required this.rawCells,
  });

  final int rowNumber;
  final List<String> messages;
  final List<String> rawCells;
}

class ImportResult {
  const ImportResult({
    required this.validRows,
    required this.invalidRows,
    this.sheetError,
  });

  final List<ImportedProductRow> validRows;
  final List<ImportRowError> invalidRows;

  /// Set instead of parsing any rows when the file itself is unusable —
  /// empty, unreadable, or missing required columns entirely.
  final String? sheetError;

  bool get hasFatalError => sheetError != null;
}

/// Column headers we recognize, keyed by canonical field name. Matching is
/// case-insensitive and ignores spaces/punctuation, so "Purchase Price",
/// "purchase_price" and "Cost" all resolve to `purchasePrice`.
const _headerSynonyms = {
  'sku': ['sku'],
  'name': ['name', 'productname', 'product'],
  'category': ['category'],
  'unitOfMeasure': ['unit', 'unitofmeasure', 'uom'],
  'purchasePrice': ['purchaseprice', 'cost', 'costprice'],
  'sellingPrice': ['sellingprice', 'price', 'saleprice'],
  'openingStock': ['openingstock', 'stock', 'quantity', 'qty'],
  'lowStockThreshold': ['lowstockthreshold', 'reorderlevel', 'threshold', 'reorderpoint'],
};

const _requiredFields = [
  'name',
  'category',
  'unitOfMeasure',
  'purchasePrice',
  'sellingPrice',
  'openingStock',
  'lowStockThreshold',
];

String _normalizeHeader(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _cellText(Data? cell) {
  final value = cell?.value;
  if (value == null) return '';
  // Every CellValue variant's toString() already returns a sensible plain
  // representation (excel's own TextSpan.toString() concatenates its text,
  // notably — it's not Flutter's TextSpan) so a single fallback covers them.
  return value.toString().trim();
}

/// Parses the first sheet of an .xlsx file's bytes into product rows.
/// Pure/synchronous and fully unit-testable — no file I/O here, so the
/// same logic that reads a real user-picked file is exercised directly in
/// `test/product_excel_import_test.dart` against workbooks built with this
/// same package's writer API.
ImportResult parseProductWorkbook(List<int> bytes) {
  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (_) {
    return const ImportResult(
      validRows: [],
      invalidRows: [],
      sheetError: "Couldn't read that file — make sure it's a valid .xlsx spreadsheet.",
    );
  }

  if (excel.tables.isEmpty) {
    return const ImportResult(
      validRows: [],
      invalidRows: [],
      sheetError: 'That spreadsheet has no sheets.',
    );
  }

  final sheet = excel.tables.values.first;
  final rows = sheet.rows;
  if (rows.isEmpty) {
    return const ImportResult(
      validRows: [],
      invalidRows: [],
      sheetError: 'The first sheet is empty.',
    );
  }

  final headerRow = rows.first;
  final columnByField = <String, int>{};
  for (var col = 0; col < headerRow.length; col++) {
    final normalized = _normalizeHeader(_cellText(headerRow[col]));
    for (final entry in _headerSynonyms.entries) {
      if (entry.value.contains(normalized)) {
        columnByField[entry.key] = col;
      }
    }
  }

  final missing = _requiredFields.where((f) => !columnByField.containsKey(f)).toList();
  if (missing.isNotEmpty) {
    return ImportResult(
      validRows: const [],
      invalidRows: const [],
      sheetError: 'Missing column(s) in the header row: ${missing.join(', ')}. '
          'Expected: Name, Category, Unit, Purchase Price, Selling Price, '
          'Opening Stock, Low Stock Threshold (SKU optional).',
    );
  }

  String cellFor(List<Data?> row, String field) {
    final col = columnByField[field];
    if (col == null || col >= row.length) return '';
    return _cellText(row[col]);
  }

  final validRows = <ImportedProductRow>[];
  final invalidRows = <ImportRowError>[];

  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    final rawCells = [for (final cell in row) _cellText(cell)];
    if (rawCells.every((c) => c.isEmpty)) continue; // skip fully blank rows

    final errors = <String>[];

    final name = cellFor(row, 'name');
    if (name.isEmpty) errors.add('Name is required');

    final category = cellFor(row, 'category');
    if (category.isEmpty) errors.add('Category is required');

    final unit = cellFor(row, 'unitOfMeasure');
    if (unit.isEmpty) errors.add('Unit is required');

    final purchasePrice = double.tryParse(cellFor(row, 'purchasePrice'));
    if (purchasePrice == null || purchasePrice < 0) {
      errors.add('Purchase price must be a non-negative number');
    }

    final sellingPrice = double.tryParse(cellFor(row, 'sellingPrice'));
    if (sellingPrice == null || sellingPrice < 0) {
      errors.add('Selling price must be a non-negative number');
    }

    final openingStock = int.tryParse(cellFor(row, 'openingStock'));
    if (openingStock == null || openingStock < 0) {
      errors.add('Opening stock must be a non-negative whole number');
    }

    final lowStockThreshold = int.tryParse(cellFor(row, 'lowStockThreshold'));
    if (lowStockThreshold == null || lowStockThreshold < 0) {
      errors.add('Low-stock threshold must be a non-negative whole number');
    }

    if (errors.isNotEmpty) {
      invalidRows.add(ImportRowError(rowNumber: i + 1, messages: errors, rawCells: rawCells));
      continue;
    }

    final sku = cellFor(row, 'sku');
    validRows.add(
      ImportedProductRow(
        rowNumber: i + 1,
        sku: sku.isEmpty ? null : sku,
        name: name,
        category: category,
        unitOfMeasure: unit,
        purchasePrice: purchasePrice!,
        sellingPrice: sellingPrice!,
        openingStock: openingStock!,
        lowStockThreshold: lowStockThreshold!,
      ),
    );
  }

  return ImportResult(validRows: validRows, invalidRows: invalidRows);
}
