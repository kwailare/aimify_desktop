// LIVE end-to-end check of sales against a running aimify-web
// (`npm run dev` on http://localhost:3000): a walk-in cash sale taking
// stock out of one warehouse, the walk-in and stock rules, a credit sale on
// a customer's account, the credit limit and the Owner's override, a later
// payment, voiding (stock back, account reversed, refund owed) and a retry
// with the same clientRef. Same repositories and notifiers the screens use,
// no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with two active warehouses (Lagos and
// Kano) and an Owner:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_sales_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/purchases/data/purchases_repository.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/sales/data/sales_repository.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
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

Future<void> _refused(Future<Object?> Function() call, String code) async {
  try {
    await call();
    fail('expected $code');
  } on ApiException catch (e) {
    expect(e.code, code);
  }
}

void main() {
  test(
    'sales against the real backend',
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
      final me = c.read(authControllerProvider).value!;
      for (final p in ['sales.view', 'sales.create', 'sales.discount', 'sales.override', 'sales.void']) {
        expect(me.hasPermission(p), isTrue, reason: p);
      }

      final warehouses = await c.read(warehousesProvider.future);
      final lagos = warehouses.firstWhere((w) => w.name == 'Lagos').id;
      final kano = warehouses.firstWhere((w) => w.name == 'Kano').id;

      final parties = c.read(partiesRepositoryProvider);
      final supplier = await parties.create(const PartyInput(type: PartyType.supplier, name: 'Live Supplier'));
      final customer = await parties.create(
        const PartyInput(type: PartyType.customer, name: 'Live Customer', creditLimit: 200000),
      );
      final rice = await c.read(productsRepositoryProvider).create(
            const ProductInput(
              sku: 'LIVE-RICE',
              name: 'Live Rice',
              unit: 'bag',
              purchasePrice: 60000,
              sellingPrice: 70000,
              minStock: 2,
            ),
          );
      // 6 bags into Lagos.
      await c.read(purchasesRepositoryProvider).create(
            PurchaseInput(
              supplierId: supplier.id,
              warehouseId: lagos,
              lines: [PurchaseLineInput(productId: rice.id, quantity: 6, unitCost: 60000)],
              orderDate: DateTime.now(),
              receive: true,
            ),
          );

      final repo = c.read(salesRepositoryProvider);
      final notifier = c.read(salesProvider.notifier);
      await c.read(productsProvider.future);
      await c.read(partiesProvider(PartyType.customer).future);
      await c.read(salesProvider.future);
      int lagosStock() => c.read(productListProvider).firstWhere((p) => p.id == rice.id).stockIn(lagos);
      double owed() =>
          c.read(partyListProvider(PartyType.customer)).firstWhere((p) => p.id == customer.id).balanceOwed;

      // A walk-in buys 1 for cash.
      final cash = await notifier.add(
        SaleInput(
          warehouseId: lagos,
          lines: [SaleLineInput(productId: rice.id, quantity: 1, unitPrice: 70000)],
          amountPaid: 70000,
        ),
      );
      expect(cash.queued, isFalse, reason: 'the connection should be good for this test');
      final walkIn = cash.value!.sale;
      expect(walkIn.reference, 'INV-0001');
      expect(walkIn.isWalkIn, isTrue);
      expect(walkIn.isPaid, isTrue);
      expect(lagosStock(), 5);

      // Walk-ins pay in full; Kano has none; never more than is held.
      await _refused(
        () => repo.create(
          SaleInput(warehouseId: lagos, lines: [SaleLineInput(productId: rice.id, quantity: 1, unitPrice: 70000)], amountPaid: 1),
        ),
        'walk_in_must_pay',
      );
      await _refused(
        () => repo.create(
          SaleInput(warehouseId: kano, lines: [SaleLineInput(productId: rice.id, quantity: 1, unitPrice: 70000)], amountPaid: 70000),
        ),
        'insufficient_stock',
      );

      // On credit: 2 bags at a discount, 40000 paid now by transfer.
      final credit = await notifier.add(
        SaleInput(
          customerId: customer.id,
          warehouseId: lagos,
          lines: [SaleLineInput(productId: rice.id, quantity: 2, unitPrice: 65000)],
          discount: 10000,
          amountPaid: 40000,
          paymentMethod: SalePaymentMethod.transfer,
        ),
      );
      final onCredit = credit.value!.sale;
      expect(onCredit.total, 120000);
      expect(onCredit.balance, 80000);
      expect(onCredit.lines.single.discounted, isTrue);
      expect(owed(), 80000);
      expect(lagosStock(), 3);

      // 150000 more on credit would pass the 200000 limit...
      final over = SaleInput(
        customerId: customer.id,
        warehouseId: lagos,
        lines: [SaleLineInput(productId: rice.id, quantity: 2, unitPrice: 75000)],
        amountPaid: 0,
      );
      await _refused(() => repo.create(over), 'over_credit_limit');
      expect(lagosStock(), 3, reason: 'a refused sale takes nothing');

      // ...unless the Owner allows it. It takes Lagos to its reorder level.
      final allowed = await notifier.add(
        SaleInput(
          customerId: over.customerId,
          warehouseId: over.warehouseId,
          lines: over.lines,
          amountPaid: 0,
          allowOverLimit: true,
        ),
      );
      expect(allowed.value!.sale.overLimit, isTrue);
      expect(allowed.value!.alerts.map((a) => a.productId), contains(rice.id));
      expect(owed(), 230000);
      expect(lagosStock(), 1);

      // A later payment on the credit sale, then more than is left.
      await notifier.pay(onCredit.id, amount: 50000, method: SalePaymentMethod.cash, note: 'Live');
      await _refused(
        () => repo.pay(onCredit.id, amount: 30001, method: SalePaymentMethod.cash),
        'overpayment',
      );
      final detail = await repo.get(onCredit.id);
      expect(detail.payments.map((p) => (p.amount, p.method)), [
        (40000.0, SalePaymentMethod.transfer),
        (50000.0, SalePaymentMethod.cash),
      ]);
      expect(owed(), 180000);

      // Void the credit sale: its 2 bags come back and its 30000 balance
      // leaves the account; 90000 paid is owed back.
      final refund = await notifier.voidSale(onCredit.id, reason: 'Live test');
      expect(refund, 90000);
      expect(lagosStock(), 3);
      expect(owed(), 60000, reason: '230000 - 50000 paid, - 120000 reversed: the 90000 they paid on it now counts in their favour');
      await _refused(() => repo.voidSale(onCredit.id, reason: 'again'), 'sale_not_voidable');
      await _refused(() => repo.pay(onCredit.id, amount: 1, method: SalePaymentMethod.cash), 'sale_voided');

      // The same clientRef twice records once.
      final ref = 'live-sale-${DateTime.now().microsecondsSinceEpoch}';
      final input = SaleInput(
        warehouseId: lagos,
        lines: [SaleLineInput(productId: rice.id, quantity: 1, unitPrice: 70000)],
        amountPaid: 70000,
      );
      final once = await repo.create(input, clientRef: ref);
      final twice = await repo.create(input, clientRef: ref);
      expect(twice.sale.id, once.sale.id);
      final all = await c.read(salesProvider.future);
      await notifier.refresh();
      expect(c.read(salesProvider).value!.where((s) => s.id == once.sale.id).length, 1);
      expect(all, isNotEmpty);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
