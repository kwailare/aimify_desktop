// Covers the new sidebar show/hide toggle: the menu button should close
// the sidebar (docked on a wide window, overlay drawer on a narrow one)
// and the floating menu FAB should reopen it.
//
// Asserts against `sidebarOpenProvider` directly rather than widget
// presence/absence — both the sidebar and the reopen FAB are always
// present in the tree with an animated opacity/position (so their
// transitions have a "from" value), so `find.byIcon`/`find.text` would
// find them either way regardless of visibility.
//
// Each tap is followed by a zero-duration `pump()` before the
// duration-pump that advances the animation. Skipping that first pump is
// a classic false-negative here: `AnimatedPositioned`/`AnimatedOpacity`
// only start animating once `didUpdateWidget` runs on a rebuild, and
// folding that rebuild into the same call that also advances the clock
// left the render tree's actual hit-test geometry unreliably behind the
// widget's target value in practice, even though the target value itself
// (and the Riverpod state driving it) already looked correct.

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:aimify_desktop/shared/widgets/sidebar/sidebar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';
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
        // Full Owner permission set (see docs/desktop-api.md) — this test
        // exercises the sidebar toggle, not permission gating itself.
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

Future<ProviderContainer> _pumpAuthenticatedApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
      authControllerProvider.overrideWith(_FakeAuthController.new),
      ...fakeDataOverrides(),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AimifyApp()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return container;
}

/// Taps [finder], then pumps once immediately (so the resulting rebuild
/// actually starts any implicit animation) before pumping past [settle].
Future<void> _tapAndSettle(WidgetTester tester, Finder finder, {bool warnIfMissed = true}) async {
  await tester.tap(finder, warnIfMissed: warnIfMissed);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('Wide window: menu button closes the docked sidebar, FAB reopens it', (tester) async {
    final container = await _pumpAuthenticatedApp(tester, const Size(1280, 800));

    expect(container.read(sidebarOpenProvider), isTrue);

    await _tapAndSettle(tester, find.byTooltip('Hide sidebar'));
    expect(container.read(sidebarOpenProvider), isFalse);

    await _tapAndSettle(tester, find.byIcon(Icons.menu_rounded));
    expect(container.read(sidebarOpenProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Narrow window: menu button closes the overlay sidebar, FAB reopens it', (tester) async {
    final container = await _pumpAuthenticatedApp(tester, const Size(500, 800));

    expect(container.read(sidebarOpenProvider), isTrue);

    await _tapAndSettle(tester, find.byTooltip('Hide sidebar'));
    expect(container.read(sidebarOpenProvider), isFalse);

    await _tapAndSettle(tester, find.byIcon(Icons.menu_rounded));
    expect(container.read(sidebarOpenProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selecting a nav item auto-closes the narrow overlay sidebar', (tester) async {
    final container = await _pumpAuthenticatedApp(tester, const Size(500, 800));

    expect(container.read(sidebarOpenProvider), isTrue);

    await _tapAndSettle(tester, find.text('Products'));

    expect(container.read(sidebarOpenProvider), isFalse);
    expect(tester.takeException(), isNull);
  });
}
