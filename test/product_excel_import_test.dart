// Bulk import's parsing logic, tested against workbooks built the same way
// the `excel` package itself builds them — no fixture files on disk.

import 'package:aimify_desktop/features/products/data/product_excel_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _workbook(List<List<CellValue?>> rows) {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet()!;
  final sheet = excel[sheetName];
  for (final row in rows) {
    sheet.appendRow(row);
  }
  return excel.encode()!;
}

const _header = [
  'SKU', 'Name', 'Barcode', 'Brand', 'Category', 'Unit', 'Description',
  'Purchase price', 'Selling price', 'Reorder level', 'Maximum stock', 'Opening stock',
];

List<CellValue?> _headerRow() => [for (final h in _header) TextCellValue(h)];

List<CellValue?> _row({
  String sku = 'SKU-1',
  String name = 'Product',
  String barcode = '',
  String brand = '',
  String category = '',
  String unit = 'bag',
  String description = '',
  Object purchasePrice = 100,
  Object sellingPrice = 150,
  Object minStock = 5,
  Object? maxStock,
  Object openingStock = 10,
}) =>
    [
      TextCellValue(sku),
      TextCellValue(name),
      TextCellValue(barcode),
      TextCellValue(brand),
      TextCellValue(category),
      TextCellValue(unit),
      TextCellValue(description),
      purchasePrice is int ? IntCellValue(purchasePrice) : DoubleCellValue(purchasePrice as double),
      sellingPrice is int ? IntCellValue(sellingPrice) : DoubleCellValue(sellingPrice as double),
      minStock is int ? IntCellValue(minStock) : TextCellValue(minStock.toString()),
      maxStock == null
          ? TextCellValue('')
          : (maxStock is int ? IntCellValue(maxStock) : TextCellValue(maxStock.toString())),
      openingStock is int ? IntCellValue(openingStock) : TextCellValue(openingStock.toString()),
    ];

void main() {
  group('parseProductWorkbook', () {
    test('parses a well-formed row into a ProductInput plus opening stock', () {
      final bytes = _workbook([
        _headerRow(),
        _row(sku: 'RICE-50KG', name: 'Rice, 50kg', category: 'Grains', openingStock: 25),
      ]);

      final result = parseProductWorkbook(bytes);

      expect(result.hasFatalError, isFalse);
      expect(result.validRows, hasLength(1));
      expect(result.invalidRows, isEmpty);

      final row = result.validRows.single;
      expect(row.input.sku, 'RICE-50KG');
      expect(row.input.name, 'Rice, 50kg');
      expect(row.input.category, 'Grains');
      expect(row.input.purchasePrice, 100);
      expect(row.input.sellingPrice, 150);
      expect(row.input.minStock, 5);
      expect(row.openingStock, 25);
    });

    test('column order and header casing/punctuation do not matter', () {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet()!;
      final sheet = excel[sheetName];
      sheet.appendRow([TextCellValue('Product Name'), TextCellValue('sku')]);
      sheet.appendRow([TextCellValue('Rice'), TextCellValue('SKU-9')]);
      final bytes = excel.encode()!;

      final result = parseProductWorkbook(bytes);

      expect(result.hasFatalError, isFalse);
      expect(result.validRows, hasLength(1));
      expect(result.validRows.single.input.sku, 'SKU-9');
      expect(result.validRows.single.input.name, 'Rice');
      // Optional columns default sanely when the sheet doesn't have them.
      expect(result.validRows.single.input.unit, 'piece');
      expect(result.validRows.single.openingStock, 0);
    });

    test('a missing required column is a fatal, whole-file error', () {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet()!;
      final sheet = excel[sheetName];
      sheet.appendRow([TextCellValue('Name'), TextCellValue('Category')]);
      sheet.appendRow([TextCellValue('Rice'), TextCellValue('Grains')]);
      final bytes = excel.encode()!;

      final result = parseProductWorkbook(bytes);

      expect(result.hasFatalError, isTrue);
      expect(result.sheetError, contains('sku'));
    });

    test('a row missing SKU or Name is invalid, not fatal, and the rest still import', () {
      final bytes = _workbook([
        _headerRow(),
        _row(sku: '', name: 'No SKU'),
        _row(sku: 'OK-1', name: 'Fine'),
      ]);

      final result = parseProductWorkbook(bytes);

      expect(result.hasFatalError, isFalse);
      expect(result.validRows, hasLength(1));
      expect(result.validRows.single.input.sku, 'OK-1');
      expect(result.invalidRows, hasLength(1));
      expect(result.invalidRows.single.messages, contains('SKU is required'));
      expect(result.invalidRows.single.rowNumber, 2);
    });

    test('a negative price is invalid', () {
      final bytes = _workbook([_headerRow(), _row(purchasePrice: -5.0)]);

      final result = parseProductWorkbook(bytes);

      expect(result.validRows, isEmpty);
      expect(result.invalidRows.single.messages, contains('Purchase price must be a number, 0 or more'));
    });

    test('maximum stock below the reorder level is invalid', () {
      final bytes = _workbook([_headerRow(), _row(minStock: 10, maxStock: 5)]);

      final result = parseProductWorkbook(bytes);

      expect(result.validRows, isEmpty);
      expect(result.invalidRows.single.messages, contains("Maximum stock can't be below the reorder level"));
    });

    test('a SKU repeated within the file is flagged on its later row(s)', () {
      final bytes = _workbook([
        _headerRow(),
        _row(sku: 'DUP-1', name: 'First'),
        _row(sku: 'DUP-1', name: 'Second'),
      ]);

      final result = parseProductWorkbook(bytes);

      expect(result.validRows, hasLength(1));
      expect(result.validRows.single.input.name, 'First');
      expect(result.invalidRows, hasLength(1));
      expect(result.invalidRows.single.rowNumber, 3);
      expect(result.invalidRows.single.messages.single, contains('repeated'));
    });

    test('fully blank rows are skipped silently', () {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet()!;
      final sheet = excel[sheetName];
      sheet.appendRow(_headerRow());
      sheet.appendRow(_row(sku: 'A-1', name: 'A'));
      sheet.appendRow([for (var i = 0; i < _header.length; i++) TextCellValue('')]);
      sheet.appendRow(_row(sku: 'A-2', name: 'B'));
      final bytes = excel.encode()!;

      final result = parseProductWorkbook(bytes);

      expect(result.validRows, hasLength(2));
      expect(result.invalidRows, isEmpty);
    });

    test('an empty sheet is a fatal error', () {
      final bytes = _workbook([]);
      final result = parseProductWorkbook(bytes);
      expect(result.hasFatalError, isTrue);
    });

    test('bytes that are not a real workbook produce a fatal, friendly error', () {
      final result = parseProductWorkbook([1, 2, 3, 4]);
      expect(result.hasFatalError, isTrue);
      expect(result.sheetError, contains('.xlsx'));
    });
  });

  group('buildProductImportTemplate', () {
    test('round-trips through the parser as one valid row', () {
      final bytes = buildProductImportTemplate();
      final result = parseProductWorkbook(bytes);

      expect(result.hasFatalError, isFalse);
      expect(result.validRows, hasLength(1));
      expect(result.invalidRows, isEmpty);
    });
  });
}
