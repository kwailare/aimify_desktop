// LIVE end-to-end check of credit and debt against a running aimify-web
// (`npm run dev` on http://localhost:3000): payment terms, credit sales and
// a manual charge with due dates, a payment on account that settles the
// oldest first with a receipt, the sales it settled showing as paid, the
// aging report on both sides, and a supplier payment settling a purchase.
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
//   flutter test test/live/live_debts_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/credits_debts/data/debt_report.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
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
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_token_storage.dart';

final _env = Platform.environment;
final _live = _env['AIMIFY_LIVE'] == '1';
String _need(String name) => _env[name] ?? (throw StateError('Set $name'));

void main() {
  test(
    'credit and debt against the real backend',
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
      final rice = await c.read(productsRepositoryProvider).create(
            const ProductInput(sku: 'LIVE-DEBT-RICE', name: 'Live Rice', unit: 'bag', purchasePrice: 600, sellingPrice: 1000, minStock: 0),
          );
      await c.read(inventoryRepositoryProvider).record(
            productId: rice.id,
            warehouseId: lagos,
            type: StockMovementType.stockIn,
            quantity: 50,
          );

      final customers = c.read(partiesProvider(PartyType.customer).notifier);
      await c.read(partiesProvider(PartyType.customer).future);
      final ada = (await customers.add(
        const PartyInput(type: PartyType.customer, name: 'Live Ada', paymentTermsDays: 7),
      ))
          .value!;
      expect(ada.paymentTermsDays, 7);

      // An opening balance, then two credit sales.
      final credit = c.read(creditServiceProvider);
      final opening = (await credit.record(
        partyType: PartyType.customer,
        partyId: ada.id,
        kind: CreditKind.charge,
        amount: 2000,
        note: 'Opening balance',
      ))
          .value!
          .entry;
      expect(opening.openAmount, 2000);
      expect(opening.dueDate!.difference(opening.createdAt).inDays, 7);

      await c.read(salesProvider.future);
      Future<Sale> sell(int qty) async => (await c.read(salesProvider.notifier).add(
                SaleInput(
                  customerId: ada.id,
                  warehouseId: lagos,
                  lines: [SaleLineInput(productId: rice.id, quantity: qty, unitPrice: 1000)],
                  amountPaid: 0,
                ),
              ))
          .value!
          .sale;
      final s1 = await sell(3);
      final s2 = await sell(2);
      expect(s1.dueDate!.difference(s1.saleDate).inDays, 7);

      // Pay 4000 on account by transfer: the opening balance, then 2000 of sale 1.
      final paid = (await credit.record(
        partyType: PartyType.customer,
        partyId: ada.id,
        kind: CreditKind.payment,
        amount: 4000,
        method: 'transfer',
      ))
          .value!;
      expect(paid.entry.receiptNumber, startsWith('RCPT-'));
      expect(paid.entry.method, 'transfer');
      expect(paid.entry.allocations.map((a) => (a.reference, a.amount)), [
        ('Opening balance', 2000.0),
        (s1.reference, 2000.0),
      ]);
      expect(paid.balanceOwed, 3000);

      // The sales follow (the providers re-read after a payment).
      final sales = await c.read(salesProvider.future);
      final s1Now = sales.firstWhere((s) => s.id == s1.id);
      expect(s1Now.amountPaid, 2000);
      expect(sales.firstWhere((s) => s.id == s2.id).amountPaid, 0);
      final detail = await c.read(saleDetailProvider(s1.id).future);
      expect(detail.payments.single.receiptNumber, paid.entry.receiptNumber);

      // The aging report: 3000 owed, none overdue yet (7-day terms).
      final report = (await c.read(debtReportProvider(PartyType.customer).future))!;
      final row = report.parties.firstWhere((p) => p.id == ada.id);
      expect(row.balance, 3000);
      expect(row.buckets[AgeBucket.current], 3000);
      expect(row.overdue, 0);
      expect(row.items.map((i) => i.reference), [s1.reference, s2.reference]);
      expect(row.lastPaymentAt, isNotNull);

      // Suppliers: a purchase on credit, settled by a payment on account.
      final suppliers = c.read(partiesProvider(PartyType.supplier).notifier);
      await c.read(partiesProvider(PartyType.supplier).future);
      final sup = (await suppliers.add(
        const PartyInput(type: PartyType.supplier, name: 'Live Supplier', paymentTermsDays: 10),
      ))
          .value!;
      final purchase = await c.read(purchasesRepositoryProvider).create(
            PurchaseInput(
              supplierId: sup.id,
              warehouseId: lagos,
              lines: [PurchaseLineInput(productId: rice.id, quantity: 5, unitCost: 600)],
              orderDate: DateTime.now(),
              receive: true,
            ),
          );
      final supplierPay = (await credit.record(
        partyType: PartyType.supplier,
        partyId: sup.id,
        kind: CreditKind.payment,
        amount: 1000,
      ))
          .value!;
      expect(supplierPay.entry.receiptNumber, isNull);
      expect(supplierPay.entry.allocations.single.reference, purchase.reference);
      final purchaseNow = await c.read(purchaseDetailProvider(purchase.id).future);
      expect(purchaseNow.amountPaid, 1000);
      final supplierReport = (await c.read(debtReportProvider(PartyType.supplier).future))!;
      expect(supplierReport.parties.firstWhere((p) => p.id == sup.id).balance, 2000);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
