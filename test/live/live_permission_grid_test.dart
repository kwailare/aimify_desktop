// LIVE end-to-end check of the Roles & permissions grid against a running
// aimify-web (`npm run dev` on http://localhost:3000): the app reads a
// customised grid from `/me`, shows the screens it allows, and the server
// enforces each action exactly. Same repositories and notifiers the screens
// use, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with one warehouse, where the Owner has
// customised Sales Staff to: products.view, products.create, stock.view,
// stock.out (so not customers, and not products.edit):
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...          shared by both accounts
//   AIMIFY_OWNER_EMAIL=...       Owner
//   AIMIFY_SALES_EMAIL=...       Sales Staff in the same org
//
//   flutter test test/live/live_permission_grid_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/domain/permissions.dart';
import 'package:aimify_desktop/features/auth/domain/screen_visibility.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/domain/allowed_movement_types.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
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

void main() {
  test(
    'a customised grid against the real backend',
    () async {
      final sales = await _signIn(_need('AIMIFY_SALES_EMAIL'));
      final me = sales.read(authControllerProvider).value!;

      expect(me.hasPermission(Permissions.productsCreate), isTrue);
      expect(me.hasPermission(Permissions.productsEdit), isFalse);
      expect(me.hasPermission(Permissions.customersView), isFalse);
      expect(me.hasPermission(Permissions.warehousesView), isTrue, reason: 'implied by stock.out');
      expect(allowedMovementTypes(me.permissions), [StockMovementType.stockOut]);

      final screens = visibleScreensFor(me.role, me.permissions);
      expect(screens, containsAll([AppScreen.products, AppScreen.inventory, AppScreen.warehouses]));
      expect(screens, isNot(anyOf(contains(AppScreen.customers), contains(AppScreen.creditsDebts))));

      // Customers aren't fetched at all.
      expect(await sales.read(partiesProvider(PartyType.customer).future), isEmpty);
      try {
        await sales.read(partiesRepositoryProvider).list(PartyType.customer);
        fail('the server should refuse customers');
      } on ApiException catch (e) {
        expect(e.isForbiddenRole, isTrue);
      }

      // Add is allowed, edit isn't.
      await sales.read(productsProvider.future);
      final added = await sales.read(productsProvider.notifier).add(
            const ProductInput(
              sku: 'GRID-LIVE-1',
              name: 'Grid live sugar',
              unit: 'bag',
              purchasePrice: 900,
              sellingPrice: 1000,
              minStock: 1,
            ),
          );
      expect(added.queued, isFalse);
      final product = sales.read(productListProvider).firstWhere((p) => p.sku == 'GRID-LIVE-1');
      try {
        await sales.read(productsRepositoryProvider).update(
              product.id,
              const ProductInput(
                sku: 'GRID-LIVE-1',
                name: 'Renamed',
                unit: 'bag',
                purchasePrice: 900,
                sellingPrice: 1000,
                minStock: 1,
              ),
            );
        fail('the server should refuse editing');
      } on ApiException catch (e) {
        expect(e.isForbiddenRole, isTrue);
      }

      // Warehouses are readable (stock out needs one) but can't be changed.
      final warehouses = await sales.read(warehousesProvider.future);
      expect(warehouses, isNotEmpty);
      try {
        await sales.read(warehousesRepositoryProvider).update(warehouses.first.id, {'address': 'X'});
        fail('the server should refuse editing a warehouse');
      } on ApiException catch (e) {
        expect(e.isForbiddenRole, isTrue);
      }

      // The Owner is unaffected by the customised Sales Staff row.
      final owner = await _signIn(_need('AIMIFY_OWNER_EMAIL'));
      final ownerMe = owner.read(authControllerProvider).value!;
      expect(visibleScreensFor(ownerMe.role, ownerMe.permissions), AppScreen.values);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
