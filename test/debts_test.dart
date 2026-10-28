// Credit and debt (feature checklist step 10): open amounts and due dates on
// the ledger, payments that settle the oldest invoices with a receipt, payment
// terms, the aging report and "who to chase", and their PDF and Excel.

import 'dart:typed_data';

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/credits_debts/data/debt_excel.dart';
import 'package:aimify_desktop/features/credits_debts/data/debt_report.dart';
import 'package:aimify_desktop/features/credits_debts/presentation/credits_debts_screen.dart';
import 'package:aimify_desktop/features/customers/data/customer_types.dart';
import 'package:aimify_desktop/features/documents/debt_documents.dart';
import 'package:aimify_desktop/features/documents/document_kit.dart';
import 'package:aimify_desktop/features/documents/document_preview.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/parties/presentation/credit_entry_dialog.dart';
import 'package:aimify_desktop/features/parties/presentation/party_form_dialog.dart';
import 'package:aimify_desktop/features/customers/presentation/customer_profile_screen.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/features/sales/presentation/sales_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

const _org = Organization(
  id: 'o1',
  name: 'Obi Ltd',
  industry: 'Wholesale',
  currency: 'NGN',
  warehouseName: 'Main Warehouse',
  subscriptionStatus: 'trial',
);

class _Auth extends AuthController {
  _Auth(this.role);

  final String role;

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
        permissions: defaultPermissionsFor(role),
      );
}

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
    opened.add((title: title, fileName: fileName, bytes: await build(await DocumentKit.load(_org))));
  }
}

bool _isPdf(Uint8List bytes) => String.fromCharCodes(bytes.take(5)) == '%PDF-';

DebtReport _report() => DebtReport.fromJson({
      'asOf': '2026-10-28T09:00:00.000Z',
      'partyType': 'customer',
      'totals': {
        'balance': 12500, 'overdue': 9000, 'credit': 1500,
        'current': 3500, 'days1to30': 0, 'days31to60': 4000, 'days61to90': 0, 'over90': 5000,
      },
      'parties': [
        {
          'id': 'c1', 'name': 'Ada Stores', 'phone': '0801', 'status': 'active', 'balance': 12000,
          'creditLimit': 50000, 'paymentTermsDays': 14,
          'buckets': {'current': 3000, 'days1to30': 0, 'days31to60': 4000, 'days61to90': 0, 'over90': 5000},
          'overdue': 9000, 'maxDaysOverdue': 100, 'oldestDueDate': '2026-07-20T09:00:00.000Z',
          'lastPaymentAt': '2026-09-01T09:00:00.000Z', 'daysSinceLastPayment': 57,
          'items': [
            {'reference': 'Opening balance', 'date': '2026-07-06T09:00:00.000Z', 'dueDate': '2026-07-20T09:00:00.000Z', 'amount': 5000, 'openAmount': 5000, 'daysOverdue': 100},
            {'reference': 'INV-0001', 'saleId': 's1', 'date': '2026-08-30T09:00:00.000Z', 'dueDate': '2026-09-13T09:00:00.000Z', 'amount': 5000, 'openAmount': 4000, 'daysOverdue': 45},
            {'reference': 'INV-0002', 'saleId': 's2', 'date': '2026-10-27T09:00:00.000Z', 'dueDate': '2026-11-10T09:00:00.000Z', 'amount': 3000, 'openAmount': 3000, 'daysOverdue': 0},
          ],
        },
        {
          'id': 'c2', 'name': 'Bello Mart', 'status': 'active', 'balance': 500, 'paymentTermsDays': 30,
          'buckets': {'current': 500}, 'overdue': 0, 'maxDaysOverdue': 0, 'items': [],
        },
        {
          'id': 'c3', 'name': 'Chi Credit', 'status': 'active', 'balance': -1500, 'paymentTermsDays': 30,
          'buckets': {}, 'overdue': 0, 'maxDaysOverdue': 0, 'items': [],
        },
      ],
    });

CreditEntry _payment() => CreditEntry.fromJson({
      'id': 'p1', 'partyType': 'customer', 'partyId': 'c1', 'kind': 'payment', 'amount': -7000,
      'note': 'GTB', 'method': 'transfer', 'receiptNumber': 'RCPT-0003', 'openAmount': 0,
      'createdAt': '2026-10-28T10:00:00.000Z',
      'allocations': [
        {'reference': 'Opening balance', 'amount': 5000, 'debitEntryId': 'd1'},
        {'reference': 'INV-0001', 'amount': 1500, 'debitEntryId': 'd2'},
      ],
    });

Future<(_FakeOpener, FakePartiesRepository)> _pump(
  WidgetTester tester,
  Widget home, {
  String role = 'Owner',
  FakePartiesRepository? parties,
  FakeDebtReportRepository? debts,
  FakeSalesRepository? sales,
  FakeCustomerTypesRepository? types,
}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final opener = _FakeOpener();
  final repo = parties ??
      FakePartiesRepository(customers: [
        fixtureParty('c1', name: 'Ada Stores', balance: 12000, creditLimit: 50000),
        fixtureParty('c2', name: 'Bello Mart', balance: 500),
      ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(role)),
        documentOpenerProvider.overrideWithValue(opener),
        ...fakeDataOverrides(parties: repo, debts: debts, sales: sales, customerTypes: types),
      ],
      child: MaterialApp(theme: ThemeData(), home: Scaffold(body: home)),
    ),
  );
  await _settle(tester);
  return (opener, repo);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Lets real async work (building a PDF) finish.
Future<void> _settleAsync(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
  await _settle(tester);
}

Widget _opener(void Function(BuildContext, WidgetRef) open) => Consumer(
      builder: (context, ref, _) => Center(
        child: ElevatedButton(onPressed: () => open(context, ref), child: const Text('open')),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('models', () {
    test('a ledger entry carries its open amount, due date, method, receipt and what it settled', () {
      final debt = CreditEntry.fromJson({
        'id': 'd1', 'partyType': 'customer', 'partyId': 'c1', 'kind': 'charge', 'amount': 5000,
        'openAmount': 3000, 'dueDate': '2026-01-01T00:00:00.000Z', 'saleId': 's1',
        'createdAt': '2025-12-01T00:00:00.000Z',
      });
      expect(debt.openAmount, 3000);
      expect(debt.isOverdue, isTrue);
      expect(debt.saleId, 's1');
      final p = _payment();
      expect(p.receiptNumber, 'RCPT-0003');
      expect(p.method, 'transfer');
      expect(p.allocations.map((a) => (a.reference, a.amount)), [('Opening balance', 5000.0), ('INV-0001', 1500.0)]);
      expect(p.isOverdue, isFalse);
    });

    test('a sale carries its due date and days overdue; a payment its receipt', () {
      final s = Sale.fromJson({
        'id': 's1', 'reference': 'INV-0001', 'customerId': 'c1', 'warehouseId': 'w1', 'status': 'completed',
        'saleDate': '2026-09-01T00:00:00.000Z', 'dueDate': '2026-09-15T00:00:00.000Z', 'daysOverdue': 43,
        'total': 100, 'amountPaid': 0,
        'payments': [
          {'id': 'x', 'amount': 10, 'method': 'pos', 'createdAt': '2026-09-02T00:00:00.000Z', 'receiptNumber': 'RCPT-0001'},
        ],
      });
      expect(s.dueDate, isNotNull);
      expect(s.daysOverdue, 43);
      expect(s.payments.single.receiptNumber, 'RCPT-0001');
    });

    test('the report parses, and who to chase is the overdue ones, biggest first', () {
      final r = _report();
      expect(r.balance, 12500);
      expect(r.credit, 1500);
      expect(r.buckets[AgeBucket.over90], 5000);
      expect(r.parties.first.items.map((i) => i.reference), ['Opening balance', 'INV-0001', 'INV-0002']);
      expect(r.parties.first.lastPaymentAt, isNotNull);
      expect(r.toChase.map((p) => p.name), ['Ada Stores']);
      expect(r.parties.last.balance, -1500);
    });

    test('payment terms go to the server for both customers and suppliers', () {
      const c = PartyInput(type: PartyType.customer, name: 'A', paymentTermsDays: 7);
      const s = PartyInput(type: PartyType.supplier, name: 'S', paymentTermsDays: 45);
      expect(c.toJson()['paymentTermsDays'], 7);
      expect(s.toJson()['paymentTermsDays'], 45);
      expect(Party.fromJson(PartyType.supplier, {'id': 's', 'name': 'S', 'paymentTermsDays': 45}).paymentTermsDays, 45);
      expect(Party.fromJson(PartyType.customer, {'id': 'c', 'name': 'C'}).paymentTermsDays, 30);
    });
  });

  group('documents', () {
    test('the account receipt and the debt report build as PDFs', () async {
      final kit = await DocumentKit.load(_org);
      final receipt = await buildAccountReceipt(kit, fixtureParty('c1', name: 'Ada Stores'), _payment());
      final report = await buildDebtReport(kit, _report());
      expect(_isPdf(receipt), isTrue);
      expect(_isPdf(report), isTrue);
    });

    test('the Excel report has a summary sheet and every open item', () {
      final book = Excel.decodeBytes(buildDebtReportExcel(_report()));
      expect(book.sheets.keys, containsAll(['By customer', 'Open items']));
      final summary = book.sheets['By customer']!.rows;
      expect(summary.first.first?.value.toString(), 'Customer');
      expect(summary[1].first?.value.toString(), 'Ada Stores');
      expect(summary.last.first?.value.toString(), 'Total');
      expect(book.sheets['Open items']!.rows.length, 4, reason: 'header and three items');
    });
  });

  group('recording a payment', () {
    testWidgets('pick how it was paid; the result names what it settled and offers the receipt', (tester) async {
      final repo = FakePartiesRepository(customers: [fixtureParty('c1', name: 'Ada Stores', balance: 12000)]);
      repo.nextAllocations = const [
        CreditAllocation(reference: 'Opening balance', amount: 5000),
        CreditAllocation(reference: 'INV-0001', amount: 2000),
      ];
      final (opener, _) = await _pump(
        tester,
        _opener((context, ref) => recordCreditEntry(context, ref, repo.customers.single, CreditKind.payment)),
        parties: repo,
      );
      await _open(tester);
      expect(find.text('Settles the oldest invoices first.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('credit-amount')), '7000');
      await tester.tap(find.byKey(const Key('credit-method')));
      await _settle(tester);
      await tester.tap(find.text('Bank transfer').last);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('credit-save')));
      await _settle(tester);
      expect(repo.methods.single, 'transfer');
      expect(find.textContaining('RCPT-0001 recorded'), findsOneWidget);
      expect(find.textContaining('Settled: Opening balance ₦5,000, INV-0001 ₦2,000'), findsOneWidget);
      await tester.tap(find.text('Print receipt'));
      await _settleAsync(tester);
      expect(opener.opened.single.fileName, 'RCPT-0001.pdf');
      expect(_isPdf(opener.opened.single.bytes), isTrue);
    });

    testWidgets('a supplier payment has no receipt to print', (tester) async {
      final repo = FakePartiesRepository(suppliers: [fixtureParty('s1', type: PartyType.supplier, balance: 900)]);
      await _pump(
        tester,
        _opener((context, ref) => recordCreditEntry(context, ref, repo.suppliers.single, CreditKind.payment)),
        parties: repo,
      );
      await _open(tester);
      await tester.enterText(find.byKey(const Key('credit-amount')), '100');
      await tester.tap(find.byKey(const Key('credit-save')));
      await _settle(tester);
      expect(find.text('Print receipt'), findsNothing);
      expect(find.textContaining('Payment recorded'), findsOneWidget);
    });

    testWidgets('the account history shows receipts (printable) and overdue debts', (tester) async {
      final repo = FakePartiesRepository(customers: [fixtureParty('c1', name: 'Ada Stores', balance: 3000)]);
      repo.ledger.addAll([
        CreditEntry(
          id: 'd1',
          partyType: PartyType.customer,
          partyId: 'c1',
          kind: CreditKind.charge,
          amount: 5000,
          note: 'Sale INV-0001',
          openAmount: 3000,
          dueDate: DateTime.now().subtract(const Duration(days: 12)),
          createdAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
        _payment(),
      ]);
      final (opener, _) = await _pump(tester, const CustomerProfileScreen(customerId: 'c1'), parties: repo);
      await tester.tap(find.text('Account history'));
      await _settle(tester);
      expect(find.text('12 days overdue'), findsOneWidget);
      expect(find.textContaining('₦3,000 open, due'), findsOneWidget);
      expect(find.textContaining('RCPT-0003 · Bank transfer'), findsOneWidget);
      expect(find.textContaining('Settled Opening balance ₦5,000, INV-0001 ₦1,500'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('print-receipt-p1')));
      await _settleAsync(tester);
      expect(opener.opened.single.fileName, 'RCPT-0003.pdf');
    });
  });

  group('payment terms', () {
    testWidgets("a customer's terms follow the type until typed, and are sent", (tester) async {
      final (_, repo) = await _pump(
        tester,
        _opener((context, ref) => showDialog(context: context, builder: (_) => const PartyFormDialog(type: PartyType.customer))),
        types: FakeCustomerTypesRepository(const [
          CustomerType(id: 't-trade', name: 'Trade', defaultCreditLimit: 1000, defaultPaymentTermsDays: 14),
        ]),
      );
      await _open(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Kano Traders');
      expect(tester.widget<TextFormField>(find.byKey(const Key('party-terms'))).controller!.text, '30');
      await tester.tap(find.byKey(const Key('party-type')));
      await _settle(tester);
      await tester.tap(find.text('Trade').last);
      await _settle(tester);
      expect(tester.widget<TextFormField>(find.byKey(const Key('party-terms'))).controller!.text, '14');
      await tester.enterText(find.byKey(const Key('party-terms')), '400');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add customer'));
      await _settle(tester);
      expect(find.text('Enter 0 to 365 days'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('party-terms')), '21');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add customer'));
      await _settle(tester);
      expect(repo.created.single.paymentTermsDays, 21);
    });

    testWidgets('suppliers have payment terms too', (tester) async {
      final (_, repo) = await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            // As the Suppliers screen does.
            ref.watch(partyListProvider(PartyType.supplier));
            return _opener((context, ref) => showDialog(context: context, builder: (_) => const PartyFormDialog(type: PartyType.supplier)));
          },
        ),
      );
      await _open(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Dangote');
      await tester.enterText(find.byKey(const Key('party-terms')), '45');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add supplier'));
      await _settle(tester);
      expect(repo.created.single.paymentTermsDays, 45);
    });
  });

  group('Credits & Debts', () {
    testWidgets('the aging report: totals, each customer by age, open items, PDF', (tester) async {
      final debts = FakeDebtReportRepository(customers: _report());
      final (opener, _) = await _pump(tester, const CreditsDebtsScreen(), debts: debts);
      await tester.tap(find.byKey(const Key('tab-aging')));
      await _settle(tester);
      expect(find.descendant(of: find.byKey(const Key('aging-total')), matching: find.text('₦12,500')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('aging-overdue')), matching: find.text('₦9,000')), findsOneWidget);
      expect(find.text('₦1,500 credit'), findsOneWidget);
      expect(find.text('Never'), findsWidgets);

      await tester.tap(find.text('Ada Stores'));
      await _settle(tester);
      expect(find.text('Opening balance'), findsOneWidget);
      expect(find.text('100d overdue'), findsOneWidget);
      expect(find.text('Not yet due'), findsWidgets);
      await tester.tap(find.text('Close'));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('aging-pdf')));
      await _settleAsync(tester);
      expect(opener.opened.single.fileName, 'debt-report-customer.pdf');
      expect(_isPdf(opener.opened.single.bytes), isTrue);

      await tester.tap(find.descendant(of: find.byKey(const Key('aging-side')), matching: find.text('You owe suppliers')));
      await _settle(tester);
      expect(debts.requested, contains(PartyType.supplier));
      expect(find.text("You don't owe any supplier."), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('who to chase lists only the overdue, with a payment button', (tester) async {
      await _pump(tester, const CreditsDebtsScreen(), debts: FakeDebtReportRepository(customers: _report()));
      await tester.tap(find.byKey(const Key('tab-chase')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('chase-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chase-c2')), findsNothing);
      expect(find.text('₦9,000 overdue'), findsOneWidget);
      expect(find.textContaining('57 days ago'), findsOneWidget);
      expect(find.byKey(const ValueKey('chase-pay-c1')), findsOneWidget);
    });

    testWidgets('Sales Staff sees only the customer side and cannot take payments', (tester) async {
      final debts = FakeDebtReportRepository(customers: _report());
      await _pump(tester, const CreditsDebtsScreen(), role: 'Sales Staff', debts: debts);
      await tester.tap(find.byKey(const Key('tab-aging')));
      await _settle(tester);
      expect(find.byKey(const Key('aging-side')), findsNothing);
      expect(debts.requested, isNot(contains(PartyType.supplier)));
      await tester.tap(find.byKey(const Key('tab-chase')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('chase-pay-c1')), findsNothing);
    });
  });

  testWidgets('the sales list shows when each unpaid sale is due, or how overdue', (tester) async {
    final now = DateTime.now();
    final overdue = fixtureSale('a', reference: 'INV-0001', amountPaid: 0);
    final late = Sale(
      id: overdue.id, reference: overdue.reference, customerId: overdue.customerId, customerName: overdue.customerName,
      warehouseId: overdue.warehouseId, warehouseName: overdue.warehouseName, status: overdue.status, saleDate: now,
      dueDate: now.subtract(const Duration(days: 9)), daysOverdue: 9,
      subtotal: overdue.subtotal, discount: 0, tax: 0, total: overdue.total, amountPaid: 0, lines: overdue.lines,
    );
    await _pump(tester, const SalesScreen(), sales: FakeSalesRepository([late, fixtureSale('b', reference: 'INV-0002')]));
    expect(find.text('9d overdue'), findsOneWidget);
    expect(find.text('Due'), findsOneWidget);
  });
}
