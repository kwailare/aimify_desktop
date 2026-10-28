// LIVE end-to-end check of suppliers against a running aimify-web
// (`npm run dev` on http://localhost:3000): a supplier with terms, purchases
// at two prices, what was bought from them, their purchases, their price
// history, an overdue opening balance, and archiving and restoring.
// Same repositories and notifiers the screens use, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with two active warehouses (Lagos and
// Kano) and an Owner:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_suppliers_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/purchases/data/purchases_repository.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/suppliers/data/supplier_prices.dart';
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
    'suppliers against the real backend',
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

      final lagos = (await c.read(warehousesProvider.future)).firstWhere((w) => w.name == 'Lagos').id;
      final suppliers = c.read(partiesProvider(PartyType.supplier).notifier);
      await c.read(partiesProvider(PartyType.supplier).future);
      final sup = (await suppliers.add(
        const PartyInput(type: PartyType.supplier, name: 'Live Supplier', contactPerson: 'Musa', paymentTermsDays: 14),
      ))
          .value!;
      Party live() => c.read(partyListProvider(PartyType.supplier)).firstWhere((p) => p.id == sup.id);
      expect(live().paymentTermsDays, 14);
      expect(live().totalPurchases, 0);

      final rice = await c.read(productsRepositoryProvider).create(
            ProductInput(sku: 'LIVE-SUP-RICE', name: 'Live Rice', unit: 'bag', purchasePrice: 600, sellingPrice: 900, minStock: 5, supplierId: sup.id),
          );

      await c.read(purchasesProvider.future);
      final notifier = c.read(purchasesProvider.notifier);
      Future<Purchase> buy(double cost, DateTime date) async => (await notifier.add(
            PurchaseInput(
              supplierId: sup.id,
              warehouseId: lagos,
              lines: [PurchaseLineInput(productId: rice.id, quantity: 10, unitCost: cost)],
              orderDate: date,
              receive: true,
            ),
          ))
              .value!;
      final first = await buy(600, DateTime(2026, 9, 1));
      final second = await buy(650, DateTime(2026, 10, 1));

      // What was bought from them.
      expect(live().totalPurchases, 12500);
      expect(live().purchaseCount, 2);
      expect(live().lastPurchaseAt!.toUtc(), DateTime.utc(2026, 10, 1));
      final history = await c.read(supplierPurchaseHistoryProvider(sup.id).future);
      expect(history.map((p) => p.id), containsAll([first.id, second.id]));

      // Price history: up 50 from the last time.
      final prices = await c.read(supplierPricesProvider(sup.id).future);
      final ricePrice = prices.single;
      expect(ricePrice.lastCost, 650);
      expect(ricePrice.previousCost, 600);
      expect(ricePrice.wentUp, isTrue);
      expect(ricePrice.history.map((h) => h.reference), [second.reference, first.reference]);

      // An imported supplier with what you already owe them.
      final imported = (await suppliers.add(
        const PartyInput(type: PartyType.supplier, name: 'Live Imported', paymentTermsDays: 0),
      ))
          .value!;
      await c.read(creditServiceProvider).record(
            partyType: PartyType.supplier,
            partyId: imported.id,
            kind: CreditKind.charge,
            amount: 5000,
            note: 'Opening balance (imported)',
          );
      await suppliers.refresh();
      final importedNow = c.read(partyListProvider(PartyType.supplier)).firstWhere((p) => p.id == imported.id);
      expect(importedNow.balanceOwed, 5000);

      // Archive and restore: archived suppliers stay listed.
      await suppliers.archive(imported.id);
      expect(c.read(partyListProvider(PartyType.supplier)).firstWhere((p) => p.id == imported.id).isActive, isFalse);
      expect(c.read(activePartyListProvider(PartyType.supplier)).any((p) => p.id == imported.id), isFalse);
      await suppliers.restore(imported.id);
      expect(c.read(partyListProvider(PartyType.supplier)).firstWhere((p) => p.id == imported.id).isActive, isTrue);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
