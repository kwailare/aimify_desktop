// Printable documents (PDF): purchase order, goods received note, payment
// receipt, invoice, sale receipt and customer/supplier statement — the figures they show, that each builds
// a real PDF with a font that has the naira sign, and that the buttons
// open the right document.


import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/documents/document_data.dart';
import 'package:aimify_desktop/features/documents/document_kit.dart';
import 'package:aimify_desktop/features/documents/document_preview.dart';
import 'package:aimify_desktop/features/documents/purchase_documents.dart';
import 'package:aimify_desktop/features/documents/sale_documents.dart';
import 'package:aimify_desktop/features/documents/statement_dialog.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/purchases/presentation/purchase_detail_dialog.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/features/sales/presentation/sale_detail_dialog.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

const _org = Organization(
  id: 'o1',
  name: 'Obi Distribution Ltd',
  industry: 'Wholesale',
  currency: 'NGN',
  warehouseName: 'Main Warehouse',
  subscriptionStatus: 'trial',
  address: '12 Marina Road, Lagos',
  phone: '+2348000000000',
  registrationNumber: 'RC 1234567',
  taxName: 'VAT',
  taxRate: 7.5,
);

Purchase _purchase({String status = 'partially_received'}) => Purchase.fromJson({
      'id': 'p1', 'reference': 'PO-0002', 'supplierId': 's1', 'supplierName': 'Dangote Foods',
      'warehouseId': 'w1', 'warehouseName': 'Main Warehouse', 'status': status,
      'orderDate': '2026-10-18T00:00:00.000Z', 'expectedDate': '2026-10-28T00:00:00.000Z', 'notes': 'Monthly restock',
      'subtotal': 804000, 'discount': 4000, 'tax': 0, 'total': 800000, 'amountPaid': 500000,
      'postedAt': '2026-10-19T09:00:00.000Z',
      'lines': [
        {'id': 'l1', 'productId': 'rice', 'productName': 'Rice 50kg', 'sku': 'RICE-50', 'unit': 'bag', 'quantity': 10, 'unitCost': 62000, 'receivedQuantity': 10},
        {'id': 'l2', 'productId': 'semo', 'productName': 'Semovita 10kg', 'sku': 'SEMO-10', 'unit': 'bag', 'quantity': 20, 'unitCost': 9200, 'receivedQuantity': 5},
      ],
      'receipts': [
        {'id': 'r1', 'createdAt': '2026-10-19T09:00:00.000Z', 'userName': 'Ada', 'lines': [{'productId': 'rice', 'quantity': 4}]},
        {'id': 'r2', 'createdAt': '2026-10-21T15:00:00.000Z', 'userName': 'Tunde', 'lines': [{'productId': 'rice', 'quantity': 6}, {'productId': 'semo', 'quantity': 5}]},
      ],
      'payments': [
        {'id': 'pay1', 'amount': 300000, 'note': 'Paid when the purchase was recorded', 'createdAt': '2026-10-18T10:00:00.000Z', 'userName': 'Ada'},
        {'id': 'pay2', 'amount': 200000, 'note': 'Bank transfer', 'createdAt': '2026-10-22T10:00:00.000Z', 'userName': 'Ada'},
      ],
    });

Sale _sale({String status = 'completed', String? customerId = 'c1'}) => Sale.fromJson({
      'id': 'sa1', 'reference': 'INV-0012', 'customerId': customerId,
      'customerName': customerId == null ? 'Walk-in customer' : 'Ada Stores',
      'warehouseId': 'w1', 'warehouseName': 'Main Warehouse', 'status': status,
      'saleDate': '2026-10-24T11:30:00.000Z', 'notes': 'Deliver Monday',
      'subtotal': 160000, 'discount': 5000, 'tax': 11625, 'total': 166625, 'amountPaid': 100000,
      'voidReason': status == 'voided' ? 'Entered twice' : null, 'createdByName': 'Tunde',
      'lines': [
        {'id': 'l1', 'productId': 'rice', 'productName': 'Rice 50kg', 'sku': 'RICE-50', 'unit': 'bag', 'quantity': 2, 'unitPrice': 70000, 'listPrice': 75000},
        {'id': 'l2', 'productId': 'semo', 'productName': 'Semovita 10kg', 'sku': 'SEMO-10', 'unit': 'bag', 'quantity': 2, 'unitPrice': 10000, 'listPrice': 10000},
      ],
      'payments': [
        {'id': 'sp1', 'amount': 60000, 'method': 'cash', 'createdAt': '2026-10-24T11:30:00.000Z', 'userName': 'Tunde'},
        {'id': 'sp2', 'amount': 40000, 'method': 'transfer', 'note': 'GTB', 'createdAt': '2026-10-25T09:00:00.000Z', 'userName': 'Ada'},
      ],
    });

CreditEntry _entry(String id, double amount, DateTime at, {CreditKind kind = CreditKind.charge, String? note}) => CreditEntry(
      id: id,
      partyType: PartyType.supplier,
      partyId: 's1',
      kind: kind,
      amount: amount,
      note: note,
      createdAt: at,
    );

bool _isPdf(Uint8List bytes) => String.fromCharCodes(bytes.take(5)) == '%PDF-';

class _Auth extends AuthController {
  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: _org,
        role: 'Owner',
        permissions: defaultPermissionsFor('Owner'),
      );
}

/// Records what was opened, and builds it, so a broken document fails the
/// test, without needing a print engine.
class _FakeOpener implements DocumentOpener {
  final List<({String title, String fileName, Uint8List bytes})> opened = [];

  @override
  Future<void> open(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String fileName,
    required DocumentBuilder build,
  }) async {
    final bytes = await build(await DocumentKit.load(_org));
    opened.add((title: title, fileName: fileName, bytes: bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('figures', () {
    test('a goods received note shows that delivery and what has arrived so far', () {
      final p = _purchase();
      final first = goodsReceivedLines(p, 0);
      expect(first.map((l) => (l.productName, l.receivedNow, l.receivedToDate, l.outstandingAfter)), [
        ('Rice 50kg', 4, 4, 6),
      ]);
      final second = goodsReceivedLines(p, 1);
      expect(second.map((l) => (l.productName, l.ordered, l.receivedNow, l.receivedToDate, l.outstandingAfter)), [
        ('Rice 50kg', 10, 6, 10, 0),
        ('Semovita 10kg', 20, 5, 5, 15),
      ]);
    });

    test('a payment receipt shows paid to date and the balance after that payment', () {
      final p = _purchase();
      expect(paymentStanding(p, 0), (paidToDate: 300000.0, balanceAfter: 500000.0));
      expect(paymentStanding(p, 1), (paidToDate: 500000.0, balanceAfter: 300000.0));
    });

    test('a statement runs the balance from the opening balance, in date order', () {
      final s = buildStatement(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 11, 1),
        openingBalance: 100000,
        entries: [
          _entry('b', -150000, DateTime(2026, 10, 20), kind: CreditKind.payment),
          _entry('a', 800000, DateTime(2026, 10, 19), note: 'Purchase PO-0002'),
          _entry('c', -20000, DateTime(2026, 10, 25), kind: CreditKind.adjustment),
        ],
      );
      expect(s.rows.map((r) => (r.entry.id, r.balance)), [('a', 900000.0), ('b', 750000.0), ('c', 730000.0)]);
      expect(s.totalCharges, 800000);
      expect(s.totalCredits, 170000);
      expect(s.closingBalance, 730000);
      expect(buildStatement(from: null, to: DateTime(2026), openingBalance: 5, entries: const []).closingBalance, 5);
    });

    test('a sale receipt shows paid to date and the balance after that payment', () {
      final s = _sale();
      expect(salePaymentStanding(s, 0), (paidToDate: 60000.0, balanceAfter: 106625.0));
      expect(salePaymentStanding(s, 1), (paidToDate: 100000.0, balanceAfter: 66625.0));
      expect(s.lines.first.discounted, isTrue);
      expect(s.lines.last.discounted, isFalse);
    });

    test('statement periods, including across a new year', () {
      final jan = DateTime(2026, 1, 15, 9);
      final last = StatementPeriod.lastMonth.range(jan);
      expect(last.from, DateTime(2025, 12));
      expect(last.to, DateTime(2026, 1));
      expect(StatementPeriod.last3Months.range(jan).from, DateTime(2025, 11));
      expect(StatementPeriod.allTime.range(jan).from, isNull);
      final custom = StatementPeriod.custom.range(
        jan,
        custom: DateTimeRange(start: DateTime(2026, 1, 3), end: DateTime(2026, 1, 10)),
      );
      expect(custom.to, DateTime(2026, 1, 11), reason: 'the last day is included');
    });
  });

  group('PDFs', () {
    test('the bundled font has the naira sign', () async {
      final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      expect(TtfParser(data).charToGlyphIndexMap.containsKey(0x20A6), isTrue);
    });

    test('every document builds, including drafts and empty statements', () async {
      final kit = await DocumentKit.load(_org);
      final p = _purchase();
      final supplier = fixtureParty('s1', type: PartyType.supplier, name: 'Dangote Foods');
      for (final bytes in [
        await buildPurchaseOrder(kit, p, supplier: supplier),
        await buildPurchaseOrder(kit, _purchase(status: 'draft')),
        await buildPurchaseOrder(kit, _purchase(status: 'cancelled')),
        await buildGoodsReceivedNote(kit, p, 1, supplier: supplier),
        await buildPaymentReceipt(kit, p, 1, supplier: supplier),
        await buildInvoice(kit, _sale(), customer: fixtureParty('c1', name: 'Ada Stores')),
        await buildInvoice(kit, _sale(status: 'voided')),
        await buildInvoice(kit, _sale(customerId: null)),
        await buildSaleReceipt(kit, _sale(), 1, customer: fixtureParty('c1', name: 'Ada Stores')),
        await buildPartyStatement(
          kit,
          fixtureParty('c1', name: 'Ada Stores'),
          buildStatement(
            from: DateTime(2026, 10),
            to: DateTime(2026, 11),
            openingBalance: 5000,
            entries: [_entry('c', 166625, DateTime(2026, 10, 24), note: 'Sale INV-0012')],
          ),
        ),
        await buildPartyStatement(
          kit,
          supplier,
          buildStatement(from: DateTime(2026, 10), to: DateTime(2026, 11), openingBalance: 0, entries: const []),
        ),
      ]) {
        expect(_isPdf(bytes), isTrue);
        expect(bytes.length, greaterThan(1000));
      }
    });

    test('a long statement runs onto more pages', () async {
      final kit = await DocumentKit.load(_org);
      final entries = [
        for (var i = 0; i < 120; i++) _entry('e$i', i.isEven ? 1000 : -500, DateTime(2026, 10, 1).add(Duration(hours: i))),
      ];
      final bytes = await buildPartyStatement(
        kit,
        fixtureParty('s1', type: PartyType.supplier),
        buildStatement(from: DateTime(2026, 10), to: DateTime(2026, 11), openingBalance: 0, entries: entries),
      );
      final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
      expect(pages, greaterThan(1));
    });
  });

  group('buttons', () {
    Future<(_FakeOpener, FakePartiesRepository)> pump(WidgetTester tester, Widget dialog, {FakePartiesRepository? parties}) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opener = _FakeOpener();
      final repo = parties ?? FakePartiesRepository(suppliers: [fixtureParty('s1', type: PartyType.supplier, name: 'Dangote Foods')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_Auth.new),
            documentOpenerProvider.overrideWithValue(opener),
            ...fakeDataOverrides(
              purchases: FakePurchasesRepository([_purchase()]),
              sales: FakeSalesRepository([_sale()]),
              parties: repo,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog(context: context, builder: (_) => dialog),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.tap(find.text('open'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      return (opener, repo);
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('the purchase offers its order, each delivery and each payment as a PDF', (tester) async {
      final (opener, _) = await pump(tester, const PurchaseDetailDialog(purchaseId: 'p1'));

      await tester.tap(find.byKey(const Key('print-order')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('print-grn-1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('print-payment-0')));
      await settle(tester);

      expect(opener.opened.map((o) => o.fileName), ['PO-0002.pdf', 'PO-0002-GRN-2.pdf', 'PO-0002-PAY-1.pdf']);
      expect(opener.opened.every((o) => _isPdf(o.bytes)), isTrue);
    });

    testWidgets('the sale offers its invoice and a receipt for each payment as a PDF', (tester) async {
      final (opener, _) = await pump(
        tester,
        const SaleDetailDialog(saleId: 'sa1'),
        parties: FakePartiesRepository(customers: [fixtureParty('c1', name: 'Ada Stores')]),
      );
      await tester.tap(find.byKey(const Key('print-invoice')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('print-sale-receipt-1')));
      await settle(tester);
      expect(opener.opened.map((o) => o.fileName), ['INV-0012.pdf', 'INV-0012-RCPT-2.pdf']);
      expect(opener.opened.every((o) => _isPdf(o.bytes)), isTrue);
    });

    testWidgets('a supplier statement asks for the period and reads that period', (tester) async {
      final parties = FakePartiesRepository(suppliers: [fixtureParty('s1', type: PartyType.supplier, name: 'Dangote Foods')]);
      parties.ledger.add(_entry('a', 800000, DateTime.now().subtract(const Duration(days: 3)), note: 'Purchase PO-0002'));
      final (opener, repo) = await pump(
        tester,
        StatementDialog(party: fixtureParty('s1', type: PartyType.supplier, name: 'Dangote Foods & Sons')),
        parties: parties,
      );
      await tester.tap(find.byKey(const Key('statement-thisMonth')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('statement-generate')));
      await settle(tester);

      final now = DateTime.now();
      expect(repo.statementRequests.single.from, DateTime(now.year, now.month));
      expect(opener.opened.single.fileName, 'Statement-Dangote-Foods-Sons.pdf');
      expect(_isPdf(opener.opened.single.bytes), isTrue);
    });

    testWidgets('offline, the statement explains it needs a connection', (tester) async {
      final parties = _OfflineParties(suppliers: [fixtureParty('s1', type: PartyType.supplier)]);
      final (opener, _) = await pump(
        tester,
        StatementDialog(party: fixtureParty('s1', type: PartyType.supplier)),
        parties: parties,
      );
      await tester.tap(find.byKey(const Key('statement-generate')));
      await settle(tester);
      expect(find.byKey(const Key('statement-error')), findsOneWidget);
      expect(find.textContaining('needs a connection'), findsOneWidget);
      expect(opener.opened, isEmpty);
    });
  });
}

class _OfflineParties extends FakePartiesRepository {
  _OfflineParties({super.suppliers});

  @override
  Future<({List<CreditEntry> entries, double openingBalance})> ledgerForPeriod(
    PartyType type,
    String partyId, {
    DateTime? from,
    required DateTime to,
  }) async =>
      throw const NetworkException();
}
