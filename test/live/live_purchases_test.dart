// LIVE end-to-end check of purchases against a running aimify-web
// (`npm run dev` on http://localhost:3000): ordering, receiving part of a
// delivery into a warehouse, the product's purchase price following the
// cost, the supplier's balance, paying, cancelling a paid draft, and a
// purchase received on the spot. Same repositories and notifiers the
// screens use, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with two active warehouses (Lagos and
// Kano) and an Owner:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_purchases_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/purchases/data/purchases_repository.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
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
    'purchases against the real backend',
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

      expect(c.read(authControllerProvider).value!.hasPermission('purchases.receive'), isTrue);

      final warehouses = await c.read(warehousesProvider.future);
      final lagos = warehouses.firstWhere((w) => w.name == 'Lagos').id;
      final kano = warehouses.firstWhere((w) => w.name == 'Kano').id;

      final parties = c.read(partiesRepositoryProvider);
      final supplier = await parties.create(const PartyInput(type: PartyType.supplier, name: 'Live Supplier'));
      final products = c.read(productsRepositoryProvider);
      final rice = await products.create(
        const ProductInput(
          sku: 'LIVE-RICE',
          name: 'Live Rice',
          unit: 'bag',
          purchasePrice: 60000,
          sellingPrice: 70000,
          minStock: 0,
        ),
      );

      final repo = c.read(purchasesRepositoryProvider);
      final notifier = c.read(purchasesProvider.notifier);
      await c.read(purchasesProvider.future);

      // Order 10 at 62000, 5000 discount.
      final order = await repo.create(
        PurchaseInput(
          supplierId: supplier.id,
          warehouseId: lagos,
          lines: [PurchaseLineInput(productId: rice.id, quantity: 10, unitCost: 62000)],
          placeOrder: true,
          orderDate: DateTime.now(),
          discount: 5000,
        ),
        clientRef: 'live-order-${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(order.reference, startsWith('PO-'));
      expect(order.status, PurchaseStatus.pending);
      expect(order.total, 615000);

      // 4 arrive.
      final first = await notifier.receive(order.id, lines: {order.lines.single.id: 4});
      expect(first.purchase.status, PurchaseStatus.partiallyReceived);
      expect(first.priceChanges.single.next, 62000);
      final afterFirst = c.read(productListProvider).firstWhere((p) => p.id == rice.id);
      expect(afterFirst.stockIn(lagos), 4);
      expect(afterFirst.stockIn(kano), 0);
      expect(afterFirst.purchasePrice, 62000);
      var owed = c.read(partyListProvider(PartyType.supplier)).firstWhere((p) => p.id == supplier.id).balanceOwed;
      expect(owed, 615000, reason: 'the whole purchase goes on the account with the first delivery');

      // More than outstanding is refused with what's left.
      try {
        await notifier.receive(order.id, lines: {order.lines.single.id: 7});
        fail('over-receipt should be refused');
      } on ApiException catch (e) {
        expect(e.code, 'over_receipt');
        expect(e.statusCode, 409);
      }

      // The rest arrives, then it's paid in full.
      final done = await notifier.receive(order.id);
      expect(done.purchase.status, PurchaseStatus.received);
      expect(c.read(productListProvider).firstWhere((p) => p.id == rice.id).stockIn(lagos), 10);
      final paid = await notifier.pay(order.id, amount: 615000, note: 'Live transfer');
      expect(paid.isPaid, isTrue);
      owed = c.read(partyListProvider(PartyType.supplier)).firstWhere((p) => p.id == supplier.id).balanceOwed;
      expect(owed, 0);

      final detail = await repo.get(order.id);
      expect(detail.receipts.length, 2);
      expect(detail.payments.single.amount, 615000);

      // A paid draft cancelled: the supplier owes it back.
      final draft = await repo.create(
        PurchaseInput(
          supplierId: supplier.id,
          warehouseId: kano,
          lines: [PurchaseLineInput(productId: rice.id, quantity: 1, unitCost: 1000)],
          orderDate: DateTime.now(),
          amountPaid: 1000,
        ),
      );
      final refund = await notifier.cancel(draft.id);
      expect(refund, 1000);
      owed = c.read(partyListProvider(PartyType.supplier)).firstWhere((p) => p.id == supplier.id).balanceOwed;
      expect(owed, -1000);

      // Bought and collected on the spot, into Kano.
      final spot = await notifier.add(
        PurchaseInput(
          supplierId: supplier.id,
          warehouseId: kano,
          lines: [PurchaseLineInput(productId: rice.id, quantity: 3, unitCost: 61000)],
          orderDate: DateTime.now(),
          amountPaid: 183000,
          receive: true,
        ),
      );
      expect(spot.queued, isFalse, reason: 'the connection should be good for this test');
      expect(spot.value!.status, PurchaseStatus.received);
      expect(c.read(productListProvider).firstWhere((p) => p.id == rice.id).stockIn(kano), 3);

      final open = (await c.read(purchasesProvider.future)).where((p) => p.status.isOpen);
      expect(open, isEmpty);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
