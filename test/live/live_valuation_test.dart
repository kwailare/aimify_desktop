// LIVE check of the valuation report against a running aimify-web
// (`npm run dev` on http://localhost:3000), through the same provider the
// Valuation tab uses.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with two active warehouses named
// "Lagos" and "Kano" and no products:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_valuation_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/reports/data/valuation_report.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
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
    'valuation report against the real backend',
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

      await c.read(productsProvider.future);
      Future<String> add(String sku, String category, double cost, double price) async {
        await c.read(productsProvider.notifier).add(
              ProductInput(sku: sku, name: sku, category: category, unit: 'bag', purchasePrice: cost, sellingPrice: price, minStock: 0),
            );
        return c.read(productListProvider).firstWhere((p) => p.sku == sku).id;
      }

      final rice = await add('VAL-RICE', 'Grains', 61000, 65000);
      final oil = await add('VAL-OIL', 'Oils', 11000, 12500);
      // Straight to the server: this tests the valuation, not offline
      // queueing (a slow connection would otherwise save these for later).
      Future<void> stockIn(String productId, String warehouseId, int qty) => c
          .read(inventoryRepositoryProvider)
          .record(productId: productId, warehouseId: warehouseId, type: StockMovementType.stockIn, quantity: qty);
      await stockIn(rice, lagos.id, 10);
      await stockIn(rice, kano.id, 2);
      await stockIn(oil, kano.id, 20);

      final all = (await c.read(valuationReportProvider((warehouseId: null, category: null)).future))!;
      expect(all.totals.valueAtCost, 12 * 61000 + 20 * 11000);
      expect(all.totals.valueAtRetail, 12 * 65000 + 20 * 12500);
      expect(all.totals.units, 32);
      expect(all.byProduct.first.sku, 'VAL-RICE', reason: 'highest value first');
      expect(all.byCategory.map((g) => g.label), containsAll(['Grains', 'Oils']));

      final kanoOnly = (await c.read(valuationReportProvider((warehouseId: kano.id, category: null)).future))!;
      expect(kanoOnly.totals.valueAtCost, 2 * 61000 + 20 * 11000);
      expect(kanoOnly.byWarehouse.single.label, 'Kano');

      final grains = (await c.read(valuationReportProvider((warehouseId: null, category: 'Grains')).future))!;
      expect(grains.totals.valueAtCost, 12 * 61000);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
