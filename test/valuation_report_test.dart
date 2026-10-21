// Inventory valuation report (feature checklist step 6): parsing the server
// report, the Valuation tab's totals, groupings, filters, search, warnings,
// permissions and layout.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/reports/data/valuation_report.dart';
import 'package:aimify_desktop/features/reports/presentation/reports_screen.dart';
import 'package:aimify_desktop/features/warehouses/domain/warehouse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

const _json = {
  'asOf': '2026-10-21T10:00:00.000Z',
  'basis': 'current_purchase_price',
  'totals': {'products': 3, 'units': 40, 'valueAtCost': 1042000, 'valueAtRetail': 1129000, 'margin': 87000, 'marginPercent': 7.71},
  'byProduct': [
    {
      'productId': 'p1', 'sku': 'RICE-50', 'name': 'Rice 50kg', 'category': 'Grains', 'unit': 'bag',
      'quantity': 12, 'unitCost': 61000, 'unitPrice': 65000, 'valueAtCost': 732000, 'valueAtRetail': 780000,
      'margin': 48000, 'warehouses': [], 'flags': [],
    },
    {
      'productId': 'p2', 'sku': 'BEANS', 'name': 'Beans', 'category': 'Grains', 'unit': 'bag',
      'quantity': 3, 'unitCost': 30000, 'unitPrice': 33000, 'valueAtCost': 90000, 'valueAtRetail': 99000,
      'margin': 9000, 'warehouses': [], 'flags': ['negative_stock'],
    },
    {
      'productId': 'p3', 'sku': 'GIFT', 'name': 'Free sample', 'category': null, 'unit': 'piece',
      'quantity': 25, 'unitCost': 0, 'unitPrice': 0, 'valueAtCost': 0, 'valueAtRetail': 0,
      'margin': 0, 'warehouses': [], 'flags': ['no_cost', 'something_new'],
    },
  ],
  'byCategory': [
    {'category': 'Grains', 'products': 2, 'units': 15, 'valueAtCost': 822000, 'valueAtRetail': 879000, 'margin': 57000, 'marginPercent': 6.48},
    {'category': null, 'products': 1, 'units': 25, 'valueAtCost': 0, 'valueAtRetail': 0, 'margin': 0, 'marginPercent': null},
  ],
  'byWarehouse': [
    {'warehouseId': 'w1', 'name': 'Lagos', 'status': 'active', 'products': 3, 'units': 19, 'valueAtCost': 730000, 'valueAtRetail': 779000, 'margin': 49000, 'marginPercent': 6.29},
    {'warehouseId': 'w2', 'name': 'Kano', 'status': 'inactive', 'products': 2, 'units': 21, 'valueAtCost': 312000, 'valueAtRetail': 350000, 'margin': 38000, 'marginPercent': 10.86},
  ],
  'warnings': {'negativeStock': 1, 'noCost': 1},
};

class _Auth extends AuthController {
  _Auth(this.permissions);

  final List<String> permissions;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Lagos',
          subscriptionStatus: 'trial',
          setupCompletedAt: DateTime(2026, 10, 1),
        ),
        role: 'Owner',
        permissions: permissions,
      );
}

Future<FakeValuationRepository> _pump(
  WidgetTester tester, {
  List<String>? permissions,
  Size size = const Size(1400, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final valuation = FakeValuationRepository(ValuationReport.fromJson(_json));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(permissions ?? defaultPermissionsFor('Owner'))),
        ...fakeDataOverrides(
          valuation: valuation,
          warehouses: FakeWarehousesRepository([
            Warehouse(id: 'w1', name: 'Lagos', isActive: true, createdAt: DateTime(2026, 9, 1)),
            Warehouse(id: 'w2', name: 'Kano', isActive: true, createdAt: DateTime(2026, 9, 1)),
          ]),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ReportsScreen()),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('Valuation'));
  await _settle(tester);
  return valuation;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  test('parses totals, rows, groups, flags and warnings', () {
    final r = ValuationReport.fromJson(_json);
    expect(r.totals.valueAtCost, 1042000);
    expect(r.totals.marginPercent, 7.71);
    expect(r.byProduct, hasLength(3));
    expect(r.byProduct[1].flags, {ValuationFlag.negativeStock});
    expect(r.byProduct[2].flags, {ValuationFlag.noCost}, reason: 'unknown flags are ignored');
    expect(r.byProduct[2].category, isNull);
    expect(r.byCategory.last.label, 'Uncategorised');
    expect(r.byCategory.last.totals.marginPercent, isNull);
    expect(r.byWarehouse.last.label, 'Kano (disabled)');
    expect(r.negativeStockCount, 1);
    expect(r.noCostCount, 1);
  });

  testWidgets('the Valuation tab shows totals, warnings and every product', (tester) async {
    await _pump(tester);
    expect(find.text('₦1,042,000'), findsWidgets);
    expect(find.text('₦1,129,000'), findsWidgets);
    expect(find.text('₦87,000'), findsWidgets);
    expect(find.text('7.7% of selling value'), findsOneWidget);
    expect(find.byKey(const Key('valuation-warnings')), findsOneWidget);
    expect(find.text('Rice 50kg · RICE-50'), findsOneWidget);
    expect(find.text('Below zero'), findsOneWidget);
    expect(find.text('No cost'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grouping by category and by warehouse', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('By category'));
    await _settle(tester);
    expect(find.text('Grains'), findsOneWidget);
    expect(find.text('Uncategorised'), findsWidgets);
    expect(find.text('₦822,000'), findsOneWidget);

    await tester.tap(find.text('By warehouse'));
    await _settle(tester);
    expect(find.text('Kano (disabled)'), findsOneWidget);
    expect(find.text('₦312,000'), findsOneWidget);
  });

  testWidgets('filters are sent to the server', (tester) async {
    final valuation = await _pump(tester);
    expect(valuation.requested.last, (warehouseId: null, category: null));

    await tester.tap(find.byKey(const Key('valuation-warehouse')));
    await _settle(tester);
    await tester.tap(find.text('Kano').last);
    await _settle(tester);
    expect(valuation.requested.last, (warehouseId: 'w2', category: null));

    await tester.tap(find.byKey(const Key('valuation-category')));
    await _settle(tester);
    await tester.tap(find.text('Uncategorised').last);
    await _settle(tester);
    expect(valuation.requested.last, (warehouseId: 'w2', category: ''));
  });

  testWidgets('search narrows the products and the total follows', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).last, 'beans');
    await _settle(tester);
    expect(find.text('Rice 50kg · RICE-50'), findsNothing);
    expect(find.text('Beans · BEANS'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.descendant(of: find.byType(DataTable), matching: find.text('₦90,000')), findsNWidgets(2),
        reason: 'the row and the total');
  });

  testWidgets('without stock.view the tab explains instead of loading', (tester) async {
    final valuation = await _pump(tester, permissions: const ['products.view']);
    expect(find.textContaining('needs to see both products and stock'), findsOneWidget);
    expect(valuation.requested, isEmpty);
  });

  testWidgets('lays out without overflow in a small window', (tester) async {
    await _pump(tester, size: const Size(1024, 760));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('By warehouse'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
