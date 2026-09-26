// The API applies a stock movement as a signed delta (stock = stock +
// quantity), so the app has to do the translation people shouldn't think
// about: "stock out 3" goes out as -3, a count goes out as the difference.
// Getting this wrong silently corrupts stock, so it is tested at both the
// pure-function level and through the real dialog.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/inventory/presentation/stock_movement_dialog.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';

class _RoleAuth extends AuthController {
  _RoleAuth(this.permissions);

  final List<String> permissions;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: const Organization(
          id: 'o1',
          name: 'Obi Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
        ),
        role: 'Owner',
        permissions: permissions,
      );
}

Future<FakeInventoryRepository> _openDialog(
  WidgetTester tester, {
  required List<String> permissions,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final inventory = FakeInventoryRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _RoleAuth(permissions)),
        ...fakeDataOverrides(
          products: FakeProductsRepository([fixtureProduct('1', name: 'Rice', stock: 10)]),
          inventory: inventory,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const StockMovementDialog(initialProductId: '1'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Resolve the session first, as the real app does long before any dialog
  // opens, then let the fake repositories load.
  final container = ProviderScope.containerOf(tester.element(find.text('open')));
  container.read(authControllerProvider);
  await tester.pump();
  container.read(productsProvider);
  container.read(warehousesProvider);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return inventory;
}

Future<void> _enterQuantityAndSave(WidgetTester tester, String quantity) async {
  await tester.enterText(find.byType(TextFormField).first, quantity);
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('signedMovementDelta', () {
    test('stock in adds', () {
      expect(signedMovementDelta(type: StockMovementType.stockIn, entered: 30, currentStock: 5), 30);
    });

    test('stock out is sent as a negative number', () {
      expect(signedMovementDelta(type: StockMovementType.stockOut, entered: 30, currentStock: 50), -30);
    });

    test('an adjustment goes up or down as chosen', () {
      expect(signedMovementDelta(type: StockMovementType.adjustment, entered: 4, currentStock: 9), 4);
      expect(
        signedMovementDelta(
          type: StockMovementType.adjustment,
          entered: 4,
          currentStock: 9,
          adjustDown: true,
        ),
        -4,
      );
    });

    test('a count is the difference between counted and system stock', () {
      expect(signedMovementDelta(type: StockMovementType.count, entered: 8, currentStock: 10), -2);
      expect(signedMovementDelta(type: StockMovementType.count, entered: 14, currentStock: 10), 4);
      expect(signedMovementDelta(type: StockMovementType.count, entered: 10, currentStock: 10), 0);
    });
  });

  group('Record movement dialog', () {
    testWidgets('stock in records the positive quantity', (tester) async {
      final inventory = await _openDialog(tester, permissions: ['stock.out', 'stock.adjust']);

      await _enterQuantityAndSave(tester, '5');

      expect(inventory.lastRecorded?.type, StockMovementType.stockIn);
      expect(inventory.lastRecorded?.quantity, 5);
      expect(inventory.lastRecorded?.productId, '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sales Staff record stock out as a negative quantity', (tester) async {
      final inventory = await _openDialog(tester, permissions: ['stock.out']);

      await _enterQuantityAndSave(tester, '3');

      expect(inventory.lastRecorded?.type, StockMovementType.stockOut);
      expect(inventory.lastRecorded?.quantity, -3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stock out above what is on hand is refused before sending', (tester) async {
      final inventory = await _openDialog(tester, permissions: ['stock.out']);

      await _enterQuantityAndSave(tester, '99');

      expect(find.text('Only 10 in stock'), findsOneWidget);
      expect(inventory.lastRecorded, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a role with no stock permissions cannot save', (tester) async {
      await _openDialog(tester, permissions: const []);

      expect(find.textContaining("isn't allowed to record"), findsOneWidget);
      final save = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save'));
      expect(save.onPressed, isNull);
    });
  });
}
