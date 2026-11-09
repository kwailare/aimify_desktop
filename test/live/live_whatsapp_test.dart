// LIVE check of WhatsApp against a running aimify-web (`npm run dev` on
// http://localhost:3000): the "WhatsApp OK" tick saved and read back for a
// customer and a supplier through the same repository the screens use. The
// harness then makes a sale to that customer and checks the server recorded
// the invoice (the local server runs WhatsApp in "record only" mode).
//
// Skipped unless AIMIFY_LIVE=1. Use a throwaway organization with an Owner:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_whatsapp_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/whatsapp/whatsapp_share.dart';
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
    'the WhatsApp OK tick against the real backend',
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
      final repo = c.read(partiesRepositoryProvider);

      final ada = await repo.create(
        const PartyInput(type: PartyType.customer, name: 'Ada Stores', phone: '0803 111 2222', whatsappOptIn: true, paymentTermsDays: 0),
      );
      expect(ada.whatsappOptIn, isTrue);
      final listed = (await repo.listFresh(PartyType.customer)).firstWhere((p) => p.id == ada.id);
      expect(listed.whatsappOptIn, isTrue);
      expect(toWhatsAppNumber(listed.phone), '2348031112222');

      final supplier = await repo.create(const PartyInput(type: PartyType.supplier, name: 'Dangote', phone: '+234 801 555 0000'));
      expect(supplier.whatsappOptIn, isFalse);
      final ticked = await repo.update(
        supplier.id,
        const PartyInput(type: PartyType.supplier, name: 'Dangote', phone: '+234 801 555 0000', whatsappOptIn: true),
      );
      expect(ticked.whatsappOptIn, isTrue);
      // The harness reads this to make a sale to Ada.
      stdout.writeln('LIVE ada=${ada.id}');
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
