import 'package:aimify_desktop/features/products/data/product_excel_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _buildWorkbook(List<String> headers, List<List<CellValue?>> dataRows) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  sheet.appendRow([for (final h in headers) TextCellValue(h)]);
  for (final row in dataRows) {
    sheet.appendRow(row);
  }
  return excel.encode()!;
}

void main() {
  const headers = [
    'SKU',
    'Name',
    'Category',
    'Unit',
    'Purchase Price',
    'Selling Price',
    'Opening Stock',
    'Low Stock Threshold',
  ];

  test('parses valid rows with recognized headers', () {
    final bytes = _buildWorkbook(headers, [
      [
        TextCellValue('SAMPLE-SKU-100'),
        TextCellValue('Test Rice 50kg'),
        TextCellValue('Grains'),
        TextCellValue('Bag'),
        DoubleCellValue(30000),
        DoubleCellValue(36000),
        IntCellValue(20),
        IntCellValue(5),
      ],
    ]);

    final result = parseProductWorkbook(bytes);

    expect(result.hasFatalError, isFalse);
    expect(result.invalidRows, isEmpty);
    expect(result.validRows, hasLength(1));
    final row = result.validRows.single;
    expect(row.sku, 'SAMPLE-SKU-100');
    expect(row.name, 'Test Rice 50kg');
    expect(row.category, 'Grains');
    expect(row.unitOfMeasure, 'Bag');
    expect(row.purchasePrice, 30000);
    expect(row.sellingPrice, 36000);
    expect(row.openingStock, 20);
    expect(row.lowStockThreshold, 5);
  });

  test('accepts header synonyms and a blank SKU column', () {
    final bytes = _buildWorkbook(
      ['Product', 'Category', 'UoM', 'Cost', 'Price', 'Qty', 'Reorder Level'],
      [
        [
          TextCellValue('Groundnut Oil'),
          TextCellValue('Cooking Oil'),
          TextCellValue('Jerrican'),
          DoubleCellValue(18000),
          DoubleCellValue(22000),
          IntCellValue(12),
          IntCellValue(4),
        ],
      ],
    );

    final result = parseProductWorkbook(bytes);

    expect(result.hasFatalError, isFalse);
    expect(result.validRows, hasLength(1));
    expect(result.validRows.single.sku, isNull);
    expect(result.validRows.single.name, 'Groundnut Oil');
  });

  test('collects per-row errors without discarding the rest of the file', () {
    final bytes = _buildWorkbook(headers, [
      // Valid row.
      [
        TextCellValue('S1'),
        TextCellValue('Good Row'),
        TextCellValue('Grains'),
        TextCellValue('Bag'),
        DoubleCellValue(1000),
        DoubleCellValue(1500),
        IntCellValue(10),
        IntCellValue(2),
      ],
      // Missing name + bad price.
      [
        TextCellValue('S2'),
        TextCellValue(''),
        TextCellValue('Grains'),
        TextCellValue('Bag'),
        TextCellValue('not-a-number'),
        DoubleCellValue(1500),
        IntCellValue(10),
        IntCellValue(2),
      ],
    ]);

    final result = parseProductWorkbook(bytes);

    expect(result.hasFatalError, isFalse);
    expect(result.validRows, hasLength(1));
    expect(result.invalidRows, hasLength(1));
    expect(result.invalidRows.single.rowNumber, 3);
    expect(result.invalidRows.single.messages, contains('Name is required'));
    expect(
      result.invalidRows.single.messages,
      contains('Purchase price must be a non-negative number'),
    );
  });

  test('skips fully blank rows', () {
    final bytes = _buildWorkbook(headers, [
      [null, null, null, null, null, null, null, null],
      [
        TextCellValue('S1'),
        TextCellValue('Real Row'),
        TextCellValue('Grains'),
        TextCellValue('Bag'),
        DoubleCellValue(1000),
        DoubleCellValue(1500),
        IntCellValue(10),
        IntCellValue(2),
      ],
    ]);

    final result = parseProductWorkbook(bytes);

    expect(result.validRows, hasLength(1));
    expect(result.invalidRows, isEmpty);
  });

  test('reports a fatal error when required columns are missing', () {
    final bytes = _buildWorkbook(['Name', 'Category'], [
      [TextCellValue('Only Two Columns'), TextCellValue('Grains')],
    ]);

    final result = parseProductWorkbook(bytes);

    expect(result.hasFatalError, isTrue);
    expect(result.sheetError, contains('Missing column'));
  });

  test('reports a fatal error for an empty sheet', () {
    final excel = Excel.createExcel();
    final bytes = excel.encode()!;

    final result = parseProductWorkbook(bytes);

    expect(result.hasFatalError, isTrue);
  });
}
