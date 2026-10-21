// LIVE end-to-end check of stock per warehouse against a running aimify-web
// (`npm run dev` on http://localhost:3000), through the same repositories
// and notifiers the screens use.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with two active warehouses named
// "Lagos" and "Kano" and no products:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_warehouse_stock_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
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

void main() {
  test(
    'stock per warehouse against the real backend',
    () async {
      final c = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      await c.read(authControllerProvider.notifier).login(
            email: _need('AIMIFY_OWNER_EMAIL'),
            password: _need('AIMIFY_PASSWORD'),
          );

      final warehouses = await c.read(warehousesProvider.future);
      final lagos = warehouses.firstWhere((w) => w.name == 'Lagos');
      final kano = warehouses.firstWhere((w) => w.name == 'Kano');
      expect(lagos.stock.isEmpty && kano.stock.isEmpty, isTrue);

      await c.read(productsProvider.future);
      await c.read(productsProvider.notifier).add(
            const ProductInput(sku: 'WH-LIVE-1', name: 'Live rice', unit: 'bag', purchasePrice: 100, sellingPrice: 150, minStock: 2),
          );
      final productId = c.read(productListProvider).firstWhere((p) => p.sku == 'WH-LIVE-1').id;

      await c.read(movementsProvider.future);
      final into = await c.read(movementsProvider.notifier).record(
            productId: productId,
            warehouseId: lagos.id,
            type: StockMovementType.stockIn,
            quantity: 8,
          );
      expect(into.value!.warehouseStock, 8);
      expect(into.value!.currentStock, 8);

      var rice = c.read(productListProvider).firstWhere((p) => p.id == productId);
      expect(rice.stockIn(lagos.id), 8);
      expect(rice.stockIn(kano.id), 0);
      expect(rice.currentStock, 8);

      // Selling from Kano, which has none, is refused by the server.
      try {
        await c.read(inventoryRepositoryProvider).record(
              productId: productId,
              warehouseId: kano.id,
              type: StockMovementType.stockOut,
              quantity: -1,
            );
        fail('stock out from an empty warehouse should be refused');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.code, 'insufficient_stock');
        expect(e.message, contains('Kano'));
      }

      await c.read(movementsProvider.notifier).record(
            productId: productId,
            warehouseId: kano.id,
            type: StockMovementType.stockIn,
            quantity: 3,
          );
      rice = c.read(productListProvider).firstWhere((p) => p.id == productId);
      expect(rice.stockByWarehouse, {lagos.id: 8, kano.id: 3});
      expect(rice.currentStock, 11);

      final refreshed = c.read(warehouseListProvider);
      expect(refreshed.firstWhere((w) => w.id == lagos.id).stock.units, 8);
      expect(refreshed.firstWhere((w) => w.id == kano.id).stock.valueAtCost, 300);

      final kanoMoves = await c.read(inventoryRepositoryProvider).movementsFresh();
      final kanoIn = kanoMoves.firstWhere((m) => m.warehouseId == kano.id);
      expect(kanoIn.previousStock, 0, reason: 'before/after are the warehouse balance');
      expect(kanoIn.newStock, 3);

      // Kano can't be disabled while it holds stock; empty it, then it can.
      try {
        await c.read(warehousesRepositoryProvider).update(kano.id, {'status': 'inactive'});
        fail('disabling a stocked warehouse should be refused');
      } on ApiException catch (e) {
        expect(e.code, 'warehouse_not_empty');
        expect(e.message, contains('Live rice (3)'));
      }
      await c.read(movementsProvider.notifier).record(
            productId: productId,
            warehouseId: kano.id,
            type: StockMovementType.stockOut,
            quantity: -3,
          );
      await c.read(warehousesProvider.notifier).edit(kano.id, {'status': 'inactive'});
      expect(c.read(warehouseListProvider).firstWhere((w) => w.id == kano.id).isActive, isFalse);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
