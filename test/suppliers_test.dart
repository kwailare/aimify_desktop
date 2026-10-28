// Suppliers (feature checklist step 11): the list (cards, search, filters,
// archive and restore), the supplier's page (totals, purchases, products and
// prices, account), reorder suggestions that fill a purchase order, and Excel
// import and export for suppliers.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/customers/data/customer_excel.dart';
import 'package:aimify_desktop/features/customers/presentation/customer_import_dialog.dart';
import 'package:aimify_desktop/features/parties/data/supplier_options.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/purchases/data/reorder.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/purchases/presentation/purchase_form_dialog.dart';
import 'package:aimify_desktop/features/purchases/presentation/reorder_dialog.dart';
import 'package:aimify_desktop/features/suppliers/data/supplier_prices.dart';
import 'package:aimify_desktop/features/suppliers/presentation/supplier_profile_screen.dart';
import 'package:aimify_desktop/features/suppliers/presentation/suppliers_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

class _Auth extends AuthController {
  _Auth(this.role);

  final String role;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
          setupCompletedAt: DateTime(2026, 10, 1),
        ),
        role: role,
        permissions: defaultPermissionsFor(role),
      );
}

Party _supplier(
  String id,
  String name, {
  double balance = 0,
  double overdue = 0,
  bool active = true,
  String? contact,
  double bought = 0,
  int purchases = 0,
  DateTime? last,
}) =>
    Party(
      id: id,
      type: PartyType.supplier,
      name: name,
      contactPerson: contact,
      phone: '0801',
      balanceOwed: balance,
      overdue: overdue,
      isActive: active,
      totalPurchases: bought,
      purchaseCount: purchases,
      lastPurchaseAt: last,
      paymentTermsDays: 14,
    );

List<Party> _suppliers() => [
      _supplier('s1', 'Dangote Foods', balance: 90000, overdue: 40000, contact: 'Musa', bought: 500000, purchases: 4, last: DateTime(2026, 10, 20)),
      _supplier('s2', 'BUA Group', balance: 10000),
      _supplier('s3', 'Golden Grains'),
      _supplier('s4', 'Old Mills', active: false),
    ];

Product _product(String id, String name, {required String? supplierId, int stock = 10, int min = 5, int? max, double cost = 100}) =>
    fixtureProduct(id, name: name, stock: stock, min: min, cost: cost).withInput(
      ProductInput(
        sku: 'SKU-$id',
        name: name,
        unit: 'bag',
        purchasePrice: cost,
        sellingPrice: cost * 1.5,
        minStock: min,
        maxStock: max,
        supplierId: supplierId,
      ),
    );

SupplierProductPrice _price(String productId, String name, double last, double? previous) => SupplierProductPrice.fromJson({
      'productId': productId, 'name': name, 'sku': 'SKU-$productId', 'unit': 'bag', 'currentCost': last,
      'lastCost': last, 'lastDate': '2026-10-20T00:00:00.000Z', 'lastReference': 'PO-0004',
      'previousCost': previous, 'change': previous == null ? null : last - previous,
      'changePercent': previous == null ? null : ((last - previous) / previous * 100).roundToDouble(),
      'timesBought': previous == null ? 1 : 2,
      'history': [
        {'date': '2026-10-20T00:00:00.000Z', 'reference': 'PO-0004', 'purchaseId': 'p4', 'unitCost': last, 'quantity': 10},
        if (previous != null)
          {'date': '2026-09-01T00:00:00.000Z', 'reference': 'PO-0002', 'purchaseId': 'p2', 'unitCost': previous, 'quantity': 5},
      ],
    });

class _Rig {
  _Rig({this.role = 'Owner'})
      : parties = FakePartiesRepository(suppliers: _suppliers()),
        purchases = FakePurchasesRepository([
          fixturePurchase('p1', reference: 'PO-0001', supplierId: 's1', supplierName: 'Dangote Foods', status: PurchaseStatus.received,
              lines: [(productId: '1', quantity: 10, unitCost: 600, received: 10)]),
          fixturePurchase('p2', reference: 'PO-0002', supplierId: 's2', supplierName: 'BUA Group'),
        ]),
        products = FakeProductsRepository([
          _product('1', 'Rice', supplierId: 's1', stock: 2, min: 5, max: 20, cost: 600),
          _product('2', 'Sugar', supplierId: 's1', stock: 0, min: 4, cost: 500),
          _product('3', 'Salt', supplierId: 's2', stock: 50, min: 5),
          _product('4', 'Oil', supplierId: null, stock: 1, min: 3),
        ]),
        prices = FakeSupplierPricesRepository({
          's1': [_price('1', 'Rice', 650, 600), _price('5', 'Beans', 400, 450)],
        });

  final String role;
  final FakePartiesRepository parties;
  final FakePurchasesRepository purchases;
  final FakeProductsRepository products;
  final FakeSupplierPricesRepository prices;
}

Future<_Rig> _pump(WidgetTester tester, Widget home, {_Rig? rig, Size size = const Size(1500, 1000)}) async {
  final r = rig ?? _Rig();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(r.role)),
        ...fakeDataOverrides(
          parties: r.parties,
          purchases: r.purchases,
          products: r.products,
          supplierPrices: r.prices,
          supplierOptions: FakeSupplierOptionsRepository(const [
            SupplierOption(id: 's1', name: 'Dangote Foods'),
            SupplierOption(id: 's2', name: 'BUA Group'),
          ]),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: home)),
    ),
  );
  await _settle(tester);
  return r;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Finder _inCard(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.text(text));
Finder _segment(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

List<int> _sheet(List<List<Object?>> rows) {
  final workbook = Excel.createExcel();
  final sheet = workbook[workbook.getDefaultSheet()!];
  for (final row in rows) {
    sheet.appendRow([
      for (final cell in row) cell is num ? DoubleCellValue(cell.toDouble()) : TextCellValue(cell?.toString() ?? ''),
    ]);
  }
  return workbook.encode()!;
}

void main() {
  group('models', () {
    test('a supplier carries what is overdue and what was bought from them', () {
      final s = Party.fromJson(PartyType.supplier, {
        'id': 's1', 'name': 'Dangote', 'balanceOwed': 9000, 'overdue': 4000, 'totalPurchases': 120000,
        'purchaseCount': 3, 'lastPurchaseAt': '2026-10-01T00:00:00.000Z', 'paymentTermsDays': 14,
      });
      expect(s.overdue, 4000);
      expect(s.totalPurchases, 120000);
      expect(s.purchaseCount, 3);
      expect(s.lastPurchaseAt, isNotNull);
    });

    test('a price parses with its change and history', () {
      final p = _price('1', 'Rice', 650, 600);
      expect(p.wentUp, isTrue);
      expect(p.change, 50);
      expect(p.history.map((h) => h.reference), ['PO-0004', 'PO-0002']);
      expect(_price('5', 'Beans', 400, 450).wentDown, isTrue);
      expect(_price('6', 'Salt', 100, null).change, isNull);
    });

    test('reorder: low products by usual supplier, with suggested quantities', () {
      final groups = reorderGroups(
        [
          _product('1', 'Rice', supplierId: 's1', stock: 2, min: 5, max: 20),
          _product('2', 'Sugar', supplierId: 's1', stock: 0, min: 4),
          _product('3', 'Salt', supplierId: 's2', stock: 50, min: 5),
          _product('4', 'Oil', supplierId: null, stock: 1, min: 3),
          _product('5', 'Gone', supplierId: 's9', stock: 0, min: 2),
          _product('6', 'No level', supplierId: 's1', stock: 0, min: 0),
        ],
        const [SupplierOption(id: 's1', name: 'Dangote Foods'), SupplierOption(id: 's2', name: 'BUA')],
      );
      expect(groups.map((g) => g.supplierName), ['Dangote Foods', 'No usual supplier']);
      final dangote = groups.first;
      expect(dangote.lines.map((l) => (l.product.name, l.suggested)), [('Sugar', 8), ('Rice', 18)]);
      expect(groups.last.lines.map((l) => l.product.name), unorderedEquals(['Gone', 'Oil']),
          reason: "a supplier that isn't known any more counts as none");
    });
  });

  group('Excel', () {
    test('suppliers import with contact, terms and opening balance; existing names skipped', () {
      final parsed = parsePartyWorkbook(
        _sheet([
          ['Supplier name', 'Contact person', 'Terms', 'Opening balance', 'Credit limit'],
          ['Flour Mills', 'Ade', 45, 150000, 99],
          ['dangote foods', '', '', '', ''],
          ['Late Payer', '', 400, '', ''],
        ]),
        type: PartyType.supplier,
        existing: [_supplier('s1', 'Dangote Foods')],
      );
      final flour = parsed.rows.single;
      expect(flour.input.type, PartyType.supplier);
      expect(flour.input.contactPerson, 'Ade');
      expect(flour.input.paymentTermsDays, 45);
      expect(flour.input.creditLimit, 0, reason: 'suppliers have no credit limit');
      expect(flour.openingBalance, 150000);
      expect(parsed.skipped.single.messages.single, contains('already a supplier'));
      expect(parsed.errors.single.messages.single, contains('0 to 365'));
    });

    test('the supplier template imports, and the export lists terms, balance, overdue and totals', () {
      final parsed = parsePartyWorkbook(buildPartyImportTemplate(PartyType.supplier), type: PartyType.supplier);
      expect(parsed.rows.single.input.name, 'Dangote Foods Ltd');
      expect(parsed.rows.single.input.paymentTermsDays, 30);
      final rows = Excel.decodeBytes(buildSupplierExport(_suppliers())).sheets.values.first.rows;
      String cell(int r, int c) => rows[r][c]?.value.toString() ?? '';
      expect(cell(0, 1), 'Contact person');
      expect(cell(1, 0), 'Dangote Foods');
      expect(double.parse(cell(1, 6)), 90000);
      expect(double.parse(cell(1, 7)), 40000);
      expect(cell(4, 11), 'Archived');
    });
  });

  group('the list', () {
    testWidgets('cards, then You owe / Overdue / Archived with restore, and search by contact', (tester) async {
      final rig = await _pump(tester, const SuppliersScreen());
      expect(_inCard('suppliers-stat-count', '3'), findsOneWidget);
      expect(_inCard('suppliers-stat-owed', '₦100,000'), findsOneWidget);
      expect(_inCard('suppliers-stat-overdue', '₦40,000'), findsOneWidget);
      expect(find.text('Old Mills'), findsNothing);
      expect(find.text('Reorder (3)'), findsOneWidget, reason: 'Rice and Sugar from Dangote, Oil with no supplier');

      await tester.tap(_segment('suppliers-show', 'Overdue'));
      await _settle(tester);
      expect(find.text('Dangote Foods'), findsOneWidget);
      expect(find.text('BUA Group'), findsNothing);

      await tester.tap(_segment('suppliers-show', 'Archived'));
      await _settle(tester);
      tester.widget<TextButton>(find.byKey(const ValueKey('supplier-restore-s4'))).onPressed!();
      await _settle(tester);
      expect(rig.parties.restored, ['s4']);

      await tester.tap(_segment('suppliers-show', 'All'));
      await tester.enterText(find.byType(TextField).last, 'musa');
      await _settle(tester);
      expect(find.text('Dangote Foods'), findsOneWidget);
      expect(find.text('BUA Group'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('archiving asks first and keeps the supplier under Archived', (tester) async {
      await _pump(tester, const SuppliersScreen());
      tester.widget<IconButton>(find.byKey(const ValueKey('supplier-archive-s3'))).onPressed!();
      await _settle(tester);
      await tester.tap(find.byKey(const Key('supplier-confirm-archive')));
      await _settle(tester);
      expect(find.text('Golden Grains'), findsNothing);
      await tester.tap(_segment('suppliers-show', 'Archived'));
      await _settle(tester);
      expect(find.text('Golden Grains'), findsOneWidget);
    });

    testWidgets('the Accountant reads and exports, without adding, importing or reordering', (tester) async {
      await _pump(tester, const SuppliersScreen(), rig: _Rig(role: 'Accountant / Finance'));
      expect(find.text('Dangote Foods'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('suppliers-add'))).onPressed, isNull);
      expect(find.byKey(const Key('suppliers-import')), findsNothing);
      expect(find.byKey(const Key('suppliers-reorder')), findsNothing);
      expect(find.byKey(const Key('suppliers-export')), findsOneWidget);
    });

    testWidgets('Sales Staff are told suppliers are not for them', (tester) async {
      await _pump(tester, const SuppliersScreen(), rig: _Rig(role: 'Sales Staff'));
      expect(find.text("Your role can't view suppliers."), findsOneWidget);
    });
  });

  group("the supplier's page", () {
    testWidgets('totals, purchases, products with price changes, account', (tester) async {
      await _pump(tester, const SupplierProfileScreen(supplierId: 's1'));
      expect(find.byKey(const Key('supplier-name')), findsOneWidget);
      expect(_inCard('supplier-stat-owe', '₦90,000'), findsOneWidget);
      expect(_inCard('supplier-stat-owe', '₦40,000 overdue'), findsOneWidget);
      expect(_inCard('supplier-stat-bought', '4 purchases'), findsOneWidget);
      expect(find.text('PO-0001'), findsOneWidget);
      expect(find.text('PO-0002'), findsNothing, reason: "another supplier's purchase");

      await tester.tap(find.text('Products & prices'));
      await _settle(tester);
      expect(find.text('Rice · SKU-1'), findsOneWidget);
      expect(find.textContaining('+₦50'), findsOneWidget);
      expect(find.textContaining('−₦50'), findsOneWidget);
      expect(find.text('Sugar · SKU-2'), findsOneWidget, reason: 'linked, not bought from them yet');
      await tester.tap(find.text('Rice · SKU-1'));
      await _settle(tester);
      expect(find.text('Rice — price history'), findsOneWidget);
      expect(find.text('PO-0002'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await _settle(tester);

      await tester.tap(find.text('Account history'));
      await _settle(tester);
      expect(find.text('Nothing on their account yet.'), findsOneWidget);
      for (final key in ['supplier-new-purchase', 'supplier-reorder', 'supplier-record-payment', 'supplier-statement', 'supplier-edit', 'supplier-archive']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Warehouse Manager buys but does not pay', (tester) async {
      await _pump(tester, const SupplierProfileScreen(supplierId: 's1'), rig: _Rig(role: 'Warehouse Manager'));
      expect(find.byKey(const Key('supplier-new-purchase')), findsOneWidget);
      expect(find.byKey(const Key('supplier-record-payment')), findsNothing);
    });

    testWidgets('the Accountant pays but does not buy', (tester) async {
      await _pump(tester, const SupplierProfileScreen(supplierId: 's1'), rig: _Rig(role: 'Accountant / Finance'));
      expect(find.byKey(const Key('supplier-new-purchase')), findsNothing);
      expect(find.byKey(const Key('supplier-record-payment')), findsOneWidget);
    });

    testWidgets('an archived supplier can be restored', (tester) async {
      final rig = await _pump(tester, const SupplierProfileScreen(supplierId: 's4'));
      expect(find.byKey(const Key('supplier-new-purchase')), findsNothing);
      await tester.tap(find.byKey(const Key('supplier-restore')));
      await _settle(tester);
      expect(rig.parties.restored, ['s4']);
    });

    testWidgets('lays out without overflow at 1024×760', (tester) async {
      await _pump(tester, const SupplierProfileScreen(supplierId: 's1'), size: const Size(1024, 760));
      await tester.tap(find.text('Products & prices'));
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('reorder', () {
    testWidgets('the suggestions fill a purchase order for the supplier, without unticked lines', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog(context: context, builder: (_) => const ReorderDialog()),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.text('Dangote Foods'), findsOneWidget);
      expect(find.text('No usual supplier'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('reorder-qty-1'))).controller!.text, '18');

      await tester.enterText(find.byKey(const ValueKey('reorder-qty-1')), '12');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('reorder-line-2')), matching: find.byType(Checkbox)));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('reorder-order-s1')));
      await _settle(tester);

      final form = tester.widget<PurchaseFormDialog>(find.byType(PurchaseFormDialog));
      expect(form.initialSupplierId, 's1');
      expect(form.initialLines.map((l) => (l.productId, l.quantity, l.unitCost)), [('1', 12, 600.0)]);
      expect(find.text('Total ₦7,200'), findsOneWidget);
    });

    testWidgets("a supplier's page offers only their products", (tester) async {
      await _pump(tester, const SupplierProfileScreen(supplierId: 's1'));
      await tester.tap(find.byKey(const Key('supplier-reorder')));
      await _settle(tester);
      final dialog = find.byType(ReorderDialog);
      expect(find.descendant(of: dialog, matching: find.text('Dangote Foods')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('No usual supplier')), findsNothing);
    });
  });

  testWidgets('import suppliers with what you already owe them', (tester) async {
    final bytes = _sheet([
      ['Name', 'Contact person', 'Opening balance'],
      ['Flour Mills', 'Ade', 150000],
    ]);
    final rig = await _pump(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => CustomerImportDialog(
                type: PartyType.supplier,
                pickFile: () async => (name: 'suppliers.xlsx', bytes: bytes),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('Import suppliers'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customer-import-pick')));
    await _settle(tester);
    expect(find.textContaining('you owe ₦150,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('customer-import-run')));
    await _settle(tester);
    expect(rig.parties.created.single.contactPerson, 'Ade');
    expect(rig.parties.recorded.single.amount, 150000);
    expect(find.text('1 supplier added'), findsOneWidget);
  });
}
