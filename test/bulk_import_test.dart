// Bulk import's dialog, end to end against the fake repositories: pick a
// workbook (via a fake FilePicker.platform, so this never touches a real OS
// dialog) -> preview -> import -> done. Also covers the Products screen's
// "Show archived" ledger view and restoring an archived product.

import 'dart:typed_data';

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/products/presentation/products_screen.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';

const _ownerPermissions = [
  'products.write', 'products.archive', 'catalog.write', 'warehouses.manage',
  'stock.out', 'stock.adjust', 'customers.read', 'customers.write',
  'suppliers.read', 'suppliers.write', 'credit.record',
];

class _Auth extends AuthController {
  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'active',
        ),
        role: 'Owner',
        permissions: _ownerPermissions,
        plan: null,
      );
}

/// Hands back a fixed `.xlsx` workbook instead of opening a real OS dialog.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.bytes);

  final List<int> bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(name: 'import.xlsx', size: bytes.length, bytes: Uint8List.fromList(bytes)),
      ]);
}

List<int> _workbookBytes() {
  final excel = Excel.createExcel();
  final sheetName = excel.getDefaultSheet()!;
  final sheet = excel[sheetName];
  sheet.appendRow([
    TextCellValue('SKU'), TextCellValue('Name'), TextCellValue('Category'),
    TextCellValue('Unit'), TextCellValue('Purchase price'), TextCellValue('Selling price'),
    TextCellValue('Reorder level'), TextCellValue('Opening stock'),
  ]);
  sheet.appendRow([
    TextCellValue('RICE-50'), TextCellValue('Rice, 50kg'), TextCellValue('Grains'),
    TextCellValue('bag'), DoubleCellValue(32000), DoubleCellValue(38000),
    IntCellValue(10), IntCellValue(25),
  ]);
  sheet.appendRow([
    TextCellValue('SALT-1'), TextCellValue('Salt, 1kg'), TextCellValue('Grains'),
    TextCellValue('pack'), DoubleCellValue(500), DoubleCellValue(700),
    IntCellValue(20), IntCellValue(0),
  ]);
  return excel.encode()!;
}

/// Rejects "RICE-50" the way the real API rejects any duplicate SKU (`409`,
/// no machine-readable `code`), so the dialog's "skip and continue" path for
/// duplicates can be exercised without touching the real server's 409 rule.
class _DuplicateSkuRejectingRepository extends FakeProductsRepository {
  _DuplicateSkuRejectingRepository(super.products);

  @override
  Future<Product> create(ProductInput input) {
    if (input.sku == 'RICE-50') {
      throw ApiException(409, 'A product with this SKU already exists.');
    }
    return super.create(input);
  }
}

Future<void> _pumpProducts(WidgetTester tester, {required List<Override> overrides}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authControllerProvider.overrideWith(_Auth.new), ...overrides],
      child: const MaterialApp(home: ProductsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // There is no real platform implementation under `flutter test`, so
  // `FilePicker.platform` is set directly rather than read-and-restored.
  setUp(() => FilePicker.platform = _FakeFilePicker(_workbookBytes()));

  testWidgets('bulk import creates every valid row and records opening stock where given',
      (tester) async {
    final products = FakeProductsRepository([]);
    final inventory = FakeInventoryRepository();
    await _pumpProducts(
      tester,
      overrides: fakeDataOverrides(
        products: products,
        warehouses: FakeWarehousesRepository([fixtureWarehouse('w1', name: 'Main Warehouse')]),
        inventory: inventory,
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bulk import'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Choose file…'));
    await tester.pumpAndSettle();

    expect(find.text('2 ready to import'), findsOneWidget);
    expect(find.textContaining('RICE-50'), findsOneWidget);
    expect(find.textContaining('SALT-1'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Import 2 product(s)'));
    await tester.pumpAndSettle();

    expect(find.text('2 created'), findsOneWidget);
    expect(products.created.map((i) => i.sku), containsAll(['RICE-50', 'SALT-1']));

    // Only the row with an opening stock value produces a movement.
    expect(inventory.sent, hasLength(1));
    expect(inventory.sent.single.quantity, 25);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
    await tester.pumpAndSettle();

    expect(find.text('RICE-50'), findsOneWidget);
    expect(find.text('SALT-1'), findsOneWidget);
  });

  testWidgets('a duplicate SKU is skipped (not fatal) and the rest of the import still runs',
      (tester) async {
    final products = _DuplicateSkuRejectingRepository([fixtureProduct('1', name: 'Existing')]);
    await _pumpProducts(
      tester,
      overrides: fakeDataOverrides(
        products: products,
        warehouses: FakeWarehousesRepository([fixtureWarehouse('w1', name: 'Main Warehouse')]),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bulk import'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Choose file…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Import 2 product(s)'));
    await tester.pumpAndSettle();

    // RICE-50 collides and is skipped; SALT-1 still goes through.
    expect(find.text('1 created'), findsOneWidget);
    expect(find.text('1 duplicate SKU, skipped'), findsOneWidget);
    expect(products.created.map((i) => i.sku), ['SALT-1']);
  });

  testWidgets('"Show archived" lists an archived product and Restore brings it back',
      (tester) async {
    final archived = fixtureProduct('a1', name: 'Old Stock').withInput(
      ProductInput.fromJson({
        'sku': 'OLD-1', 'name': 'Old Stock', 'unit': 'bag', 'purchasePrice': 10,
        'sellingPrice': 15, 'minStock': 0,
      }),
    );
    final products = FakeProductsRepository(
      [fixtureProduct('1', name: 'Active One')],
      archivedProducts: [archived],
    );
    await _pumpProducts(tester, overrides: fakeDataOverrides(products: products));

    expect(find.text('OLD-1'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Show archived'));
    await tester.pumpAndSettle();

    expect(find.text('OLD-1'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);

    // The actions column sits at the right edge of a wide, horizontally
    // scrollable table — scroll it into view before tapping.
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(products.archivedProducts.any((p) => p.id == 'a1'), isFalse);
    expect(products.products.any((p) => p.id == 'a1'), isTrue);
  });
}
