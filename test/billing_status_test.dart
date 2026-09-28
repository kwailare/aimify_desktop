// Section 5 of the desktop-update prompt: `organization.currentPeriodEnd` and
// `cancelAtPeriodEnd` are new on `/me`. All payment happens on the website —
// this only covers parsing the fields and showing them; it never taps a
// "Manage billing" / "Open billing page" button, since that would launch a
// real browser via a platform channel the test environment doesn't have
// (the existing locked-screen test follows the same rule).

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/dashboard/presentation/dashboard_screen.dart';
import 'package:aimify_desktop/features/products/presentation/products_screen.dart';
import 'package:aimify_desktop/features/warehouses/presentation/warehouses_screen.dart';
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
  _Auth({
    required this.status,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.role = 'Owner',
    this.plan,
  });

  final String status;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String role;
  final Plan? plan;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: status,
          currentPeriodEnd: currentPeriodEnd,
          cancelAtPeriodEnd: cancelAtPeriodEnd,
        ),
        role: role,
        permissions: _ownerPermissions,
        plan: plan,
      );
}

Future<void> _pumpDashboard(WidgetTester tester, AuthController Function() controller) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authControllerProvider.overrideWith(controller), ...fakeDataOverrides()],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

void main() {
  group('parsing', () {
    test('currentPeriodEnd and cancelAtPeriodEnd parse from /me JSON', () {
      final org = Organization.fromJson({
        'id': 'o1', 'name': 'X', 'industry': 'Y', 'currency': 'NGN',
        'subscriptionStatus': 'active',
        'currentPeriodEnd': '2026-11-05T00:00:00.000Z',
        'cancelAtPeriodEnd': true,
      });

      expect(org.currentPeriodEnd, DateTime.parse('2026-11-05T00:00:00.000Z'));
      expect(org.cancelAtPeriodEnd, isTrue);
    });

    test('both default sanely when absent (an org that has never paid)', () {
      final org = Organization.fromJson({
        'id': 'o1', 'name': 'X', 'industry': 'Y', 'currency': 'NGN',
        'subscriptionStatus': 'trial',
      });

      expect(org.currentPeriodEnd, isNull);
      expect(org.cancelAtPeriodEnd, isFalse);
    });

    test('cancelAtPeriodEnd never affects isLocked — access continues until the date passes', () {
      final org = Organization.fromJson({
        'id': 'o1', 'name': 'X', 'industry': 'Y', 'currency': 'NGN',
        'subscriptionStatus': 'active',
        'currentPeriodEnd': '2026-11-05T00:00:00.000Z',
        'cancelAtPeriodEnd': true,
      });

      expect(org.isLocked, isFalse);
    });
  });

  group('the dashboard banner', () {
    testWidgets('past_due: the exact wording plus an "Update billing" link, non-blocking', (tester) async {
      await _pumpDashboard(tester, () => _Auth(status: 'past_due'));

      expect(find.textContaining("A payment didn't go through"), findsOneWidget);
      expect(find.text('Update billing'), findsOneWidget);
      // Non-blocking: the normal dashboard is still there underneath.
      expect(find.text('Products'), findsNothing); // sidebar isn't part of DashboardScreen itself
      expect(find.text('Past due'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('active with a paid period shows when it renews', (tester) async {
      await _pumpDashboard(
        tester,
        () => _Auth(status: 'active', currentPeriodEnd: DateTime.utc(2026, 11, 5)),
      );

      expect(find.textContaining('Renews'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.textContaining("didn't go through"), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelAtPeriodEnd shows when access ends, but the org still reads Active', (tester) async {
      await _pumpDashboard(
        tester,
        () => _Auth(
          status: 'active',
          currentPeriodEnd: DateTime.utc(2026, 11, 5),
          cancelAtPeriodEnd: true,
        ),
      );

      expect(find.textContaining('Cancels'), findsOneWidget);
      expect(find.textContaining('access continues'), findsOneWidget);
      // Nothing changes because of the cancellation until the date passes.
      expect(find.text('Active'), findsOneWidget);
      expect(find.textContaining('Renews'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('past_due never shows "Renews" with the already-past period date', (tester) async {
      await _pumpDashboard(
        tester,
        () => _Auth(status: 'past_due', currentPeriodEnd: DateTime.utc(2026, 9, 1)),
      );

      expect(find.textContaining('Renews'), findsNothing);
      expect(find.textContaining("A payment didn't go through"), findsOneWidget);
    });

    testWidgets('trial with no paid period yet shows the trial countdown, not a renewal date', (tester) async {
      await _pumpDashboard(
        tester,
        () => _Auth(status: 'trial'),
      );

      expect(find.textContaining('Renews'), findsNothing);
      expect(find.textContaining('Cancels'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('plan-limit "Manage billing" link', () {
    const cappedPlan = Plan(
      name: 'Full Access',
      limits: PlanLimits(warehouses: 1, products: 5),
      usage: PlanUsage(users: 1, warehouses: 1, products: 5),
    );
    const roomyPlan = Plan(
      name: 'Full Access',
      limits: PlanLimits(warehouses: 1, products: 5),
      usage: PlanUsage(users: 1, warehouses: 0, products: 1),
    );

    Future<void> pumpScreen(WidgetTester tester, Widget screen, AuthController Function() controller) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(controller), ...fakeDataOverrides()],
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('Owner at the product cap sees "Manage billing" on Products', (tester) async {
      await pumpScreen(
        tester,
        const ProductsScreen(),
        () => _Auth(status: 'active', plan: cappedPlan),
      );

      expect(find.text('Manage billing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Owner NOT at the cap sees no billing link on Products', (tester) async {
      await pumpScreen(
        tester,
        const ProductsScreen(),
        () => _Auth(status: 'active', plan: roomyPlan),
      );

      expect(find.text('Manage billing'), findsNothing);
    });

    testWidgets('a non-Owner at the cap does not see the billing link (only the owner can act on it)',
        (tester) async {
      await pumpScreen(
        tester,
        const ProductsScreen(),
        () => _Auth(status: 'active', role: 'Administrator', plan: cappedPlan),
      );

      expect(find.text('Manage billing'), findsNothing);
    });

    testWidgets('Owner at the warehouse cap sees "Manage billing" on Warehouses', (tester) async {
      await pumpScreen(
        tester,
        const WarehousesScreen(),
        () => _Auth(status: 'active', plan: cappedPlan),
      );

      expect(find.text('Manage billing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
