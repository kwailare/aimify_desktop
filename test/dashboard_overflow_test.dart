// Regression test for a real bug: the dashboard's stat-card grid used a
// fixed `childAspectRatio`, which squeezed tile height short enough to
// clip StatCard's text at ordinary window widths. Fixed by switching to a
// fixed-height grid delegate (see dashboard_screen.dart) — this test fails
// loudly if that regresses, across a range of widths.
//
// Relies on flutter_test's own default error handling (which already fails
// a test on any FlutterError raised during the test body, overflow
// exceptions included) rather than manually swapping `FlutterError.onError`
// — doing that ourselves left the test binding's error state corrupted
// between the parameterized cases and hung the whole run.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/dashboard/presentation/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';

class _FakeAuthController extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main warehouse — Lagos',
          subscriptionStatus: 'trial',
          trialEndsAt: null,
        ),
        role: 'Owner',
        // Full Owner permission set (see docs/desktop-api.md) — this test
        // exercises dashboard layout, not permission gating itself.
        permissions: [
          'products.write',
          'products.archive',
          'catalog.write',
          'warehouses.manage',
          'stock.out',
          'stock.adjust',
        ],
      );
}

void main() {
  for (final width in [360.0, 600.0, 900.0, 1280.0]) {
    testWidgets('Dashboard has no overflow at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            ...fakeDataOverrides(),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const DashboardScreen(),
          ),
        ),
      );

      // The redesigned dashboard has several finite entrance animations
      // (counters, staggered rows); pump well past the longest of them
      // (~1.1s) so none are left mid-flight when the test ends.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      expect(tester.takeException(), isNull);
    });
  }
}
