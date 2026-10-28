// Sales on the server (feature checklist step 8): parsing and the offline
// queue, the form (walk-in or customer, stock per warehouse, prices and
// discounts only with sales.discount, the credit limit and its override),
// the list with its periods, filters and offline rows, the detail actions
// per role (payment, void), and the customer's history.

import 'dart:convert';

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/data/outbox_overlay.dart';
import 'package:aimify_desktop/features/parties/data/party_overlay.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/parties/presentation/party_history_dialog.dart';
import 'package:aimify_desktop/features/sales/data/sales_repository.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/features/sales/presentation/sale_detail_dialog.dart';
import 'package:aimify_desktop/features/sales/presentation/sales_screen.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/offline/outbox.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

class _Auth extends AuthController {
  _Auth(this.role, this.permissions);

  final String role;
  final List<String> permissions;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
          setupCompletedAt: DateTime(2026, 10, 1),
        ),
        role: role,
        permissions: permissions,
      );
}

class _Rig {
  _Rig({
    this.role = 'Owner',
    List<String>? permissions,
    List<Sale>? sales,
    List<Party>? customers,
    this.store,
  })  : permissions = permissions ?? defaultPermissionsFor(role),
        sales = FakeSalesRepository(sales),
        parties = FakePartiesRepository(
          customers: customers ??
              [
                fixtureParty('c1', name: 'Ada Stores', balance: 400, creditLimit: 500),
                fixtureParty('c2', name: 'Bello Mart'),
              ],
        );

  final String role;
  final List<String> permissions;
  final FakeSalesRepository sales;
  final FakePartiesRepository parties;
  final MemoryLocalStore? store;
}

Future<_Rig> _pump(WidgetTester tester, Widget home, {_Rig? rig, Size size = const Size(1400, 1000)}) async {
  final r = rig ?? _Rig();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(r.role, r.permissions)),
        ...fakeDataOverrides(
          sales: r.sales,
          parties: r.parties,
          store: r.store,
          products: FakeProductsRepository([
            fixtureProduct('1', name: 'Rice', price: 150, stock: 10),
            fixtureProduct('2', name: 'Sugar', price: 80, stock: 2),
            fixtureProduct('3', name: 'Salt', stock: 0),
          ]),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: home)),
    ),
  );
  await _settle(tester);
  return r;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Opens the sale form the way the screens do, so the result is reported.
Widget _saleOpener({String? customerId}) => Consumer(
      builder: (context, ref, _) => Center(
        child: ElevatedButton(
          onPressed: () => recordSale(context, ref, customerId: customerId),
          child: const Text('open'),
        ),
      ),
    );

Widget _opener(Widget dialog) => Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => showDialog(context: context, builder: (_) => dialog),
          child: const Text('open'),
        ),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Future<void> _addProduct(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownMenu<String>));
  await _settle(tester);
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

Future<void> _complete(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sale-complete')));
  await _settle(tester);
}

OutboxOp _queued(SaleInput input, {String id = 'q1'}) => OutboxOp(
      id: id,
      kind: OpKind.saleCreate,
      payload: {'input': input.toJson()},
      createdAt: DateTime(2026, 10, 26, 9),
    );

void main() {
  group('models', () {
    test('a sale parses from the API, with lines, payments and its standing', () {
      final s = Sale.fromJson({
        'id': 'sa1',
        'reference': 'INV-0007',
        'customerId': 'c1',
        'customerName': 'Ada Stores',
        'warehouseId': 'w1',
        'warehouseName': 'Main',
        'status': 'completed',
        'saleDate': '2026-10-26T10:00:00.000Z',
        'subtotal': 400,
        'discount': 20,
        'tax': 10,
        'total': 390,
        'amountPaid': 100,
        'overLimit': true,
        'lines': [
          {'id': 'l1', 'productId': 'p1', 'productName': 'Rice', 'sku': 'R', 'unit': 'bag', 'quantity': 2, 'unitPrice': 140, 'listPrice': 150},
          {'id': 'l2', 'productId': 'p2', 'productName': 'Salt', 'sku': 'S', 'unit': 'bag', 'quantity': 3, 'unitPrice': 40},
        ],
        'payments': [
          {'id': 'p1', 'amount': 100, 'method': 'transfer', 'createdAt': '2026-10-26T10:00:00.000Z'},
        ],
      });
      expect(s.balance, 290);
      expect(s.isPaid, isFalse);
      expect(s.isWalkIn, isFalse);
      expect(s.overLimit, isTrue);
      expect(s.units, 5);
      expect(s.lines.first.discounted, isTrue);
      expect(s.lines.last.listPrice, 40, reason: 'no list price means sold at its price');
      expect(s.payments.single.method, SalePaymentMethod.transfer);

      final voided = Sale.fromJson({
        'id': 'sa2', 'reference': 'INV-0008', 'customerId': null, 'warehouseId': 'w1',
        'status': 'voided', 'saleDate': '2026-10-26T10:00:00.000Z', 'total': 50, 'amountPaid': 50,
      });
      expect(voided.isWalkIn, isTrue);
      expect(voided.customerName, 'Walk-in customer');
      expect(voided.balance, 0, reason: 'nothing is due on a voided sale');
      expect(voided.isPaid, isFalse);
    });

    test('the sale input round-trips through the offline queue, and resolves offline ids', () {
      const input = SaleInput(
        customerId: 'local:c',
        warehouseId: 'w1',
        lines: [SaleLineInput(productId: 'local:p', quantity: 3, unitPrice: 100)],
        discount: 20,
        tax: 5,
        amountPaid: 85,
        paymentMethod: SalePaymentMethod.pos,
        allowOverLimit: true,
      );
      final back = SaleInput.fromJson(jsonDecode(jsonEncode(input.toJson())) as Map<String, dynamic>);
      expect(back.total, 285);
      expect(back.unpaid, 200);
      expect(back.paymentMethod, SalePaymentMethod.pos);
      expect(back.allowOverLimit, isTrue);
      final resolved = back.resolved((id) => id.replaceFirst('local:', 'srv-'));
      expect(resolved.customerId, 'srv-c');
      expect(resolved.lines.single.productId, 'srv-p');
      expect(const SaleInput(warehouseId: 'w1', lines: [], amountPaid: 0).resolved((id) => 'x').customerId, isNull);
    });

    test('a sale made offline takes the stock and adds the unpaid part to the customer at once', () {
      final op = _queued(const SaleInput(
        customerId: 'c1',
        warehouseId: 'w1',
        lines: [SaleLineInput(productId: '1', quantity: 4, unitPrice: 150)],
        amountPaid: 200,
      ));
      final view = overlayOutbox([fixtureProduct('1', stock: 10)], [op]);
      expect(view.products.single.currentStock, 6);
      expect(view.products.single.stockIn('w1'), 6);

      final customers = overlayParties([fixtureParty('c1', balance: 50)], [op], PartyType.customer);
      expect(customers.single.balanceOwed, 450, reason: '50 before, 600 sold, 200 paid');

      final walkIn = _queued(const SaleInput(
        warehouseId: 'w1',
        lines: [SaleLineInput(productId: '1', quantity: 1, unitPrice: 150)],
        amountPaid: 150,
      ));
      expect(
        overlayParties([fixtureParty('c1', balance: 50)], [walkIn], PartyType.customer).single.balanceOwed,
        50,
      );
    });
  });

  group('the form', () {
    testWidgets('a walk-in cash sale: products at their price, paid in full, then Print invoice', (tester) async {
      final rig = await _pump(tester, _saleOpener());
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await _addProduct(tester, 'Sugar · SKU-2');
      await _addProduct(tester, 'Rice · SKU-1');
      // Rice 2 × 150 + Sugar 1 × 80
      expect(find.text('Total ₦380'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('sale-paid'))).controller!.text, '380');

      await _complete(tester);
      final sent = rig.sales.created.single;
      expect(sent.input.customerId, isNull);
      expect(sent.input.warehouseId, 'w1');
      expect(sent.input.lines.map((l) => (l.productId, l.quantity, l.unitPrice)), [('1', 2, 150.0), ('2', 1, 80.0)]);
      expect(sent.input.amountPaid, 380);
      expect(sent.input.paymentMethod, SalePaymentMethod.cash);
      expect(sent.clientRef, isNotNull, reason: 'so a retry is never recorded twice');
      expect(find.textContaining('INV-0001 completed'), findsOneWidget);
      expect(find.text('Print invoice'), findsOneWidget);
    });

    testWidgets('a walk-in must pay in full', (tester) async {
      final rig = await _pump(tester, _saleOpener());
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.enterText(find.byKey(const Key('sale-paid')), '100');
      await _complete(tester);
      expect(find.byKey(const Key('sale-error')), findsOneWidget);
      expect(find.textContaining('must be paid in full'), findsOneWidget);
      expect(rig.sales.created, isEmpty);
    });

    testWidgets('a customer can buy on credit within their limit', (tester) async {
      final rig = await _pump(tester, _saleOpener(customerId: 'c2'));
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.enterText(find.byKey(const Key('sale-paid')), '50');
      await _settle(tester);
      expect(find.textContaining('On credit ₦100 · due'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sale-method')));
      await _settle(tester);
      await tester.tap(find.text('Bank transfer').last);
      await _settle(tester);
      await _complete(tester);
      final sent = rig.sales.created.single.input;
      expect(sent.customerId, 'c2');
      expect(sent.amountPaid, 50);
      expect(sent.paymentMethod, SalePaymentMethod.transfer);
      expect(find.textContaining('on credit'), findsOneWidget);
    });

    testWidgets('over the credit limit: the Owner can allow it, and it is sent as allowed', (tester) async {
      final rig = await _pump(tester, _saleOpener(customerId: 'c1'));
      await _open(tester);
      expect(find.text('Owes ₦400 · credit left ₦100'), findsOneWidget);
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.enterText(find.byKey(const Key('sale-paid')), '0');
      await _settle(tester);
      expect(find.byKey(const Key('sale-over-limit')), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('sale-complete'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('sale-allow-over-limit')));
      await _settle(tester);
      await _complete(tester);
      expect(rig.sales.created.single.input.allowOverLimit, isTrue);
    });

    testWidgets('Sales Staff: no override, no price change and no discount', (tester) async {
      final rig = await _pump(tester, _saleOpener(customerId: 'c1'), rig: _Rig(role: 'Sales Staff'));
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      expect(tester.widget<TextFormField>(find.byKey(const ValueKey('sale-price-1'))).enabled, isFalse);
      expect(find.byKey(const Key('sale-discount')), findsNothing);

      await tester.enterText(find.byKey(const Key('sale-paid')), '0');
      await _settle(tester);
      expect(find.byKey(const Key('sale-over-limit')), findsOneWidget);
      expect(find.byKey(const Key('sale-allow-over-limit')), findsNothing);
      expect(find.textContaining('ask an Owner or Administrator'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('sale-complete'))).onPressed, isNull);

      // Paying enough brings it within the limit.
      await tester.enterText(find.byKey(const Key('sale-paid')), '50');
      await _settle(tester);
      expect(find.byKey(const Key('sale-over-limit')), findsNothing);
      await _complete(tester);
      expect(rig.sales.created.single.input.allowOverLimit, isFalse);
    });

    testWidgets('the Owner can sell at another price and give a discount', (tester) async {
      final rig = await _pump(tester, _saleOpener());
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.enterText(find.byKey(const ValueKey('sale-price-1')), '140');
      await tester.enterText(find.byKey(const Key('sale-discount')), '10');
      await _settle(tester);
      expect(find.text('Total ₦130'), findsOneWidget);
      await _complete(tester);
      final sent = rig.sales.created.single.input;
      expect(sent.lines.single.unitPrice, 140);
      expect(sent.discount, 10);
      expect(sent.amountPaid, 130, reason: 'paid follows the total until it is typed in');
    });

    testWidgets('a quantity above what the warehouse holds is refused, and empty products are not offered', (
      tester,
    ) async {
      final rig = await _pump(tester, _saleOpener());
      await _open(tester);
      await tester.tap(find.byType(DropdownMenu<String>));
      await _settle(tester);
      final salt = tester.widget<MenuItemButton>(
        find.ancestor(of: find.text('Salt · SKU-3').last, matching: find.byType(MenuItemButton)),
      );
      expect(salt.onPressed, isNull, reason: 'none in this warehouse');
      await tester.tap(find.text('Sugar · SKU-2').last);
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('sale-qty-2')), '3');
      await _complete(tester);
      expect(find.text('Only 2'), findsOneWidget);
      expect(rig.sales.created, isEmpty);
    });

    testWidgets('a server refusal is shown in the form', (tester) async {
      final rig = _Rig();
      rig.sales.writeError = ApiException(409, 'Only 1 Rice left in Main Warehouse.', code: 'insufficient_stock');
      await _pump(tester, _saleOpener(), rig: rig);
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await _complete(tester);
      expect(find.textContaining('Only 1 Rice left'), findsOneWidget);
    });

    testWidgets('stock alerts from the sale are mentioned', (tester) async {
      final rig = _Rig();
      rig.sales.alerts = [(productId: '2', alert: 'low')];
      await _pump(tester, _saleOpener(), rig: rig);
      await _open(tester);
      await _addProduct(tester, 'Sugar · SKU-2');
      await _complete(tester);
      expect(find.textContaining('1 product now low or out of stock'), findsOneWidget);
    });

    testWidgets('lays out without overflow at 1024×760', (tester) async {
      await _pump(tester, _saleOpener(customerId: 'c1'), size: const Size(1024, 760));
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.enterText(find.byKey(const Key('sale-paid')), '0');
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('the list', () {
    final old = DateTime(2025, 3, 1, 10);

    testWidgets("shows today's sales by default, then other periods and filters", (tester) async {
      await _pump(
        tester,
        const SalesScreen(),
        rig: _Rig(
          sales: [
            fixtureSale('a', reference: 'INV-0003'),
            fixtureSale('b', reference: 'INV-0002', amountPaid: 100),
            fixtureSale('c', reference: 'INV-0001', saleDate: old),
            fixtureSale('d', reference: 'INV-0004', status: SaleStatus.voided),
          ],
        ),
      );
      expect(find.text('INV-0003'), findsOneWidget);
      expect(find.text('INV-0001'), findsNothing);
      // Sold today: 300 + 300, the voided one not counted.
      expect(
        find.descendant(of: find.byKey(const Key('sales-stat-today')), matching: find.text('₦600')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const Key('sales-stat-owed')), matching: find.text('₦200')),
        findsOneWidget,
      );

      await tester.tap(find.text('Unpaid'));
      await _settle(tester);
      expect(find.text('INV-0002'), findsOneWidget);
      expect(find.text('INV-0003'), findsNothing);

      await tester.tap(find.text('Voided').first);
      await _settle(tester);
      expect(find.text('INV-0004'), findsOneWidget);

      await tester.tap(find.text('All').first);
      await tester.tap(find.text('All').last);
      await _settle(tester);
      expect(find.text('INV-0001'), findsOneWidget);
      expect(find.byKey(const Key('sales-shown-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a sale waiting to sync is listed as such', (tester) async {
      final store = MemoryLocalStore();
      store.data['u_u1_outbox'] = jsonEncode([
        _queued(const SaleInput(
          customerId: 'c2',
          warehouseId: 'w1',
          lines: [SaleLineInput(productId: '1', quantity: 3, unitPrice: 150)],
          amountPaid: 450,
        )).toJson(),
      ]);
      await _pump(tester, const SalesScreen(), rig: _Rig(store: store));
      expect(find.text('Waiting to sync'), findsOneWidget);
      expect(find.text('Bello Mart'), findsWidgets);
      expect(find.text('₦450'), findsOneWidget);
    });

    testWidgets('the Accountant sees sales but cannot record one', (tester) async {
      await _pump(tester, const SalesScreen(), rig: _Rig(role: 'Accountant / Finance', sales: [fixtureSale('a')]));
      expect(find.text('INV-0001'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('sales-new'))).onPressed, isNull);
    });
  });

  group('the detail', () {
    testWidgets('an unpaid sale offers payment and void to the Owner', (tester) async {
      await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        rig: _Rig(sales: [fixtureSale('a', amountPaid: 100)]),
      );
      await _open(tester);
      for (final key in ['sale-pay', 'sale-void', 'print-invoice']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('Sales Staff can print but not take later payments or void', (tester) async {
      await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        rig: _Rig(role: 'Sales Staff', sales: [fixtureSale('a', amountPaid: 100)]),
      );
      await _open(tester);
      expect(find.byKey(const Key('print-invoice')), findsOneWidget);
      expect(find.byKey(const Key('sale-pay')), findsNothing);
      expect(find.byKey(const Key('sale-void')), findsNothing);
    });

    testWidgets('a voided sale says so and offers neither', (tester) async {
      await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        rig: _Rig(sales: [fixtureSale('a', status: SaleStatus.voided, amountPaid: 0)]),
      );
      await _open(tester);
      expect(find.byKey(const Key('sale-voided-note')), findsOneWidget);
      expect(find.byKey(const Key('sale-pay')), findsNothing);
      expect(find.byKey(const Key('sale-void')), findsNothing);
    });

    testWidgets("paying can't exceed what is still due", (tester) async {
      final rig = await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        rig: _Rig(sales: [fixtureSale('a', amountPaid: 100)]),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('sale-pay')));
      await _settle(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('sale-payment-amount'))).controller!.text, '200');
      await tester.enterText(find.byKey(const Key('sale-payment-amount')), '201');
      await tester.tap(find.byKey(const Key('sale-payment-confirm')));
      await _settle(tester);
      expect(find.byKey(const Key('sale-payment-error')), findsOneWidget);
      expect(rig.sales.paid, isEmpty);
      await tester.enterText(find.byKey(const Key('sale-payment-amount')), '150');
      await tester.tap(find.byKey(const Key('sale-payment-confirm')));
      await _settle(tester);
      expect(rig.sales.paid.single.amount, 150);
      expect(find.textContaining('₦150 received on INV-0001'), findsOneWidget);
    });

    testWidgets('voiding needs a reason and mentions the refund', (tester) async {
      final rig = await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        rig: _Rig(sales: [fixtureSale('a', amountPaid: 300)]),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('sale-void')));
      await _settle(tester);
      expect(find.textContaining('first settles their other invoices'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('void-confirm'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('void-reason')), 'Entered twice');
      await _settle(tester);
      await tester.tap(find.byKey(const Key('void-confirm')));
      await _settle(tester);
      expect(rig.sales.voided.single, (id: 'a', reason: 'Entered twice'));
      expect(find.textContaining('Refund ₦300'), findsOneWidget);
    });
  });

  testWidgets("a customer's history lists their sales, with New sale and Statement", (tester) async {
    await _pump(
      tester,
      _opener(PartyHistoryDialog(party: fixtureParty('c1', name: 'Ada Stores'))),
      rig: _Rig(
        sales: [
          fixtureSale('a', reference: 'INV-0001', customerId: 'c1'),
          fixtureSale('b', reference: 'INV-0002', customerId: 'c2'),
        ],
      ),
    );
    await _open(tester);
    expect(find.byKey(const Key('customer-sales')), findsOneWidget);
    expect(find.text('Sales (1)'), findsOneWidget);
    expect(find.text('INV-0001'), findsOneWidget);
    expect(find.text('INV-0002'), findsNothing);
    expect(find.byKey(const Key('customer-new-sale')), findsOneWidget);
    expect(find.byKey(const Key('supplier-statement')), findsOneWidget);
  });

  test('salesProvider asks the server only with sales.view', () async {
    final repo = FakeSalesRepository([fixtureSale('a')]);
    for (final (perms, expected) in [
      (asGranted(['sales.view']), 1),
      (asGranted(['products.view']), 0),
    ]) {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _Auth('Owner', perms)),
          ...fakeDataOverrides(sales: repo),
        ],
      );
      await container.read(authControllerProvider.future);
      final list = await container.read(salesProvider.future);
      expect(list.length, expected);
      container.dispose();
    }
  });
}
