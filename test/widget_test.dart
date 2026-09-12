// Smoke test: the app boots, resolves the (empty, faked) stored session,
// and lands on the login screen since there's no token to restore.
//
// Uses bounded `pump()` calls rather than `pumpAndSettle()` because the
// splash screen's CircularProgressIndicator animates forever and would
// make pumpAndSettle time out waiting for the widget tree to go idle.
//
// The real `flutter_secure_storage` plugin is overridden with an in-memory
// fake here — it talks to the OS keychain, which isn't available (and can
// hang) in a headless test run.

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_token_storage.dart';

void main() {
  testWidgets('Boots to the login screen when signed out', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        ],
        child: const AimifyApp(),
      ),
    );

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Sign in to your warehouse'), findsOneWidget);
  });
}
