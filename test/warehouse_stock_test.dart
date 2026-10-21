// Stock per warehouse (feature checklist step 5): each product has a balance
// in each warehouse and currentStock is their total. Movements, stock-out
// limits, counts, the offline overlay, the Inventory screen's warehouse
// filter and the Warehouses screen all work from the warehouse's own
// balance; a warehouse holding stock can't be disabled.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/data/outbox_overlay.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/inventory/presentation/inventory_screen.dart';
import 'package:aimify_desktop/features/inventory/presentation/stock_movement_dialog.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
import 'package:aimify_desktop/features/warehouses/domain/warehouse.dart';
import 'package:aimify_desktop/features/warehouses/presentation/warehouses_screen.dart';
import 'package:aimify_desktop/shared/offline/outbox.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/widgets/stock_level_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

class _Auth extends AuthController {
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
        permissions: defaultPermissionsFor('Owner').where((p) => p != 'setup.complete').toList(),
      );
}

/// Rice: 10 in Lagos (w1), 2 in Kano (w2) — 12 in total.
Product _rice() => fixtureProduct('1', name: 'Rice', stock: 0).withMovement('w1', 10).withMovement('w2', 2);

final _lagos = Warehouse(
  id: 'w1',
  name: 'Lagos',
  isActive: true,
  createdAt: DateTime(2026, 9, 1),
  stock: WarehouseStock(units: 10, products: 1, valueAtCost: 1000, valueAtRetail: 1500),
);
final _kano = Warehouse(
  id: 'w2',
  name: 'Kano',
  isActive: true,
  createdAt: DateTime(2026, 9, 1),
  stock: WarehouseStock(units: 2, products: 1, valueAtCost: 200, valueAtRetail: 300),
);
final _abuja = Warehouse(id: 'w3', name: 'Abuja', isActive: true, createdAt: DateTime(2026, 9, 1));

List<Override> _overrides({FakeInventoryRepository? inventory}) => [
      authControllerProvider.overrideWith(_Auth.new),
      ...fakeDataOverrides(
        products: FakeProductsRepository([_rice()]),
        warehouses: FakeWarehousesRepository([_lagos, _kano, _abuja]),
        inventory: inventory,
      ),
    ];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen, {FakeInventoryRepository? inventory}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(inventory: inventory),
      child: MaterialApp(theme: AppTheme.light(), home: screen),
    ),
  );
  await _settle(tester);
}

Future<void> _openDialog(WidgetTester tester, {String? warehouseId, FakeInventoryRepository? inventory}) async {
  await _pumpScreen(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => StockMovementDialog(initialProductId: '1', initialWarehouseId: warehouseId),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    inventory: inventory,
  );
  final container = ProviderScope.containerOf(tester.element(find.text('open')));
  container.read(productsProvider);
  container.read(warehousesProvider);
  await _settle(tester);
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Future<void> _chooseType(WidgetTester tester, String label) async {
  await tester.tap(find.text('Stock in').last);
  await _settle(tester);
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

void main() {
  group('model', () {
    test('stockByWarehouse parses from the API and stockIn reads it', () {
      final p = Product.fromJson({
        'id': 'p1', 'sku': 'A', 'name': 'Rice', 'currentStock': 12,
        'stockByWarehouse': [
          {'warehouseId': 'w1', 'quantity': 10},
          {'warehouseId': 'w2', 'quantity': 2},
        ],
      });
      expect(p.stockIn('w1'), 10);
      expect(p.stockIn('w2'), 2);
      expect(p.stockIn('w9'), 0);
      expect(Product.fromJson({'id': 'p2', 'sku': 'B', 'name': 'Beans'}).stockByWarehouse, isEmpty);
    });

    test('a movement changes that warehouse and the total together', () {
      final p = _rice().withMovement('w2', -2);
      expect(p.currentStock, 10);
      expect(p.stockIn('w1'), 10);
      expect(p.stockByWarehouse.containsKey('w2'), isFalse, reason: 'an emptied warehouse drops out');
      expect(p.withMovement('w3', 4).stockIn('w3'), 4);
    });

    test('editing a product keeps its warehouse balances', () {
      final edited = _rice().withInput(
        const ProductInput(sku: 'SKU-1', name: 'Rice 50kg', unit: 'bag', purchasePrice: 1, sellingPrice: 2, minStock: 0),
      );
      expect(edited.stockByWarehouse, {'w1': 10, 'w2': 2});
    });

    test('a warehouse parses its stock summary, empty when missing', () {
      final w = Warehouse.fromJson({
        'id': 'w1', 'name': 'Lagos', 'status': 'active',
        'stock': {'units': 340, 'products': 12, 'valueAtCost': 1520000, 'valueAtRetail': 1810000},
      });
      expect(w.stock.units, 340);
      expect(w.stock.valueAtCost, 1520000);
      expect(w.stock.isEmpty, isFalse);
      expect(Warehouse.fromJson({'id': 'w2', 'name': 'Kano'}).stock.isEmpty, isTrue);
    });

    test('a pending offline movement moves only its warehouse and shows that warehouse\'s balance', () {
      final view = overlayOutbox([_rice()], [
        OutboxOp(
          id: 'op1',
          kind: OpKind.movement,
          payload: {'productId': '1', 'warehouseId': 'w2', 'type': 'stock_out', 'quantity': -1, 'reason': null},
          createdAt: DateTime(2026, 10, 21),
        ),
      ]);
      final rice = view.products.single;
      expect(rice.stockIn('w2'), 1);
      expect(rice.stockIn('w1'), 10);
      expect(rice.currentStock, 11);
      expect(view.movements.single.previousStock, 2);
      expect(view.movements.single.newStock, 1);
    });

    test('the server\'s warehouse balance comes back on the result', () {
      final result = MovementResult.fromJson({
        'movement': {
          'id': 'm1', 'productId': '1', 'warehouseId': 'w2', 'type': 'stock_in', 'quantity': 3,
          'previousStock': 2, 'newStock': 5, 'createdAt': '2026-10-21T10:00:00.000Z',
        },
        'currentStock': 15,
        'warehouseStock': 5,
        'alert': null,
      });
      expect(result.warehouseStock, 5);
      expect(result.currentStock, 15);
    });
  });

  group('movement form', () {
    testWidgets('stock out is limited to what the chosen warehouse holds', (tester) async {
      final inventory = FakeInventoryRepository();
      await _openDialog(tester, warehouseId: 'w2', inventory: inventory);
      await _chooseType(tester, 'Stock out');
      await tester.enterText(find.byType(TextFormField).first, '5');
      await _settle(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);
      expect(find.text('Only 2 in this warehouse'), findsOneWidget);
      expect(inventory.sent, isEmpty);
    });

    testWidgets('the same stock out is fine from the warehouse that has it', (tester) async {
      final inventory = FakeInventoryRepository();
      await _openDialog(tester, warehouseId: 'w1', inventory: inventory);
      await _chooseType(tester, 'Stock out');
      await tester.enterText(find.byType(TextFormField).first, '5');
      await _settle(tester);
      expect(find.text('Stock in this warehouse will go from 10 to 5'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);
      expect(inventory.sent.single.quantity, -5);
    });

    testWidgets('a count is compared with the warehouse, not the total', (tester) async {
      final inventory = FakeInventoryRepository();
      await _openDialog(tester, warehouseId: 'w2', inventory: inventory);
      await _chooseType(tester, 'Stock count');
      await tester.enterText(find.byType(TextFormField).first, '3');
      await _settle(tester);
      expect(find.textContaining('This warehouse shows 2; counted 3'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, 'Recount');
      await _settle(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);
      expect(inventory.sent.single.quantity, 1);
    });

    testWidgets('the server refusing for lack of stock is shown in the form', (tester) async {
      final inventory = FakeInventoryRepository()
        ..recordError = ApiException(
          409,
          'Lagos has only 3 of this product, so 5 can\'t be taken out.',
          code: 'insufficient_stock',
        );
      await _openDialog(tester, warehouseId: 'w1', inventory: inventory);
      await _chooseType(tester, 'Stock out');
      await tester.enterText(find.byType(TextFormField).first, '5');
      await _settle(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);
      expect(find.textContaining('Lagos has only 3'), findsOneWidget);
    });
  });

  group('screens', () {
    testWidgets('Inventory: filtering to a warehouse shows its own stock and value', (tester) async {
      await _pumpScreen(tester, const InventoryScreen());
      final bar = find.byType(StockLevelBar);
      expect(tester.widget<StockLevelBar>(bar.first).quantity, 12, reason: 'all warehouses');

      await tester.tap(find.byKey(const Key('inventory-warehouse-filter')));
      await _settle(tester);
      await tester.tap(find.text('Kano').last);
      await _settle(tester);

      expect(tester.widget<StockLevelBar>(bar.first).quantity, 2);
      expect(find.text('On hand · Kano'), findsOneWidget);
      expect(find.text('₦200'), findsOneWidget, reason: '2 bags at ₦100 cost');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Warehouses: each card shows what it holds; only an empty one can be disabled',
        (tester) async {
      await _pumpScreen(tester, const WarehousesScreen());
      expect(find.text('10 units · 1 product · ₦1,000 at cost'), findsOneWidget);
      expect(find.text('No stock here'), findsOneWidget);

      final disables = find.widgetWithText(TextButton, 'Disable');
      final pressed = [
        for (final e in disables.evaluate()) (e.widget as TextButton).onPressed,
      ];
      expect(pressed.where((p) => p == null).length, 2, reason: 'Lagos and Kano hold stock');
      expect(pressed.where((p) => p != null).length, 1, reason: 'Abuja is empty');
    });
  });
}
