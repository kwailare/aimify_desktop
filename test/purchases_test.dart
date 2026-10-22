// Purchases on the server (feature checklist step 7): parsing, the form
// (supplier, warehouse, product lines, totals, draft / order / received
// now), the list and its offline rows, the detail actions per status and
// role, receiving part of a delivery, paying, cancelling, importing
// purchases saved on this computer by older versions, and the offline
// overlays.

import 'dart:convert';

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/data/outbox_overlay.dart';
import 'package:aimify_desktop/features/parties/data/party_overlay.dart';
import 'package:aimify_desktop/features/parties/data/supplier_options.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/purchases/data/purchases_repository.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/purchases/presentation/import_legacy_purchases_dialog.dart';
import 'package:aimify_desktop/features/purchases/presentation/purchase_detail_dialog.dart';
import 'package:aimify_desktop/features/purchases/presentation/purchase_form_dialog.dart';
import 'package:aimify_desktop/features/purchases/presentation/purchases_screen.dart';
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
  _Rig({this.role = 'Owner', List<String>? permissions, List<Purchase>? purchases, this.store})
    : permissions = permissions ?? defaultPermissionsFor(role),
      purchases = FakePurchasesRepository(purchases);

  final String role;
  final List<String> permissions;
  final FakePurchasesRepository purchases;
  final MemoryLocalStore? store;
}

Future<_Rig> _pump(
  WidgetTester tester,
  Widget home, {
  _Rig? rig,
  Size size = const Size(1400, 1000),
}) async {
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
          purchases: r.purchases,
          store: r.store,
          products: FakeProductsRepository([
            fixtureProduct('1', name: 'Rice', cost: 100),
            fixtureProduct('2', name: 'Sugar', cost: 50),
          ]),
          supplierOptions: FakeSupplierOptionsRepository(const [
            SupplierOption(id: 's1', name: 'Dangote Foods'),
            SupplierOption(id: 's2', name: 'Old Mills', isArchived: true),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: home),
      ),
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

/// Opens [dialog] from a button, like the screens do.
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

void main() {
  group('models', () {
    test('a purchase parses from the API, with statuses, lines, receipts and payments', () {
      final p = Purchase.fromJson({
        'id': 'p1',
        'reference': 'PO-0007',
        'supplierId': 's1',
        'supplierName': 'Dangote',
        'warehouseId': 'w1',
        'warehouseName': 'Lagos',
        'status': 'partially_received',
        'orderDate': '2026-10-20T00:00:00.000Z',
        'expectedDate': null,
        'notes': 'x',
        'subtotal': 660000,
        'discount': 10000,
        'tax': 5000,
        'total': 655000,
        'amountPaid': 100000,
        'postedAt': '2026-10-21T00:00:00.000Z',
        'lines': [
          {
            'id': 'l1',
            'productId': 'p',
            'productName': 'Rice',
            'sku': 'R',
            'unit': 'bag',
            'quantity': 10,
            'unitCost': 62000,
            'receivedQuantity': 4,
          },
        ],
        'receipts': [
          {
            'id': 'r1',
            'createdAt': '2026-10-21T10:00:00.000Z',
            'userName': 'Ada',
            'lines': [
              {'productId': 'p', 'quantity': 4},
            ],
          },
        ],
        'payments': [
          {
            'id': 'pay1',
            'amount': 100000,
            'note': null,
            'createdAt': '2026-10-20T10:00:00.000Z',
            'userName': 'Ada',
          },
        ],
      });
      expect(p.status, PurchaseStatus.partiallyReceived);
      expect(p.status.label, 'Partly received');
      expect(p.balance, 555000);
      expect(p.lines.single.outstanding, 6);
      expect(p.receipts.single.lines.single.quantity, 4);
      expect(p.payments.single.amount, 100000);
      expect(p.canEdit, isFalse, reason: 'something was received');
      expect(p.status.canReceive, isTrue);
    });

    test('the purchase input round-trips through the offline queue, and resolves offline ids', () {
      final input = PurchaseInput(
        supplierId: 'local:s',
        warehouseId: 'w1',
        lines: const [PurchaseLineInput(productId: 'local:p', quantity: 3, unitCost: 10)],
        placeOrder: true,
        orderDate: DateTime(2026, 10, 22),
        discount: 5,
        tax: 2,
        amountPaid: 7,
        receive: true,
      );
      final back = PurchaseInput.fromJson(
        jsonDecode(jsonEncode(input.toJson())) as Map<String, dynamic>,
      );
      expect(back.total, 27);
      expect(back.receive, isTrue);
      expect(back.toJson()['status'], 'pending');
      expect(back.toJson()['orderDate'], '2026-10-22');
      final resolved = back.resolved((id) => id.replaceFirst('local:', 'srv-'));
      expect(resolved.supplierId, 'srv-s');
      expect(resolved.lines.single.productId, 'srv-p');
    });

    test('a purchase bought and received offline moves stock and the supplier balance at once', () {
      final op = OutboxOp(
        id: 'op1',
        kind: OpKind.purchaseCreate,
        payload: {
          'input': PurchaseInput(
            supplierId: 's1',
            warehouseId: 'w1',
            lines: const [PurchaseLineInput(productId: '1', quantity: 5, unitCost: 100)],
            orderDate: DateTime(2026, 10, 22),
            amountPaid: 200,
            receive: true,
          ).toJson(),
        },
        createdAt: DateTime(2026, 10, 22),
      );
      final view = overlayOutbox([fixtureProduct('1', stock: 10)], [op]);
      expect(view.products.single.currentStock, 15);
      expect(view.products.single.stockIn('w1'), 15);

      final suppliers = overlayParties(
        [fixtureParty('s1', type: PartyType.supplier)],
        [op],
        PartyType.supplier,
      );
      expect(suppliers.single.balanceOwed, 300, reason: '500 bought, 200 paid');

      final ordered = OutboxOp(
        id: 'op2',
        kind: OpKind.purchaseCreate,
        payload: {
          'input': PurchaseInput(
            supplierId: 's1',
            warehouseId: 'w1',
            lines: const [PurchaseLineInput(productId: '1', quantity: 5, unitCost: 100)],
            orderDate: DateTime(2026, 10, 22),
          ).toJson(),
        },
        createdAt: DateTime(2026, 10, 22),
      );
      expect(
        overlayOutbox([fixtureProduct('1', stock: 10)], [ordered]).products.single.currentStock,
        10,
        reason: 'an order that has not arrived changes no stock',
      );
    });
  });

  group('the form', () {
    testWidgets('records an order: supplier, warehouse, products at their cost, totals', (
      tester,
    ) async {
      final rig = await _pump(tester, _opener(const PurchaseFormDialog(initialSupplierId: 's1')));
      await _open(tester);

      expect(find.text('Old Mills (archived)'), findsNothing);
      await _addProduct(tester, 'Rice · SKU-1');
      await _addProduct(tester, 'Sugar · SKU-2');
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.enterText(find.byKey(const ValueKey('purchase-cost-2')), '60');
      await tester.enterText(find.byKey(const Key('purchase-discount')), '20');
      await _settle(tester);
      // Rice 2 × 100 + Sugar 1 × 60 - 20
      expect(find.text('Total ₦240'), findsOneWidget);

      await tester.tap(find.byKey(const Key('purchase-place-order')));
      await _settle(tester);

      final sent = rig.purchases.created.single;
      expect(sent.input.placeOrder, isTrue);
      expect(sent.input.receive, isFalse);
      expect(sent.input.supplierId, 's1');
      expect(sent.input.warehouseId, 'w1');
      expect(sent.input.lines.map((l) => (l.productId, l.quantity, l.unitCost)), [
        ('1', 2, 100.0),
        ('2', 1, 60.0),
      ]);
      expect(sent.input.discount, 20);
      expect(sent.clientRef, isNotNull, reason: 'so a retry is never recorded twice');
      expect(find.textContaining('ordered'), findsOneWidget);
    });

    testWidgets('"Received now" receives everything straight away', (tester) async {
      final rig = await _pump(tester, _opener(const PurchaseFormDialog(initialSupplierId: 's1')));
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.tap(find.byKey(const Key('purchase-receive-now')));
      await _settle(tester);
      expect(rig.purchases.created.single.input.receive, isTrue);
      expect(find.textContaining('the stock is in'), findsOneWidget);
    });

    testWidgets('needs a product, and paid can\'t exceed the total', (tester) async {
      final rig = await _pump(tester, _opener(const PurchaseFormDialog(initialSupplierId: 's1')));
      await _open(tester);
      await tester.tap(find.byKey(const Key('purchase-save-draft')));
      await _settle(tester);
      expect(find.text('Add at least one product.'), findsOneWidget);

      await _addProduct(tester, 'Rice · SKU-1');
      await tester.enterText(find.byKey(const Key('purchase-paid')), '500');
      await tester.tap(find.byKey(const Key('purchase-save-draft')));
      await _settle(tester);
      expect(find.text("The amount paid can't be more than the total."), findsOneWidget);
      expect(rig.purchases.created, isEmpty);
    });

    testWidgets(
      'a role without credit.record has no "Paid now", and no "Received now" without receive',
      (tester) async {
        await _pump(
          tester,
          _opener(const PurchaseFormDialog()),
          rig: _Rig(permissions: asGranted(['purchases.view', 'purchases.create'])),
        );
        await _open(tester);
        expect(find.byKey(const Key('purchase-paid')), findsNothing);
        expect(find.byKey(const Key('purchase-receive-now')), findsNothing);
      },
    );

    testWidgets('a server refusal is shown in the form', (tester) async {
      final rig = _Rig();
      rig.purchases.writeError = ApiException(
        400,
        'That supplier is archived.',
        code: 'invalid_supplier',
      );
      await _pump(tester, _opener(const PurchaseFormDialog(initialSupplierId: 's1')), rig: rig);
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      await tester.tap(find.byKey(const Key('purchase-save-draft')));
      await _settle(tester);
      expect(find.textContaining('archived'), findsOneWidget);
    });

    testWidgets('lays out without overflow at 1024×760', (tester) async {
      await _pump(
        tester,
        _opener(const PurchaseFormDialog(initialSupplierId: 's1')),
        size: const Size(1024, 760),
      );
      await _open(tester);
      await _addProduct(tester, 'Rice · SKU-1');
      expect(tester.takeException(), isNull);
    });
  });

  group('the list', () {
    testWidgets('shows open purchases by default, and the other filters', (tester) async {
      await _pump(
        tester,
        const PurchasesScreen(),
        rig: _Rig(
          purchases: [
            fixturePurchase('a', reference: 'PO-0001', status: PurchaseStatus.pending),
            fixturePurchase(
              'b',
              reference: 'PO-0002',
              status: PurchaseStatus.received,
              lines: [(productId: '1', quantity: 2, unitCost: 100, received: 2)],
            ),
            fixturePurchase('c', reference: 'PO-0003', status: PurchaseStatus.cancelled),
          ],
        ),
      );
      expect(find.text('PO-0001'), findsOneWidget);
      expect(find.text('PO-0002'), findsNothing);
      await tester.tap(find.text('Received'));
      await _settle(tester);
      expect(find.text('PO-0002'), findsOneWidget);
      expect(find.text('PO-0001'), findsNothing);
      await tester.tap(find.text('All'));
      await _settle(tester);
      expect(find.text('PO-0003'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a purchase waiting to sync is listed as such', (tester) async {
      final store = MemoryLocalStore();
      store.data['u_u1_outbox'] = jsonEncode([
        OutboxOp(
          id: 'q1',
          kind: OpKind.purchaseCreate,
          payload: {
            'input': PurchaseInput(
              supplierId: 's1',
              warehouseId: 'w1',
              lines: const [PurchaseLineInput(productId: '1', quantity: 3, unitCost: 100)],
              orderDate: DateTime(2026, 10, 22),
            ).toJson(),
          },
          createdAt: DateTime(2026, 10, 22),
        ).toJson(),
      ]);
      await _pump(tester, const PurchasesScreen(), rig: _Rig(store: store));
      expect(find.text('Waiting to sync'), findsOneWidget);
      expect(find.text('₦300'), findsOneWidget);
    });

    testWidgets('purchases saved on this computer are offered for import', (tester) async {
      final store = MemoryLocalStore();
      store.data['u_u1_purchases'] = jsonEncode([
        {
          'id': 'old1',
          'supplierName': '  dangote   FOODS ',
          'date': '2026-10-05T22:02:53.000Z',
          'items': [
            {'productName': 'rice', 'quantity': 4, 'unitCost': 90},
            {'productName': 'Mystery item', 'quantity': 1, 'unitCost': 5},
          ],
          'paymentStatus': 'partial',
          'amountPaid': 100,
        },
      ]);
      final rig = await _pump(tester, const PurchasesScreen(), rig: _Rig(store: store));
      await tester.tap(find.byKey(const Key('purchases-import-legacy')));
      await _settle(tester);
      expect(find.byType(ImportLegacyPurchasesDialog), findsOneWidget);
      expect(
        find.text('Leave this line out'),
        findsWidgets,
        reason: 'the unknown product is not guessed',
      );

      await tester.tap(find.byKey(const ValueKey('legacy-import-old1')));
      await _settle(tester);
      final sent = rig.purchases.created.single;
      expect(sent.clientRef, 'legacy:old1');
      expect(sent.input.supplierId, 's1', reason: 'matched by name, ignoring case and spacing');
      expect(sent.input.lines.map((l) => (l.productId, l.quantity, l.unitCost)), [('1', 4, 90.0)]);
      expect(sent.input.placeOrder, isFalse, reason: 'imported as a draft');
      expect(sent.input.receive, isFalse);
      expect(sent.input.amountPaid, 100);
      expect(find.text('All done — nothing left to import.'), findsOneWidget);
    });

    testWidgets('roles without purchases.create see no Record or import buttons', (tester) async {
      await _pump(tester, const PurchasesScreen(), rig: _Rig(role: 'Accountant / Finance'));
      final record = tester.widget<ElevatedButton>(find.byKey(const Key('purchases-new')));
      expect(record.onPressed, isNull);
    });
  });

  group('the detail', () {
    testWidgets('an open order offers Receive, Edit, Cancel and Pay to the Owner', (tester) async {
      await _pump(
        tester,
        _opener(const PurchaseDetailDialog(purchaseId: 'a')),
        rig: _Rig(purchases: [fixturePurchase('a', status: PurchaseStatus.pending)]),
      );
      await _open(tester);
      for (final key in ['purchase-receive', 'purchase-edit', 'purchase-cancel', 'purchase-pay']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('purchase-place')), findsNothing, reason: 'already ordered');
    });

    testWidgets('a received, paid purchase offers none of them', (tester) async {
      await _pump(
        tester,
        _opener(const PurchaseDetailDialog(purchaseId: 'a')),
        rig: _Rig(
          purchases: [
            fixturePurchase(
              'a',
              status: PurchaseStatus.received,
              amountPaid: 1000,
              lines: [(productId: '1', quantity: 10, unitCost: 100, received: 10)],
            ),
          ],
        ),
      );
      await _open(tester);
      for (final key in ['purchase-receive', 'purchase-edit', 'purchase-cancel', 'purchase-pay']) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
    });

    testWidgets('the Accountant can only record a payment', (tester) async {
      await _pump(
        tester,
        _opener(const PurchaseDetailDialog(purchaseId: 'a')),
        rig: _Rig(
          role: 'Accountant / Finance',
          purchases: [fixturePurchase('a', status: PurchaseStatus.pending)],
        ),
      );
      await _open(tester);
      expect(find.byKey(const Key('purchase-pay')), findsOneWidget);
      for (final key in ['purchase-receive', 'purchase-edit', 'purchase-cancel']) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
    });

    testWidgets('receiving part of a delivery sends only what arrived', (tester) async {
      final rig = await _pump(
        tester,
        _opener(const PurchaseDetailDialog(purchaseId: 'a')),
        rig: _Rig(
          purchases: [
            fixturePurchase(
              'a',
              lines: [
                (productId: '1', quantity: 10, unitCost: 100, received: 4),
                (productId: '2', quantity: 5, unitCost: 50, received: 0),
              ],
            ),
          ],
        ),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('purchase-receive')));
      await _settle(tester);
      expect(find.textContaining('6 of 10 outstanding'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('receive-qty-a-l0')), '7');
      await tester.tap(find.byKey(const Key('receive-confirm')));
      await _settle(tester);
      expect(find.text('Product 1: enter 0 to 6.'), findsOneWidget);
      expect(rig.purchases.received, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('receive-qty-a-l0')), '6');
      await tester.enterText(find.byKey(const ValueKey('receive-qty-a-l1')), '0');
      await tester.tap(find.byKey(const Key('receive-confirm')));
      await _settle(tester);
      expect(rig.purchases.received.single.lines, {'a-l0': 6});
      expect(find.textContaining('6 units received'), findsOneWidget);
    });

    testWidgets('paying can\'t exceed what is owed', (tester) async {
      final rig = await _pump(
        tester,
        _opener(const PurchaseDetailDialog(purchaseId: 'a')),
        rig: _Rig(purchases: [fixturePurchase('a', amountPaid: 400)]),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('purchase-pay')));
      await _settle(tester);
      expect(
        tester.widget<TextField>(find.byKey(const Key('payment-amount'))).controller!.text,
        '600',
      );
      await tester.enterText(find.byKey(const Key('payment-amount')), '601');
      await tester.tap(find.byKey(const Key('payment-confirm')));
      await _settle(tester);
      expect(find.textContaining('is still owed'), findsWidgets);
      expect(rig.purchases.paid, isEmpty);
      await tester.enterText(find.byKey(const Key('payment-amount')), '250');
      await tester.tap(find.byKey(const Key('payment-confirm')));
      await _settle(tester);
      expect(rig.purchases.paid.single.amount, 250);
    });

    testWidgets('cancelling asks first, and mentions money to be paid back', (tester) async {
      final rig = await _pump(
        tester,
        _opener(const PurchaseDetailDialog(purchaseId: 'a')),
        rig: _Rig(purchases: [fixturePurchase('a', status: PurchaseStatus.draft, amountPaid: 300)]),
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('purchase-cancel')));
      await _settle(tester);
      expect(find.textContaining('owed back'), findsOneWidget);
      await tester.tap(find.byKey(const Key('purchase-confirm-cancel')));
      await _settle(tester);
      expect(rig.purchases.cancelled, ['a']);
      expect(find.textContaining('owes back ₦300'), findsOneWidget);
    });
  });

  test('purchasesProvider asks the server only with purchases.view', () async {
    final repo = FakePurchasesRepository([fixturePurchase('a')]);
    for (final (perms, expected) in [
      (asGranted(['purchases.view']), 1),
      (asGranted(['products.view']), 0),
    ]) {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _Auth('Owner', perms)),
          ...fakeDataOverrides(purchases: repo),
        ],
      );
      await container.read(authControllerProvider.future);
      final list = await container.read(purchasesProvider.future);
      expect(list.length, expected);
      container.dispose();
    }
  });
}
