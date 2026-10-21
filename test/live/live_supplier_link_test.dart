// LIVE end-to-end check of the product ↔ supplier link against a running
// aimify-web (`npm run dev` on http://localhost:3000): an Inventory Staff
// member, who can't see supplier records, reads supplier names, links a new
// product, and the Owner sees it under the supplier's products. Same
// repositories and notifiers the screens use, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with an active supplier named
// "Dangote Foods Ltd" and an archived one named "Old Mills":
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...          shared by both accounts
//   AIMIFY_OWNER_EMAIL=...       Owner
//   AIMIFY_INVENTORY_EMAIL=...   Inventory Staff in the same org
//
//   flutter test test/live/live_supplier_link_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/data/supplier_options.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_token_storage.dart';

final _env = Platform.environment;
final _live = _env['AIMIFY_LIVE'] == '1';
String _need(String name) => _env[name] ?? (throw StateError('Set $name'));

Future<ProviderContainer> _signIn(String email) async {
  final container = ProviderContainer(
    overrides: [
      secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);
  await container.read(authControllerProvider.notifier).login(
        email: email,
        password: _need('AIMIFY_PASSWORD'),
      );
  return container;
}

ProductInput _input(String sku, String? supplierId) => ProductInput(
      sku: sku,
      name: 'Live $sku',
      unit: 'bag',
      purchasePrice: 61000,
      sellingPrice: 65000,
      minStock: 2,
      supplierId: supplierId,
    );

void main() {
  test(
    'product ↔ supplier link against the real backend',
    () async {
      final staff = await _signIn(_need('AIMIFY_INVENTORY_EMAIL'));

      // Names without supplier records.
      final options = await staff.read(supplierOptionsProvider.future);
      final dangote = matchSupplierByName(options, 'dangote foods ltd');
      expect(dangote, isNotNull);
      expect(matchSupplierByName(options, 'Old Mills'), isNull, reason: 'archived');
      final oldMills = options.firstWhere((o) => o.name == 'Old Mills');
      expect(oldMills.isArchived, isTrue);
      expect(await staff.read(partiesProvider(PartyType.supplier).future), isEmpty,
          reason: 'no suppliers.view, so supplier records are never fetched');

      // Link a new product.
      await staff.read(productsProvider.future);
      final created = await staff.read(productsProvider.notifier).add(_input('SUP-LIVE-1', dangote!.id));
      expect(created.queued, isFalse);
      final product = staff.read(productListProvider).firstWhere((p) => p.sku == 'SUP-LIVE-1');
      expect(product.supplierId, dangote.id);
      expect(staff.read(supplierOptionByIdProvider)[product.supplierId]?.name, 'Dangote Foods Ltd');

      // The server refuses a new link to an archived supplier.
      try {
        await staff.read(productsRepositoryProvider).create(_input('SUP-LIVE-2', oldMills.id));
        fail('linking to an archived supplier should be refused');
      } on ApiException catch (e) {
        expect(e.statusCode, 400);
        expect(e.code, 'invalid_supplier');
      }

      // Unlinking through an edit.
      await staff.read(productsProvider.notifier).edit(product.id, _input('SUP-LIVE-1', null));
      expect(staff.read(productListProvider).firstWhere((p) => p.id == product.id).supplierId, isNull);
      await staff.read(productsProvider.notifier).edit(product.id, _input('SUP-LIVE-1', dangote.id));

      // The Owner sees it under the supplier.
      final owner = await _signIn(_need('AIMIFY_OWNER_EMAIL'));
      final ownerProducts = await owner.read(productsProvider.future);
      expect(
        ownerProducts.where((p) => p.supplierId == dangote.id).map((p) => p.sku),
        contains('SUP-LIVE-1'),
      );
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
