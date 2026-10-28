// Product ↔ supplier link (feature checklist step 4): one usual supplier per
// product, picked in the product form, shown under the product's name and as
// "Products supplied" on the supplier, matched by name in the Excel import,
// with supplier names readable without `suppliers.view`.

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/parties/data/supplier_options.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/suppliers/presentation/supplier_profile_screen.dart';
import 'package:aimify_desktop/features/products/data/product_excel_import.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/products/presentation/product_form_dialog.dart';
import 'package:aimify_desktop/features/products/presentation/products_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

const _dangote = SupplierOption(id: 's1', name: 'Dangote Foods Ltd');
const _bua = SupplierOption(id: 's2', name: 'Bua Foods');
const _old = SupplierOption(id: 's3', name: 'Old Mills', isArchived: true);

class _Auth extends AuthController {
  _Auth(this.permissions);

  final List<String> permissions;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
          setupCompletedAt: DateTime(2026, 10, 1),
        ),
        role: 'Inventory Staff',
        permissions: permissions,
      );
}

Product _linked(String id, String name, String? supplierId) =>
    fixtureProduct(id, name: name).withInput(
      ProductInput(
        sku: 'SKU-$id',
        name: name,
        unit: 'bag',
        purchasePrice: 100,
        sellingPrice: 120,
        minStock: 5,
        supplierId: supplierId,
      ),
    );

List<int> _workbook(List<List<String>> rows) {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  for (final row in rows) {
    sheet.appendRow([for (final cell in row) TextCellValue(cell)]);
  }
  return excel.encode()!;
}

Future<void> _pump(WidgetTester tester, Widget child, List<Override> overrides) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: Scaffold(body: child))));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  group('model', () {
    test('supplierId round-trips through JSON, input and local copies', () {
      final product = Product.fromJson({
        'id': 'p1', 'sku': 'A', 'name': 'Rice', 'unit': 'bag', 'status': 'active', 'supplierId': 's1',
      });
      expect(product.supplierId, 's1');
      expect(Product.fromJson({'id': 'p2', 'sku': 'B', 'name': 'Beans'}).supplierId, isNull);

      const input = ProductInput(
        sku: 'A', name: 'Rice', unit: 'bag', purchasePrice: 1, sellingPrice: 2, minStock: 0, supplierId: 's1',
      );
      expect(input.toJson()['supplierId'], 's1');
      expect(ProductInput.fromJson(input.toJson()).supplierId, 's1', reason: 'offline queue keeps it');
      expect(input.toLocalProduct('local:1').supplierId, 's1');
      expect(product.withMovement('w1', 9).supplierId, 's1');
    });

    test('an unlinked edit sends supplierId: null so the server clears it', () {
      const input = ProductInput(sku: 'A', name: 'Rice', unit: 'bag', purchasePrice: 1, sellingPrice: 2, minStock: 0);
      expect(input.toJson().containsKey('supplierId'), isTrue);
      expect(input.toJson()['supplierId'], isNull);
    });

    test('matching supplier names ignores case and spacing, never archived ones', () {
      const options = [_dangote, _bua, _old];
      expect(matchSupplierByName(options, '  dangote   FOODS ltd ')?.id, 's1');
      expect(matchSupplierByName(options, 'Old Mills'), isNull);
      expect(matchSupplierByName(options, 'Nobody'), isNull);
      expect(matchSupplierByName(options, ''), isNull);
      expect(_old.label, 'Old Mills (archived)');
    });
  });

  group('Excel import', () {
    test('a Supplier column links matching rows and warns about unknown names', () {
      final result = parseProductWorkbook(
        _workbook([
          ['SKU', 'Name', 'Supplier'],
          ['R1', 'Rice', 'dangote foods ltd'],
          ['R2', 'Beans', 'Nobody Ltd'],
          ['R3', 'Oil', ''],
          ['R4', 'Flour', 'Old Mills'],
        ]),
        suppliers: const [_dangote, _bua, _old],
      );
      expect(result.invalidRows, isEmpty, reason: 'a supplier problem never blocks the row');
      final bySku = {for (final r in result.validRows) r.input.sku: r};
      expect(bySku['R1']!.input.supplierId, 's1');
      expect(bySku['R1']!.warning, isNull);
      expect(bySku['R2']!.input.supplierId, isNull);
      expect(bySku['R2']!.warning, contains('"Nobody Ltd" not found'));
      expect(bySku['R3']!.input.supplierId, isNull);
      expect(bySku['R3']!.warning, isNull);
      expect(bySku['R4']!.input.supplierId, isNull, reason: 'archived suppliers are not linked');
      expect(bySku['R4']!.warning, isNotNull);
    });

    test('"Vendor" is accepted as the column name', () {
      final result = parseProductWorkbook(
        _workbook([
          ['SKU', 'Name', 'Vendor'],
          ['R1', 'Rice', 'Bua Foods'],
        ]),
        suppliers: const [_dangote, _bua],
      );
      expect(result.validRows.single.input.supplierId, 's2');
    });

    test('without a Supplier column nothing changes', () {
      final result = parseProductWorkbook(_workbook([
        ['SKU', 'Name'],
        ['R1', 'Rice'],
      ]));
      expect(result.validRows.single.input.supplierId, isNull);
      expect(result.validRows.single.warning, isNull);
    });
  });

  group('screens', () {
    testWidgets('the product list shows each product\'s supplier under its name', (tester) async {
      await _pump(tester, const ProductsScreen(), [
        authControllerProvider.overrideWith(() => _Auth(defaultPermissionsFor('Inventory Staff'))),
        ...fakeDataOverrides(
          products: FakeProductsRepository([_linked('1', 'Rice', 's1'), _linked('2', 'Beans', 's3')]),
          supplierOptions: FakeSupplierOptionsRepository(const [_dangote, _bua, _old]),
        ),
      ]);
      expect(find.text('Dangote Foods Ltd'), findsOneWidget);
      expect(find.text('Old Mills (archived)'), findsOneWidget);
    });

    testWidgets('picking a supplier in the form saves it on the new product', (tester) async {
      final products = FakeProductsRepository([]);
      await _pump(tester, const ProductFormDialog(), [
        authControllerProvider.overrideWith(() => _Auth(defaultPermissionsFor('Inventory Staff'))),
        ...fakeDataOverrides(
          products: products,
          supplierOptions: FakeSupplierOptionsRepository(const [_dangote, _bua, _old]),
        ),
      ]);

      await tester.enterText(find.widgetWithText(TextFormField, 'SKU *'), 'RICE-50');
      await tester.enterText(find.widgetWithText(TextFormField, 'Name *'), 'Rice 50kg');
      await tester.enterText(find.widgetWithText(TextFormField, 'Purchase price *'), '61000');
      await tester.enterText(find.widgetWithText(TextFormField, 'Selling price *'), '65000');
      await tester.tap(find.byKey(const Key('product-supplier')));
      await tester.pumpAndSettle();
      expect(find.text('Old Mills (archived)'), findsNothing, reason: 'archived suppliers are not offered');
      await tester.tap(find.text('Bua Foods').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add product').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(products.created.single.supplierId, 's2');
    });

    testWidgets('editing a product linked to an archived supplier keeps the link', (tester) async {
      final product = _linked('1', 'Rice', 's3');
      final products = FakeProductsRepository([product]);
      await _pump(tester, ProductFormDialog(product: product), [
        authControllerProvider.overrideWith(() => _Auth(defaultPermissionsFor('Inventory Staff'))),
        ...fakeDataOverrides(
          products: products,
          supplierOptions: FakeSupplierOptionsRepository(const [_dangote, _old]),
        ),
      ]);
      expect(find.text('Old Mills (archived)'), findsOneWidget, reason: 'shown as the current value');
    });

    testWidgets("a supplier's page lists the products it supplies", (tester) async {
      final supplier = fixtureParty('s1', type: PartyType.supplier, name: 'Dangote Foods Ltd');
      await _pump(tester, const SupplierProfileScreen(supplierId: 's1'), [
        authControllerProvider.overrideWith(() => _Auth(defaultPermissionsFor('Warehouse Manager'))),
        ...fakeDataOverrides(
          products: FakeProductsRepository([
            _linked('1', 'Rice', 's1'),
            _linked('2', 'Beans', 's2'),
            _linked('3', 'Semovita', 's1'),
          ]),
          parties: FakePartiesRepository(suppliers: [supplier]),
        ),
      ]);
      await tester.tap(find.text('Products & prices'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.textContaining('Rice ·'), findsOneWidget);
      expect(find.textContaining('Semovita ·'), findsOneWidget);
      expect(find.textContaining('Beans'), findsNothing);
      expect(find.text('Not bought from them yet'), findsNWidgets(2));
    });
  });

  group('access', () {
    test('supplier names are fetched with products.view alone, and not without it', () async {
      Future<int> callsWith(List<String> permissions) async {
        final options = FakeSupplierOptionsRepository(const [_dangote]);
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(() => _Auth(permissions)),
            ...fakeDataOverrides(supplierOptions: options),
          ],
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);
        await container.read(supplierOptionsProvider.future);
        return options.listCalls;
      }

      expect(await callsWith(['products.view']), 1);
      expect(await callsWith(['suppliers.view']), 1);
      expect(await callsWith(['customers.view', 'credit.record']), 0);
    });
  });
}
