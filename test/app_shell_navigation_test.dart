// Regression test for a real, user-reported crash: clicking a sidebar nav
// item froze/crashed the app. Root cause was `AppShell` wrapping
// `navigationShell` in an `AnimatedSwitcher` keyed on the branch index —
// during the crossfade, both the outgoing and incoming subtrees were
// mounted at once, and both are backed by the same go_router-owned
// GlobalKeys (one per branch Navigator), which Flutter treats as a
// duplicate-GlobalKey error. Fixed by fading the shell in place instead of
// re-keying it (see `_BranchFadeIn` in `app_shell.dart`).
//
// This test drives real sidebar taps through the real router/app shell —
// the exact path a dashboard-only test doesn't cover — so a regression
// here fails loudly instead of only showing up by clicking around the
// running app. Covers every current nav item, including the multi-
// warehouse-era additions (Warehouses, Staff, Reports).

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_token_storage.dart';

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
      );
}

void main() {
  testWidgets('Clicking sidebar nav items does not crash the app', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authControllerProvider.overrideWith(_FakeAuthController.new),
        ],
        child: const AimifyApp(),
      ),
    );

    // Let splash resolve and the redirect land on the dashboard.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    for (final label in [
      'Products',
      'Inventory',
      'Purchases',
      'Suppliers',
      'Customers',
      'Expenses',
      'Credits & Debts',
      'Warehouses',
      'Staff',
      'Reports',
      'Dashboard',
    ]) {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'after tapping "$label"');
    }
  });
}
