// WhatsApp (feature checklist step 17): "Send on WhatsApp" opens WhatsApp
// with the message ready, to the right number. Phone numbers, the links,
// the wording, the "WhatsApp OK" tick, and the buttons on a sale (invoice,
// receipts), a purchase (the order), Who to chase and the customer's
// account (receipts).

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/credits_debts/data/debt_report.dart';
import 'package:aimify_desktop/features/credits_debts/presentation/debt_report_view.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/parties/presentation/credit_entry_row.dart';
import 'package:aimify_desktop/features/parties/presentation/party_form_dialog.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/purchases/presentation/purchase_detail_dialog.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/features/sales/presentation/sale_detail_dialog.dart';
import 'package:aimify_desktop/features/whatsapp/whatsapp_share.dart';
import 'package:aimify_desktop/shared/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

class _Auth extends AuthController {
  @override
  Future<MeResponse?> build() async => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'active',
          setupCompletedAt: DateTime(2026, 10, 1),
        ),
        role: 'Owner',
        permissions: defaultPermissionsFor('Owner'),
      );
}

const _adaPhone = '0803 111 2222';
const _adaNumber = '2348031112222';

Party _ada({double balance = 400, double overdue = 0}) => Party(
      id: 'c1',
      type: PartyType.customer,
      name: 'Ada Stores',
      phone: _adaPhone,
      balanceOwed: balance,
      overdue: overdue,
      whatsappOptIn: true,
    );

const _dangote = Party(id: 's1', type: PartyType.supplier, name: 'Dangote Foods', phone: '+234 801 555 0000');

class _Opened {
  final uris = <Uri>[];
  bool works = true;
  Future<bool> call(Uri uri) async {
    uris.add(uri);
    return works;
  }

  String get text => uris.last.queryParameters['text'] ?? '';
}

Future<_Opened> _pump(
  WidgetTester tester,
  Widget home, {
  List<Sale> sales = const [],
  List<Purchase> purchases = const [],
  List<Party>? customers,
  FakeDebtReportRepository? debts,
  FakePartiesRepository? parties,
}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final opened = _Opened();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        urlOpenerProvider.overrideWithValue(opened.call),
        ...fakeDataOverrides(
          sales: FakeSalesRepository(sales),
          purchases: FakePurchasesRepository(purchases),
          parties: parties ?? FakePartiesRepository(customers: customers ?? [_ada()], suppliers: [_dangote]),
          debts: debts,
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: home)),
    ),
  );
  await _settle(tester);
  return opened;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Widget _opener(Widget dialog) => Builder(
      builder: (context) => Center(
        child: ElevatedButton(onPressed: () => showDialog(context: context, builder: (_) => dialog), child: const Text('open')),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await _settle(tester);
}

void main() {
  group('phone numbers', () {
    test('as WhatsApp wants them', () {
      expect(toWhatsAppNumber('0803 111 2222'), '2348031112222');
      expect(toWhatsAppNumber('+234 803 111 2222'), '2348031112222');
      expect(toWhatsAppNumber('234-803-111-2222'), '2348031112222');
      expect(toWhatsAppNumber('803 111 2222'), '2348031112222');
      expect(toWhatsAppNumber('00234 803 111 2222'), '2348031112222');
      expect(toWhatsAppNumber('+44 7700 900123'), '447700900123');
      expect(toWhatsAppNumber('0700'), isNull);
      expect(toWhatsAppNumber(''), isNull);
      expect(toWhatsAppNumber(null), isNull);
    });

    test('the link to WhatsApp, with the text', () {
      final uri = whatsAppUri('0803 111 2222', 'Hello & thanks: ₦1,000');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/2348031112222');
      expect(uri.queryParameters['text'], 'Hello & thanks: ₦1,000');
      expect(whatsAppUri(null, 'Hi').path, '/');
    });
  });

  group('the wording', () {
    test('an invoice lists the goods and what is still due', () {
      final sale = fixtureSale('a', customerName: 'Ada Stores', amountPaid: 100);
      final text = invoiceWhatsAppText(sale, business: 'Obi Ltd');
      expect(text, startsWith('Hello Ada Stores,\nThank you for buying from Obi Ltd. Invoice INV-0001'));
      expect(text, contains('• 2 ${sale.lines.first.unit} ${sale.lines.first.productName} @ ${currencyFormat.format(150)}'));
      expect(text, contains('Total: ${currencyFormat.format(300)}'));
      expect(text, contains('Paid: ${currencyFormat.format(100)}'));
      expect(text, contains('Balance: ${currencyFormat.format(200)}'));
      expect(invoiceWhatsAppText(fixtureSale('b'), business: 'X'), isNot(contains('Balance')));
    });

    test('a purchase order, a receipt and a reminder', () {
      final order = purchaseOrderWhatsAppText(fixturePurchase('p'), business: 'Obi Ltd');
      expect(order, contains('Obi Ltd would like to order (purchase order PO-0001):'));
      expect(order, contains('Total: ${currencyFormat.format(1000)}'));
      expect(order, contains('Deliver to: Main Warehouse'));
      expect(
        receiptWhatsAppText(customer: 'Ada', business: 'Obi Ltd', amount: 500, reference: 'RCPT-0001', balance: -20),
        'Hello Ada,\nObi Ltd received your payment of ${currencyFormat.format(500)} (RCPT-0001). Your balance is now ${currencyFormat.format(0)}. Thank you.',
      );
      expect(
        reminderWhatsAppText(customer: 'Ada', business: 'Obi Ltd', overdue: 9000, balance: 12000),
        contains('${currencyFormat.format(9000)} is overdue on your account (your balance is ${currencyFormat.format(12000)})'),
      );
    });
  });

  group('the WhatsApp OK tick', () {
    test('is read and sent', () {
      expect(Party.fromJson(PartyType.customer, {'id': 'c', 'name': 'A', 'whatsappOptIn': true}).whatsappOptIn, isTrue);
      expect(Party.fromJson(PartyType.customer, {'id': 'c', 'name': 'A'}).whatsappOptIn, isFalse);
      expect(const PartyInput(type: PartyType.supplier, name: 'S', whatsappOptIn: true).toJson()['whatsappOptIn'], isTrue);
      expect(PartyInput.fromJson(PartyType.customer, {'name': 'A', 'whatsappOptIn': true}).whatsappOptIn, isTrue);
    });

    testWidgets('is on the customer form and saved', (tester) async {
      final parties = FakePartiesRepository();
      await _pump(tester, _opener(const PartyFormDialog(type: PartyType.customer)), parties: parties);
      await _open(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Chi Foods');
      await tester.tap(find.byKey(const Key('party-whatsapp-ok')));
      await _settle(tester);
      await tester.tap(find.text('Add customer').last);
      await _settle(tester);
      expect(parties.created.single.whatsappOptIn, isTrue);
    });

    testWidgets('an existing supplier keeps theirs', (tester) async {
      await _pump(tester, _opener(const PartyFormDialog(type: PartyType.supplier, party: _dangote)));
      await _open(tester);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('party-whatsapp-ok'))).value, isFalse);
      expect(find.textContaining('purchase orders on WhatsApp'), findsOneWidget);
    });
  });

  group('Send on WhatsApp', () {
    testWidgets('a sale: the invoice, to the customer', (tester) async {
      final opened = await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        sales: [fixtureSale('a', customerName: 'Ada Stores', amountPaid: 100)],
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('whatsapp-invoice')));
      await _settle(tester);
      expect(opened.uris.single.path, '/$_adaNumber');
      expect(opened.text, contains('Invoice INV-0001'));
      expect(opened.text, contains('Obi Ltd'));
    });

    testWidgets("a sale's payment: its receipt", (tester) async {
      final opened = await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        sales: [fixtureSale('a', customerName: 'Ada Stores', amountPaid: 100)],
      );
      await _open(tester);
      await tester.tap(find.byKey(const Key('whatsapp-sale-receipt-0')));
      await _settle(tester);
      expect(opened.uris.single.path, '/$_adaNumber');
      expect(opened.text, contains('received your payment of ${currencyFormat.format(100)}'));
    });

    testWidgets('a voided sale offers no invoice', (tester) async {
      await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        sales: [fixtureSale('a', status: SaleStatus.voided, amountPaid: 0)],
      );
      await _open(tester);
      expect(find.byKey(const Key('whatsapp-invoice')), findsNothing);
    });

    testWidgets('a purchase: the order, to the supplier, until it arrives', (tester) async {
      final opened = await _pump(tester, _opener(const PurchaseDetailDialog(purchaseId: 'p')), purchases: [fixturePurchase('p')]);
      await _open(tester);
      await tester.tap(find.byKey(const Key('whatsapp-order')));
      await _settle(tester);
      expect(opened.uris.single.path, '/2348015550000');
      expect(opened.text, contains('purchase order PO-0001'));
    });

    testWidgets('a received purchase offers no order', (tester) async {
      await _pump(
        tester,
        _opener(const PurchaseDetailDialog(purchaseId: 'p')),
        purchases: [fixturePurchase('p', status: PurchaseStatus.received)],
      );
      await _open(tester);
      expect(find.byKey(const Key('whatsapp-order')), findsNothing);
    });

    testWidgets('who to chase: a reminder', (tester) async {
      final report = DebtReport.fromJson({
        'asOf': '2026-11-09T09:00:00.000Z',
        'partyType': 'customer',
        'totals': {'balance': 12000, 'overdue': 9000, 'credit': 0},
        'parties': [
          {
            'id': 'c1', 'name': 'Ada Stores', 'phone': _adaPhone, 'status': 'active', 'balance': 12000,
            'paymentTermsDays': 14, 'buckets': {'over90': 9000, 'current': 3000}, 'overdue': 9000,
            'maxDaysOverdue': 100, 'items': [],
          },
        ],
      });
      final opened = await _pump(tester, const WhoToChaseView(), debts: FakeDebtReportRepository(customers: report));
      await tester.tap(find.byKey(const ValueKey('chase-whatsapp-c1')));
      await _settle(tester);
      expect(opened.uris.single.path, '/$_adaNumber');
      expect(opened.text, contains('${currencyFormat.format(9000)} is overdue'));
    });

    testWidgets("a payment on the customer's account: its receipt", (tester) async {
      final entry = CreditEntry.fromJson({
        'id': 'p1', 'partyType': 'customer', 'partyId': 'c1', 'kind': 'payment', 'amount': -7000,
        'method': 'transfer', 'receiptNumber': 'RCPT-0003', 'openAmount': 0, 'createdAt': '2026-11-08T10:00:00.000Z',
      });
      final opened = await _pump(
        tester,
        Consumer(builder: (context, ref, _) => CreditEntryRow(entry: entry, myId: 'u1', theme: Theme.of(context), party: _ada(balance: 5000))),
      );
      await tester.tap(find.byKey(const ValueKey('whatsapp-receipt-p1')));
      await _settle(tester);
      expect(opened.uris.single.path, '/$_adaNumber');
      expect(opened.text, contains('${currencyFormat.format(7000)} (RCPT-0003)'));
      expect(opened.text, contains('balance is now ${currencyFormat.format(5000)}'));
    });

    testWidgets("if WhatsApp can't open, it says so", (tester) async {
      final opened = await _pump(
        tester,
        _opener(const SaleDetailDialog(saleId: 'a')),
        sales: [fixtureSale('a', customerName: 'Ada Stores', amountPaid: 100)],
      );
      opened.works = false;
      await _open(tester);
      await tester.tap(find.byKey(const Key('whatsapp-invoice')));
      await _settle(tester);
      expect(find.textContaining("Couldn't open WhatsApp"), findsOneWidget);
    });
  });
}
