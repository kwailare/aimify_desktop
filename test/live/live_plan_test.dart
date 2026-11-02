// LIVE check of the plan details on /me against a running aimify-web
// (`npm run dev` on http://localhost:3000): the plan's price and a cheaper
// plan scheduled for the end of the paid period, as the dashboard shows
// them. Plans are changed on the website; this only reads them.
//
// Skipped unless AIMIFY_LIVE=1. Use a throwaway organization on the
// default plan with a plan change scheduled:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//   AIMIFY_PLAN_NAME=...        the plan it is on (and the one scheduled)
//   AIMIFY_PLAN_PRICE=...       its monthly price
//   AIMIFY_SCHEDULED_AT=...     when the change starts (ISO)
//
//   flutter test test/live/live_plan_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_token_storage.dart';

final _env = Platform.environment;
final _live = _env['AIMIFY_LIVE'] == '1';
String _need(String name) => _env[name] ?? (throw StateError('Set $name'));

void main() {
  test(
    'the plan and a scheduled change from the real backend',
    () async {
      final c = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      await c
          .read(authControllerProvider.notifier)
          .login(email: _need('AIMIFY_OWNER_EMAIL'), password: _need('AIMIFY_PASSWORD'));

      final plan = c.read(authControllerProvider).value!.plan!;
      expect(plan.name, _need('AIMIFY_PLAN_NAME'));
      expect(plan.priceMonthly, double.parse(_need('AIMIFY_PLAN_PRICE')));
      expect(plan.scheduled, isNotNull);
      expect(plan.scheduled!.name, _need('AIMIFY_PLAN_NAME'));
      expect(plan.scheduled!.at, DateTime.parse(_need('AIMIFY_SCHEDULED_AT')).toLocal());
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
