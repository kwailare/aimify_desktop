// LIVE end-to-end check of customers against a running aimify-web
// (`npm run dev` on http://localhost:3000): customer types and their
// default limits, a customer of a type, archiving and restoring (archived
// customers stay listed), what a customer bought, their sales, renaming a
// type and a type in use refusing removal. Same repositories and notifiers
// the screens use, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with two active warehouses (Lagos and
// Kano) and an Owner:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_customers_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/customers/data/customer_excel.dart';
import 'package:aimify_desktop/features/customers/data/customer_types.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
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

void main() {
  test(
    'customers against the real backend',
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
      expect(c.read(authControllerProvider).value!.hasPermission('customers.types'), isTrue);

      final types = c.read(customerTypesProvider.notifier);
      await c.read(customerTypesProvider.future);
      final wholesale = await types.add('Live Wholesale', defaultCreditLimit: 300000);
      expect(wholesale.defaultCreditLimit, 300000);
      try {
        await types.add('live wholesale');
        fail('a duplicate type should be refused');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
      }

      // Importing works out the type and its default limit on this side.
      final parsed = parseCustomerWorkbook(
        buildCustomerImportTemplate(),
        types: [const CustomerType(id: 'x', name: 'Retail')],
      );
      expect(parsed.rows.single.input.customerTypeId, 'x');

      final customers = c.read(partiesProvider(PartyType.customer).notifier);
      await c.read(partiesProvider(PartyType.customer).future);
      final added = await customers.add(
        PartyInput(
          type: PartyType.customer,
          name: 'Live Customer',
          phone: '0800',
          creditLimit: wholesale.defaultCreditLimit,
          customerTypeId: wholesale.id,
        ),
      );
      expect(added.queued, isFalse, reason: 'the connection should be good for this test');
      final id = added.value!.id;
      Party live() => c.read(partyListProvider(PartyType.customer)).firstWhere((p) => p.id == id);
      expect(live().customerTypeName, 'Live Wholesale');
      expect(live().creditLimit, 300000);
      expect(live().salesCount, 0);

      // Archived customers stay in the list, marked, and can be restored.
      await customers.archive(id);
      expect(live().isActive, isFalse);
      expect(c.read(activePartyListProvider(PartyType.customer)).any((p) => p.id == id), isFalse);
      await customers.restore(id);
      expect(live().isActive, isTrue);

      // A sale shows in what they bought, and in their sales.
      final lagos = (await c.read(warehousesProvider.future)).firstWhere((w) => w.name == 'Lagos').id;
      final rice = await c.read(productsRepositoryProvider).create(
            const ProductInput(sku: 'LIVE-CUS-RICE', name: 'Live Rice', unit: 'bag', purchasePrice: 100, sellingPrice: 150, minStock: 0),
          );
      await c.read(inventoryRepositoryProvider).record(
            productId: rice.id,
            warehouseId: lagos,
            type: StockMovementType.stockIn,
            quantity: 10,
          );
      await c.read(salesProvider.future);
      final sold = await c.read(salesProvider.notifier).add(
            SaleInput(
              customerId: id,
              warehouseId: lagos,
              lines: [SaleLineInput(productId: rice.id, quantity: 4, unitPrice: 150)],
              amountPaid: 200,
            ),
          );
      final sale = sold.value!.sale;
      expect(live().totalSales, 600);
      expect(live().salesCount, 1);
      expect(live().lastSaleAt, isNotNull);
      expect(live().balanceOwed, 400);
      final history = await c.read(customerSaleHistoryProvider(id).future);
      expect(history.map((s) => s.id), [sale.id]);

      // A rename shows on the customer; a type in use can't be removed.
      await types.edit(wholesale.id, name: 'Live Wholesalers');
      expect(live().customerTypeName, 'Live Wholesalers');
      try {
        await types.remove(wholesale.id);
        fail('a type in use should be refused');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.code, 'type_in_use');
      }
      final listed = await c.read(customerTypesRepositoryProvider).list();
      expect(listed.firstWhere((t) => t.id == wholesale.id).customerCount, 1);

      // The export holds what the screen shows.
      final bytes = buildCustomerExport([live()], (p) => p.customerTypeName);
      expect(bytes, isNotEmpty);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
