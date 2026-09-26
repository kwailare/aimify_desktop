// Regression coverage for two of the behaviors added against the updated
// docs/desktop-api.md: permission-driven UI (item 3) and subscription
// gating (item 4). Each other test file's `_FakeAuthController` grants the
// full Owner permission set specifically so *these* are the only tests
// that exercise what happens when a role doesn't have every permission, or
// when the organization's subscription is locked.

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/domain/allowed_movement_types.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';
import 'fakes/fake_token_storage.dart';

const _orgBase = Organization(
  id: 'o1',
  name: 'Obi Distribution Ltd',
  industry: 'Wholesale',
  currency: 'NGN',
  warehouseName: 'Main warehouse — Lagos',
  subscriptionStatus: 'trial',
  trialEndsAt: null,
);

class _SalesStaffAuthController extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Chidi Sales', email: 'chidi@company.com'),
        organization: _orgBase,
        role: 'Sales Staff',
        // Per docs/desktop-api.md, Sales Staff holds only `stock.out`.
        permissions: ['stock.out'],
      );
}

class _AccountantAuthController extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Bola Finance', email: 'bola@company.com'),
        organization: _orgBase,
        role: 'Accountant / Finance',
        // Read-only — no permission keys at all.
        permissions: [],
      );
}

class _ExpiredOrgAuthController extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main warehouse — Lagos',
          subscriptionStatus: 'expired',
          trialEndsAt: null,
        ),
        role: 'Owner',
        permissions: ['products.write'],
      );
}

class _PastDueOrgAuthController extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main warehouse — Lagos',
          subscriptionStatus: 'past_due',
          trialEndsAt: null,
        ),
        role: 'Owner',
        permissions: ['products.write'],
      );
}

Future<void> _pumpApp(WidgetTester tester, AuthController Function() controllerFactory) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        authControllerProvider.overrideWith(controllerFactory),
        ...fakeDataOverrides(),
      ],
      child: const AimifyApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('Permission-driven UI', () {
    testWidgets('Accountant/Finance (no permissions) sees "Add product" disabled', (tester) async {
      await _pumpApp(tester, _AccountantAuthController.new);

      await tester.tap(find.text('Products'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final addButton = tester.widget<ElevatedButton>(
        find.ancestor(of: find.text('Add product'), matching: find.byType(ElevatedButton)),
      );
      expect(addButton.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Sales Staff (stock.out only) opens the movement dialog pre-selected to "Stock out"',
        (tester) async {
      await _pumpApp(tester, _SalesStaffAuthController.new);

      await tester.tap(find.text('Inventory'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Record movement'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Scope to the dialog itself: the Inventory screen's own filter chips
      // (also labelled "Stock out"/"Stock in") stay mounted behind the open
      // dialog, so an unscoped `find.text` would be ambiguous. The dropdown
      // is closed here, so only its current selection — not the full item
      // list — is in the tree, letting us assert the type without needing
      // to open it.
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Stock out')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Stock in')), findsNothing);
      expect(find.descendant(of: dialog, matching: find.text('Adjustment')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('allowedMovementTypes (pure function backing the dialog above)', () {
    test('Sales Staff (stock.out only) is offered only Stock out', () {
      expect(allowedMovementTypes(['stock.out']), [StockMovementType.stockOut]);
    });

    test('stock.adjust unlocks Stock in, Adjustment and Stock count but not Stock out', () {
      expect(
        allowedMovementTypes(['stock.adjust']),
        [StockMovementType.stockIn, StockMovementType.adjustment, StockMovementType.count],
      );
    });

    test('both permissions unlock all three, in menu order', () {
      expect(
        allowedMovementTypes(['stock.out', 'stock.adjust']),
        [
          StockMovementType.stockIn,
          StockMovementType.stockOut,
          StockMovementType.adjustment,
          StockMovementType.count,
        ],
      );
    });

    test('no relevant permissions unlocks nothing (e.g. Accountant / Finance)', () {
      expect(allowedMovementTypes(['products.write']), isEmpty);
      expect(allowedMovementTypes(const []), isEmpty);
    });
  });

  group('Subscription gating', () {
    testWidgets('expired subscription locks the app and shows the billing screen',
        (tester) async {
      await _pumpApp(tester, _ExpiredOrgAuthController.new);

      expect(find.text('Open billing page'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('past_due subscription does NOT lock the app', (tester) async {
      await _pumpApp(tester, _PastDueOrgAuthController.new);

      expect(find.text('Open billing page'), findsNothing);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.textContaining('Past due'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
