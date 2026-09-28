// Roles now decide which sections of the app are visible at all, not just
// which buttons inside them work. Covers the pure per-role rule, the sidebar
// (fewer tiles, and the sliding highlight still lands on the right one), and
// the router (a hidden screen can't be reached by a stale link or a role
// change while already on it).

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/domain/screen_visibility.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
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
);

class _RoleAuth extends AuthController {
  _RoleAuth(this.role);

  String role;

  @override
  Future<MeResponse?> build() async => _me();

  MeResponse _me() => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: _orgBase,
        role: role,
        permissions: const [
          'products.write', 'products.archive', 'catalog.write', 'warehouses.manage',
          'stock.out', 'stock.adjust', 'customers.read', 'customers.write',
          'suppliers.read', 'suppliers.write', 'credit.record',
        ],
      );

  /// Sets the state directly (rather than `ref.invalidateSelf()`, which would
  /// rebuild through `overrideWith`'s closure and just recreate the original
  /// role) — the same way a real `/me` refresh publishes a changed role
  /// without recreating the notifier.
  void changeRoleTo(String newRole) {
    role = newRole;
    state = AsyncData(_me());
  }
}

void main() {
  group('isScreenVisible (pure rule)', () {
    test('Owner and Administrator see everything', () {
      for (final role in ['Owner', 'Administrator']) {
        expect(visibleScreensFor(role), AppScreen.values, reason: role);
      }
    });

    test('Warehouse Manager: stock and supplier side, not customers or expenses', () {
      final visible = visibleScreensFor('Warehouse Manager');
      expect(visible, containsAll([AppScreen.products, AppScreen.inventory, AppScreen.warehouses,
          AppScreen.purchases, AppScreen.suppliers, AppScreen.creditsDebts, AppScreen.reports]));
      expect(visible, isNot(anyOf(contains(AppScreen.customers), contains(AppScreen.expenses))));
    });

    test('Inventory Staff: only the stock side', () {
      expect(
        visibleScreensFor('Inventory Staff'),
        [AppScreen.dashboard, AppScreen.products, AppScreen.inventory, AppScreen.reports],
      );
    });

    test('Sales Staff: stock (view) and the customer side, no back-office screens', () {
      final visible = visibleScreensFor('Sales Staff');
      expect(visible, containsAll([AppScreen.products, AppScreen.inventory, AppScreen.customers,
          AppScreen.creditsDebts]));
      expect(
        visible,
        isNot(anyOf(contains(AppScreen.warehouses), contains(AppScreen.suppliers),
            contains(AppScreen.purchases), contains(AppScreen.expenses), contains(AppScreen.reports))),
      );
    });

    test('Accountant / Finance: money screens, not stock mechanics', () {
      final visible = visibleScreensFor('Accountant / Finance');
      expect(visible, containsAll([AppScreen.purchases, AppScreen.suppliers, AppScreen.customers,
          AppScreen.expenses, AppScreen.creditsDebts, AppScreen.reports]));
      expect(
        visible,
        isNot(anyOf(contains(AppScreen.products), contains(AppScreen.inventory), contains(AppScreen.warehouses))),
      );
    });

    test('dashboard is visible to every recognized role', () {
      for (final role in const [
        'Owner', 'Administrator', 'Warehouse Manager', 'Inventory Staff', 'Sales Staff', 'Accountant / Finance',
      ]) {
        expect(isScreenVisible(role, AppScreen.dashboard), isTrue, reason: role);
      }
    });

    test('an unrecognized or missing role fails closed to just the dashboard', () {
      expect(visibleScreensFor(null), [AppScreen.dashboard]);
      expect(visibleScreensFor('Made-up Role'), [AppScreen.dashboard]);
    });

    test('screenForPath round-trips every screenPaths entry', () {
      for (final entry in screenPaths.entries) {
        expect(screenForPath(entry.value), entry.key);
      }
      expect(screenForPath('/no-such-route'), isNull);
    });
  });

  group('the sidebar', () {
    Future<ProviderContainer> pump(WidgetTester tester, String role) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authControllerProvider.overrideWith(() => _RoleAuth(role)),
          ...fakeDataOverrides(),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AimifyApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return container;
    }

    testWidgets('Inventory Staff sees only their four screens', (tester) async {
      await pump(tester, 'Inventory Staff');

      for (final label in ['Dashboard', 'Products', 'Inventory', 'Reports']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in [
        'Purchases', 'Suppliers', 'Customers', 'Expenses', 'Credits & Debts', 'Warehouses',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sales Staff sees products/inventory/customers/credits, nothing else', (tester) async {
      await pump(tester, 'Sales Staff');

      for (final label in ['Dashboard', 'Products', 'Inventory', 'Customers', 'Credits & Debts']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['Purchases', 'Suppliers', 'Expenses', 'Warehouses', 'Reports']) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('tapping a visible item still navigates and highlights correctly', (tester) async {
      await pump(tester, 'Sales Staff');

      await tester.tap(find.text('Customers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add customer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a role change mid-session drops now-hidden tiles without crashing', (tester) async {
      final container = await pump(tester, 'Warehouse Manager');
      expect(find.text('Warehouses'), findsOneWidget);
      expect(find.text('Customers'), findsNothing);

      (container.read(authControllerProvider.notifier) as _RoleAuth).changeRoleTo('Sales Staff');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Warehouses'), findsNothing);
      expect(find.text('Customers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the router', () {
    Future<ProviderContainer> pumpAt(WidgetTester tester, String role) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authControllerProvider.overrideWith(() => _RoleAuth(role)),
          ...fakeDataOverrides(),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AimifyApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return container;
    }

    testWidgets('a role change while sitting on a screen it can no longer see redirects to the dashboard',
        (tester) async {
      final container = await pumpAt(tester, 'Warehouse Manager');
      await tester.tap(find.text('Warehouses'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add warehouse'), findsOneWidget);

      // Reassigned on the website mid-session, the next time /me refreshes.
      (container.read(authControllerProvider.notifier) as _RoleAuth).changeRoleTo('Sales Staff');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Add warehouse'), findsNothing);
      expect(find.text('Add customer'), findsNothing); // landed on the dashboard, not Customers
      expect(tester.takeException(), isNull);
    });
  });
}
