// Regression test for a real, user-reported crash: deleting a warehouse
// that was currently selected in a `WarehouseSelector` crashed the app to
// a blank screen. Root cause: `StatefulShellRoute.indexedStack` never
// disposes a branch once visited (it just hides it), so the Products
// screen's `WarehouseSelector` was still mounted and still watching
// `selectedWarehouseIdProvider`. The instant the warehouse it was showing
// got removed from the list, its `DropdownButton.value` no longer matched
// any `item`, which is a hard assertion failure in Flutter — not a
// catchable, recoverable error.
//
// Fixed in `WarehousesNotifier.removeWarehouse` (resets the selection if
// it pointed at the removed warehouse) and defensively in
// `WarehouseSelector` itself (falls back to "All warehouses" if the
// current selection isn't in the list). This test exercises the real
// repro path: pick a warehouse in one tab, delete it from another.

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
import 'package:aimify_desktop/features/warehouses/domain/warehouse.dart';
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
  testWidgets('Deleting the currently-selected warehouse does not crash', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        authControllerProvider.overrideWith(_FakeAuthController.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AimifyApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Add a warehouse with nothing attached to it — freely removable.
    container.read(warehousesProvider.notifier).addWarehouse(
          const Warehouse(id: 'w-empty', name: 'Empty Test Warehouse', location: 'Nowhere'),
        );

    // Visit Products so its WarehouseSelector mounts and stays mounted
    // (StatefulShellRoute.indexedStack keeps branches alive once visited).
    await tester.tap(find.text('Products'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Select the soon-to-be-deleted warehouse in that still-mounted screen.
    container.read(selectedWarehouseIdProvider.notifier).state = 'w-empty';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Now delete it from the Warehouses screen.
    await tester.tap(find.text('Warehouses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // "Nothing linked to it" confirmation — proceed with removal.
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(container.read(selectedWarehouseIdProvider), isNull);

    // The still-mounted Products screen shouldn't have crashed either.
    await tester.tap(find.text('Products'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
