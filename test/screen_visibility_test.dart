// Which sections of the app are visible at all. Screens backed by the API
// follow the person's `*.view` permissions from `/me` (the Owner's Roles &
// permissions grid on the website); Purchases, Expenses and Reports, which
// have no server permissions yet, keep their fixed role rules. Covers the
// pure rule, the sidebar (fewer tiles, and the highlight still lands on the
// right one), and the router (a hidden screen can't be reached by a stale
// link, a role change, or the Owner removing a view while it's open).

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/domain/screen_visibility.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';
import 'fakes/fake_token_storage.dart';

const _orgBase = Organization(
  id: 'o1',
  name: 'Obi Distribution Ltd',
  industry: 'Wholesale',
  currency: 'NGN',
  warehouseName: 'Main warehouse — Lagos',
  subscriptionStatus: 'trial',
  setupCompletedAt: null,
);

class _RoleAuth extends AuthController {
  _RoleAuth(this.role, [List<String>? permissions])
      : permissions = permissions ?? defaultPermissionsFor(role);

  String role;
  List<String> permissions;

  @override
  Future<MeResponse?> build() async => _me();

  MeResponse _me() => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: _orgBase,
        role: role,
        permissions: permissions.where((p) => p != 'setup.complete').toList(),
      );

  /// Sets the state directly, the way a real `/me` refresh publishes a
  /// changed role or grid without recreating the notifier.
  void changeTo(String newRole, [List<String>? newPermissions]) {
    role = newRole;
    permissions = newPermissions ?? defaultPermissionsFor(newRole);
    state = AsyncData(_me());
  }
}

List<AppScreen> _visible(String role, [List<String>? permissions]) =>
    visibleScreensFor(role, permissions ?? defaultPermissionsFor(role));

void main() {
  group('isScreenVisible (pure rule)', () {
    test('Owner and Administrator see everything', () {
      for (final role in ['Owner', 'Administrator']) {
        expect(_visible(role), AppScreen.values, reason: role);
      }
    });

    test('Warehouse Manager by default: stock and supplier side, not customers or expenses', () {
      final visible = _visible('Warehouse Manager');
      expect(visible, containsAll([AppScreen.products, AppScreen.inventory, AppScreen.warehouses,
          AppScreen.purchases, AppScreen.suppliers, AppScreen.creditsDebts, AppScreen.reports]));
      expect(visible, isNot(anyOf(contains(AppScreen.customers), contains(AppScreen.expenses))));
    });

    test('Inventory Staff by default: the stock side, warehouses read-only', () {
      expect(
        _visible('Inventory Staff'),
        [AppScreen.dashboard, AppScreen.products, AppScreen.inventory, AppScreen.warehouses, AppScreen.reports],
      );
    });

    test('Sales Staff by default: stock, warehouses (read-only) and the customer side', () {
      final visible = _visible('Sales Staff');
      expect(visible, containsAll([AppScreen.products, AppScreen.inventory, AppScreen.warehouses,
          AppScreen.customers, AppScreen.creditsDebts]));
      expect(
        visible,
        isNot(anyOf(contains(AppScreen.suppliers), contains(AppScreen.purchases),
            contains(AppScreen.expenses), contains(AppScreen.reports))),
      );
    });

    test('Accountant / Finance by default: money screens plus read-only stock', () {
      expect(_visible('Accountant / Finance'), AppScreen.values);
    });

    test('a module the Owner hides from a role disappears from its screens', () {
      final sales = defaultPermissionsFor('Sales Staff')
          .where((p) => !p.startsWith('warehouses.') && !p.startsWith('customers.'))
          .toList();
      final visible = _visible('Sales Staff', sales);
      expect(visible, isNot(anyOf(contains(AppScreen.warehouses), contains(AppScreen.customers),
          contains(AppScreen.creditsDebts))));
      expect(visible, contains(AppScreen.products));
    });

    test('a module the Owner grants appears, even for a role that never had it', () {
      final sales = [...defaultPermissionsFor('Sales Staff'), 'suppliers.view'];
      expect(_visible('Sales Staff', sales), contains(AppScreen.suppliers));
    });

    test('Credits & Debts shows when either side is visible', () {
      expect(isScreenVisible('Warehouse Manager', ['suppliers.view'], AppScreen.creditsDebts), isTrue);
      expect(isScreenVisible('Sales Staff', ['customers.view'], AppScreen.creditsDebts), isTrue);
      expect(isScreenVisible('Sales Staff', ['products.view'], AppScreen.creditsDebts), isFalse);
    });

    test('local-only screens (Expenses, Reports) keep their role rules regardless of the grid', () {
      expect(isScreenVisible('Sales Staff', defaultPermissionsFor('Owner'), AppScreen.expenses), isFalse);
      expect(isScreenVisible('Accountant / Finance', const [], AppScreen.expenses), isTrue);
    });

    test('Purchases follows purchases.view, like the other server-backed screens', () {
      expect(isScreenVisible('Sales Staff', const ['purchases.view'], AppScreen.purchases), isTrue);
      expect(isScreenVisible('Owner', const ['products.view'], AppScreen.purchases), isFalse);
      expect(_visible('Sales Staff', defaultPermissionsFor('Sales Staff')), isNot(contains(AppScreen.purchases)));
      expect(_visible('Accountant / Finance', defaultPermissionsFor('Accountant / Finance')), contains(AppScreen.purchases));
    });

    test('dashboard is always visible; nothing else without permissions', () {
      expect(_visible('Sales Staff', const []), [AppScreen.dashboard]);
      expect(visibleScreensFor(null, const []), [AppScreen.dashboard]);
      expect(visibleScreensFor('Made-up Role', const []), [AppScreen.dashboard]);
    });

    test('screenForPath round-trips every screenPaths entry', () {
      for (final entry in screenPaths.entries) {
        expect(screenForPath(entry.value), entry.key);
      }
      expect(screenForPath('/no-such-route'), isNull);
    });
  });

  Future<ProviderContainer> pump(WidgetTester tester, _RoleAuth auth) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        authControllerProvider.overrideWith(() => auth),
        ...fakeDataOverrides(),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AimifyApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  group('the sidebar', () {
    testWidgets('Inventory Staff sees their screens by default', (tester) async {
      await pump(tester, _RoleAuth('Inventory Staff'));

      for (final label in ['Dashboard', 'Products', 'Inventory', 'Warehouses', 'Reports']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['Purchases', 'Suppliers', 'Customers', 'Expenses', 'Credits & Debts']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a customised grid shapes the sidebar', (tester) async {
      await pump(
        tester,
        _RoleAuth('Sales Staff', asGranted(['customers.read']).where((p) => p != 'warehouses.view').toList()),
      );

      for (final label in ['Dashboard', 'Products', 'Inventory', 'Customers', 'Credits & Debts']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in ['Warehouses', 'Suppliers', 'Purchases', 'Expenses', 'Reports']) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('tapping a visible item still navigates and highlights correctly', (tester) async {
      await pump(tester, _RoleAuth('Sales Staff'));

      await tester.tap(find.text('Customers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add customer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a role change mid-session drops now-hidden tiles without crashing', (tester) async {
      final container = await pump(tester, _RoleAuth('Warehouse Manager'));
      expect(find.text('Suppliers'), findsOneWidget);
      expect(find.text('Customers'), findsNothing);

      (container.read(authControllerProvider.notifier) as _RoleAuth).changeTo('Sales Staff');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Suppliers'), findsNothing);
      expect(find.text('Customers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the router', () {
    testWidgets('a role change while on a screen it can no longer see redirects to the dashboard',
        (tester) async {
      final container = await pump(tester, _RoleAuth('Warehouse Manager'));
      await tester.tap(find.text('Suppliers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add supplier'), findsOneWidget);

      (container.read(authControllerProvider.notifier) as _RoleAuth).changeTo('Sales Staff');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Add supplier'), findsNothing);
      expect(find.text('Add customer'), findsNothing); // landed on the dashboard, not Customers
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Owner removing a view while it is open sends the person to the dashboard',
        (tester) async {
      final container = await pump(tester, _RoleAuth('Warehouse Manager'));
      await tester.tap(find.text('Warehouses'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add warehouse'), findsOneWidget);

      final withoutWarehouses = defaultPermissionsFor('Warehouse Manager')
          .where((p) => !p.startsWith('warehouses.') && !p.startsWith('stock.'))
          .toList();
      (container.read(authControllerProvider.notifier) as _RoleAuth)
          .changeTo('Warehouse Manager', withoutWarehouses);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Add warehouse'), findsNothing);
      expect(find.text('Warehouses'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
