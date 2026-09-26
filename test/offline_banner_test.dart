// While the last request found no connection, every screen shows an offline
// banner with a retry, and it goes away once a request succeeds again.

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/shared/services/authed_api.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';
import 'fakes/fake_token_storage.dart';

class _OwnerAuth extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
        ),
        role: 'Owner',
        permissions: ['products.write'],
      );
}

void main() {
  testWidgets('offline banner appears with a retry, and clears when back online', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        authControllerProvider.overrideWith(_OwnerAuth.new),
        ...fakeDataOverrides(),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AimifyApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining("You're offline"), findsNothing);

    container.read(offlineProvider.notifier).state = true;
    await tester.pump();
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Retry re-reads everything without crashing.
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    container.read(offlineProvider.notifier).state = false;
    await tester.pump();
    expect(find.textContaining("You're offline"), findsNothing);
  });
}
