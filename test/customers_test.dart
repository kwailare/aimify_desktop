// Customers (feature checklist step 9): types with default credit limits,
// the list (summary cards, search, filters, archive and restore), the
// customer's page (totals, sales, account, actions per role), managing
// types, and Excel import and export.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/domain/screen_visibility.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/customers/data/customer_excel.dart';
import 'package:aimify_desktop/features/customers/data/customer_types.dart';
import 'package:aimify_desktop/features/customers/presentation/customer_import_dialog.dart';
import 'package:aimify_desktop/features/customers/presentation/customer_profile_screen.dart';
import 'package:aimify_desktop/features/customers/presentation/customers_screen.dart';
import 'package:aimify_desktop/features/parties/data/party_overlay.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/parties/presentation/party_form_dialog.dart';
import 'package:aimify_desktop/shared/offline/outbox.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

List<Party> _customers() => [
      fixtureParty(
        'c1',
        name: 'Ada Stores',
        customerTypeId: 't-wholesale',
        customerTypeName: 'Wholesale',
        balance: 400000,
        creditLimit: 500000,
        totalSales: 1250000,
        salesCount: 5,
        lastSaleAt: DateTime(2026, 10, 20),
        email: 'ada@stores.ng',
      ),
      fixtureParty('c2', name: 'Bello Mart', customerTypeId: 't-retail', customerTypeName: 'Retail'),
      fixtureParty('c3', name: 'Chinedu Ventures', balance: 100, creditLimit: 100),
      fixtureParty('c4', name: 'Dayo Archived', isActive: false),
    ];

class _Rig {
  _Rig({this.role = 'Owner', List<String>? permissions, List<CustomerType>? types})
      : permissions = permissions ?? defaultPermissionsFor(role),
        parties = FakePartiesRepository(customers: _customers()),
        types = FakeCustomerTypesRepository(types),
        sales = FakeSalesRepository([
          fixtureSale('s1', reference: 'INV-0001', customerId: 'c1'),
          fixtureSale('s2', reference: 'INV-0002', customerId: 'c2'),
        ]);

  final String role;
  final List<String> permissions;
  final FakePartiesRepository parties;
  final FakeCustomerTypesRepository types;
  final FakeSalesRepository sales;
}

Future<_Rig> _pump(WidgetTester tester, {Widget? home, String location = '/customers', _Rig? rig, Size size = const Size(1400, 1000)}) async {
  final r = rig ?? _Rig();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/customers',
        builder: (context, state) => home ?? const CustomersScreen(),
        routes: [
          GoRoute(path: ':id', builder: (context, state) => CustomerProfileScreen(customerId: state.pathParameters['id']!)),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(r.role, r.permissions)),
        ...fakeDataOverrides(parties: r.parties, customerTypes: r.types, sales: r.sales),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
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

Widget _opener(Widget dialog) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await _settle(tester);
}

Finder _inCard(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

List<int> _sheet(List<List<Object?>> rows) {
  final workbook = Excel.createExcel();
  final sheet = workbook[workbook.getDefaultSheet()!];
  for (final row in rows) {
    sheet.appendRow([
      for (final cell in row)
        cell is num ? DoubleCellValue(cell.toDouble()) : TextCellValue(cell?.toString() ?? ''),
    ]);
  }
  return workbook.encode()!;
}

const _types = [
  CustomerType(id: 't-retail', name: 'Retail'),
  CustomerType(id: 't-wholesale', name: 'Wholesale', defaultCreditLimit: 500000),
];

void main() {
  group('models', () {
    test('a customer parses with its type and what it bought', () {
      final c = Party.fromJson(PartyType.customer, {
        'id': 'c1',
        'name': 'Ada',
        'creditLimit': 1000,
        'balanceOwed': 250,
        'status': 'archived',
        'customerTypeId': 't1',
        'customerTypeName': 'Retail',
        'totalSales': 9000.5,
        'salesCount': 3,
        'lastSaleAt': '2026-10-25T15:04:00.000Z',
      });
      expect(c.customerTypeName, 'Retail');
      expect(c.totalSales, 9000.5);
      expect(c.salesCount, 3);
      expect(c.lastSaleAt, DateTime.utc(2026, 10, 25, 15, 4).toLocal());
      expect(c.isActive, isFalse);
      expect(c.creditLeft, 750);
      expect(fixtureParty('x').creditLeft, isNull, reason: 'no limit, nothing to count down');
    });

    test('only customers send a type', () {
      const customer = PartyInput(type: PartyType.customer, name: 'A', customerTypeId: 't1');
      const supplier = PartyInput(type: PartyType.supplier, name: 'S', customerTypeId: 't1');
      expect(customer.toJson()['customerTypeId'], 't1');
      expect(supplier.toJson().containsKey('customerTypeId'), isFalse);
      expect(PartyInput.fromJson(PartyType.customer, customer.toJson()).customerTypeId, 't1');
    });

    test('archiving offline keeps a customer, marked archived; a supplier leaves the list', () {
      OutboxOp archive(String type, String id) => OutboxOp(
            id: 'op-$id',
            kind: OpKind.partyArchive,
            payload: {'type': type, 'id': id},
            createdAt: DateTime(2026, 10, 26),
          );
      final customers = overlayParties([fixtureParty('c1')], [archive('customer', 'c1')], PartyType.customer);
      expect(customers.single.isActive, isFalse);
      final suppliers = overlayParties(
        [fixtureParty('s1', type: PartyType.supplier)],
        [archive('supplier', 's1')],
        PartyType.supplier,
      );
      expect(suppliers, isEmpty);
    });

    test("a customer's page belongs to the Customers section", () {
      expect(screenForPath('/customers/abc'), AppScreen.customers);
      expect(screenForPath('/customers'), AppScreen.customers);
      expect(screenForPath('/nowhere/1'), isNull);
    });
  });

  group('Excel', () {
    test('rows are matched by header, types by name, and existing names are skipped', () {
      final parsed = parseCustomerWorkbook(
        _sheet([
          ['Customer name', 'Customer Type', 'Phone', 'Credit limit', 'Opening balance'],
          ['New Shop', 'wholesale', '080 1', '', 2500],
          ['ada stores', 'Retail', '', '', ''],
          ['Fresh Co', 'Agents', '', 1000, ''],
          ['', 'Retail', '', '', ''],
          ['Fresh  co', '', '', '', ''],
          ['Bad Limit', '', '', 'abc', ''],
          ['', '', '', '', ''],
        ]),
        types: _types,
        existing: [fixtureParty('c1', name: 'Ada Stores')],
      );
      expect(parsed.sheetError, isNull);
      expect(parsed.rows.map((r) => r.input.name), ['New Shop', 'Fresh Co']);
      final shop = parsed.rows.first;
      expect(shop.input.customerTypeId, 't-wholesale');
      expect(shop.input.creditLimit, 500000, reason: "an empty limit takes the type's default");
      expect(shop.openingBalance, 2500);
      expect(shop.input.phone, '080 1');
      final fresh = parsed.rows.last;
      expect(fresh.input.customerTypeId, isNull);
      expect(fresh.input.creditLimit, 1000);
      expect(fresh.warnings.single, contains('Agents'));
      expect(parsed.skipped.map((e) => e.rowNumber), [3, 6], reason: 'already a customer, then repeated in the file');
      expect(parsed.errors.map((e) => e.rowNumber), [5, 7]);
      expect(parsed.errors.first.messages, ['Name is required']);
    });

    test('a sheet without a Name column, or not a spreadsheet, is refused', () {
      expect(parseCustomerWorkbook(_sheet([['Phone'], ['080']])).sheetError, contains('Name'));
      expect(parseCustomerWorkbook([1, 2, 3]).sheetError, isNotNull);
    });

    test('the template imports as one example customer', () {
      final parsed = parseCustomerWorkbook(buildCustomerImportTemplate(), types: _types);
      expect(parsed.rows.single.input.name, 'Blessing Retail Store');
      expect(parsed.rows.single.input.customerTypeId, 't-retail');
      expect(parsed.rows.single.openingBalance, 45000);
    });

    test('the export has every customer with type, balance and totals', () {
      final bytes = buildCustomerExport(_customers(), (c) => c.customerTypeName);
      final rows = Excel.decodeBytes(bytes).sheets.values.first.rows;
      String cell(int r, int c) => rows[r][c]?.value.toString() ?? '';
      expect(cell(0, 0), 'Name');
      expect(rows.length, 5);
      expect(cell(1, 0), 'Ada Stores');
      expect(cell(1, 1), 'Wholesale');
      expect(double.parse(cell(1, 6)), 400000);
      expect(double.parse(cell(1, 7)), 1250000);
      expect(cell(1, 9), '2026-10-20');
      expect(cell(4, 10), 'Archived');
    });
  });

  group('the list', () {
    testWidgets('summary cards, then Owing / At limit / Archived and restoring', (tester) async {
      final rig = await _pump(tester);
      expect(_inCard('customers-stat-count', '3'), findsOneWidget);
      expect(_inCard('customers-stat-owed', '₦400,100'), findsOneWidget);
      expect(_inCard('customers-stat-limit', '1'), findsOneWidget);
      expect(_inCard('customers-stat-month', '₦600'), findsOneWidget);
      expect(find.text('Dayo Archived'), findsNothing);
      expect(find.text('Wholesale'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const Key('customers-show')), matching: find.text('Owing')));
      await _settle(tester);
      expect(find.text('Ada Stores'), findsOneWidget);
      expect(find.text('Bello Mart'), findsNothing);

      await tester.tap(find.descendant(of: find.byKey(const Key('customers-show')), matching: find.text('At limit')));
      await _settle(tester);
      expect(find.text('Chinedu Ventures'), findsOneWidget);
      expect(find.text('Ada Stores'), findsNothing);

      await tester.tap(find.descendant(of: find.byKey(const Key('customers-show')), matching: find.text('Archived')));
      await _settle(tester);
      expect(find.text('Dayo Archived'), findsOneWidget);
      tester.widget<TextButton>(find.byKey(const ValueKey('customer-restore-c4'))).onPressed!();
      await _settle(tester);
      expect(rig.parties.restored, ['c4']);
      expect(find.text('Dayo Archived'), findsNothing, reason: 'it is active again');
      expect(tester.takeException(), isNull);
    });

    testWidgets('search and the type filter', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField).last, 'stores.ng');
      await _settle(tester);
      expect(find.text('Ada Stores'), findsOneWidget, reason: 'matched by email');
      expect(find.text('Bello Mart'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.tap(find.byKey(const Key('customers-type-filter')));
      await _settle(tester);
      await tester.tap(find.text('No type').last);
      await _settle(tester);
      expect(find.text('Chinedu Ventures'), findsOneWidget);
      expect(find.text('Ada Stores'), findsNothing);
    });

    testWidgets('archiving asks first and moves the customer to Archived', (tester) async {
      await _pump(tester);
      tester.widget<IconButton>(find.byKey(const ValueKey('customer-archive-c2'))).onPressed!();
      await _settle(tester);
      await tester.tap(find.byKey(const Key('customer-confirm-archive')));
      await _settle(tester);
      expect(find.text('Bello Mart'), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const Key('customers-show')), matching: find.text('Archived')));
      await _settle(tester);
      expect(find.text('Bello Mart'), findsOneWidget);
    });

    testWidgets('Sales Staff: no Types button, but add, import and export', (tester) async {
      await _pump(tester, rig: _Rig(role: 'Sales Staff'));
      expect(find.byKey(const Key('customers-types')), findsNothing);
      expect(find.byKey(const Key('customers-import')), findsOneWidget);
      expect(find.byKey(const Key('customers-export')), findsOneWidget);
    });

    testWidgets('the Accountant can look and export, not add', (tester) async {
      await _pump(tester, rig: _Rig(role: 'Accountant / Finance'));
      expect(find.byKey(const Key('customers-import')), findsNothing);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('customers-add'))).onPressed, isNull);
      expect(find.byKey(const Key('customers-export')), findsOneWidget);
    });

    testWidgets('a row opens the customer, and back returns to the list', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Ada Stores'));
      await _settle(tester);
      expect(find.byType(CustomerProfileScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('customer-back')));
      await _settle(tester);
      expect(find.byType(CustomerProfileScreen), findsNothing);
      expect(find.byKey(const Key('customers-stat-count')), findsOneWidget);
    });
  });

  group("the customer's page", () {
    testWidgets('totals, type, sales and account', (tester) async {
      final rig = _Rig();
      rig.parties.ledger.add(
        CreditEntry(
          id: 'e1',
          partyType: PartyType.customer,
          partyId: 'c1',
          kind: CreditKind.payment,
          amount: -50000,
          note: 'Paid at the shop',
          createdAt: DateTime(2026, 10, 21),
        ),
      );
      await _pump(tester, location: '/customers/c1', rig: rig);
      expect(find.byKey(const Key('customer-name')), findsOneWidget);
      expect(find.text('Ada Stores'), findsOneWidget);
      expect(find.byKey(const Key('customer-type-chip')), findsOneWidget);
      expect(_inCard('customer-stat-owes', '₦400,000'), findsOneWidget);
      expect(_inCard('customer-stat-owes', '₦100,000 of credit left'), findsOneWidget);
      expect(_inCard('customer-stat-bought', '₦1,250,000'), findsOneWidget);
      expect(_inCard('customer-stat-bought', '5 sales'), findsOneWidget);
      expect(find.text('INV-0001'), findsOneWidget);
      expect(find.text('INV-0002'), findsNothing, reason: "another customer's sale");

      await tester.tap(find.text('Account history'));
      await _settle(tester);
      expect(find.textContaining('Paid at the shop'), findsOneWidget);
      for (final key in ['customer-new-sale', 'customer-record-payment', 'customer-statement', 'customer-edit', 'customer-archive']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Accountant takes payments but neither sells nor edits', (tester) async {
      await _pump(tester, location: '/customers/c1', rig: _Rig(role: 'Accountant / Finance'));
      expect(find.byKey(const Key('customer-record-payment')), findsOneWidget);
      expect(find.byKey(const Key('customer-new-sale')), findsNothing);
      expect(find.byKey(const Key('customer-edit')), findsNothing);
      expect(find.byKey(const Key('customer-archive')), findsNothing);
    });

    testWidgets('Sales Staff sells and edits, without payments', (tester) async {
      await _pump(tester, location: '/customers/c1', rig: _Rig(role: 'Sales Staff'));
      expect(find.byKey(const Key('customer-new-sale')), findsOneWidget);
      expect(find.byKey(const Key('customer-edit')), findsOneWidget);
      expect(find.byKey(const Key('customer-record-payment')), findsNothing);
    });

    testWidgets('an archived customer can be restored, not sold to', (tester) async {
      final rig = await _pump(tester, location: '/customers/c4');
      expect(find.byKey(const Key('customer-new-sale')), findsNothing);
      await tester.tap(find.byKey(const Key('customer-restore')));
      await _settle(tester);
      expect(rig.parties.restored, ['c4']);
      expect(find.byKey(const Key('customer-new-sale')), findsOneWidget);
    });

    testWidgets('an unknown customer says so', (tester) async {
      await _pump(tester, location: '/customers/nope');
      expect(find.text('This customer was not found.'), findsOneWidget);
    });

    testWidgets('lays out without overflow at 1024×760', (tester) async {
      await _pump(tester, location: '/customers/c1', size: const Size(1024, 760));
      expect(tester.takeException(), isNull);
    });
  });

  group('the form', () {
    testWidgets("picking a type fills in its default limit, and the type is sent", (tester) async {
      final rig = await _pump(tester, home: _opener(const PartyFormDialog(type: PartyType.customer)));
      await _open(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Kano Traders');
      await tester.tap(find.byKey(const Key('party-type')));
      await _settle(tester);
      await tester.tap(find.text('Wholesale').last);
      await _settle(tester);
      expect(tester.widget<TextFormField>(find.byKey(const Key('party-credit-limit'))).controller!.text, '500000');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add customer'));
      await _settle(tester);
      final sent = rig.parties.created.single;
      expect(sent.customerTypeId, 't-wholesale');
      expect(sent.creditLimit, 500000);
    });

    testWidgets('a limit typed first is kept when the type is picked', (tester) async {
      final rig = await _pump(tester, home: _opener(const PartyFormDialog(type: PartyType.customer)));
      await _open(tester);
      await tester.enterText(find.byType(TextFormField).first, 'Kano Traders');
      await tester.enterText(find.byKey(const Key('party-credit-limit')), '1000');
      await tester.tap(find.byKey(const Key('party-type')));
      await _settle(tester);
      await tester.tap(find.text('Wholesale').last);
      await _settle(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add customer'));
      await _settle(tester);
      expect(rig.parties.created.single.creditLimit, 1000);
    });
  });

  group('types', () {
    testWidgets('add one, change one, and a type in use cannot be removed', (tester) async {
      final rig = await _pump(
        tester,
        rig: _Rig(types: const [
          CustomerType(id: 't-retail', name: 'Retail'),
          CustomerType(id: 't-wholesale', name: 'Wholesale', defaultCreditLimit: 500000, customerCount: 1),
        ]),
      );
      await tester.tap(find.byKey(const Key('customers-types')));
      await _settle(tester);
      expect(
        tester.widget<IconButton>(find.byKey(const ValueKey('customer-type-delete-t-wholesale'))).onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('customer-type-name')), 'Agents');
      await tester.enterText(find.byKey(const Key('customer-type-limit')), '1000');
      await tester.tap(find.byKey(const Key('customer-type-add')));
      await _settle(tester);
      expect(rig.types.types.map((t) => t.name), contains('Agents'));
      expect(rig.types.types.firstWhere((t) => t.name == 'Agents').defaultCreditLimit, 1000);
      expect(find.text('Agents'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('customer-type-delete-t-retail')));
      await _settle(tester);
      expect(rig.types.deleted, ['t-retail']);
    });

    testWidgets("the server's refusal is shown", (tester) async {
      final rig = _Rig();
      rig.types.writeError = ApiException(409, 'This customer type already exists.');
      await _pump(tester, rig: rig);
      await tester.tap(find.byKey(const Key('customers-types')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('customer-type-name')), 'retail');
      await tester.tap(find.byKey(const Key('customer-type-add')));
      await _settle(tester);
      expect(find.text('This customer type already exists.'), findsOneWidget);
    });
  });

  testWidgets('import: preview, then customers added with their opening balances', (tester) async {
    final bytes = _sheet([
      ['Name', 'Type', 'Opening balance'],
      ['New Shop', 'Wholesale', 2500],
      ['Ada Stores', '', ''],
      ['Second Shop', '', ''],
    ]);
    final rig = await _pump(
      tester,
      home: _opener(CustomerImportDialog(pickFile: () async => (name: 'customers.xlsx', bytes: bytes))),
    );
    await _open(tester);
    await tester.tap(find.byKey(const Key('customer-import-pick')));
    await _settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('customer-import-summary'))).data, 'customers.xlsx: 2 ready · 1 already in your list');
    await tester.tap(find.byKey(const Key('customer-import-run')));
    await _settle(tester);
    expect(rig.parties.created.map((p) => p.name), ['New Shop', 'Second Shop']);
    expect(rig.parties.created.first.creditLimit, 500000);
    expect(rig.parties.recorded.single.amount, 2500);
    expect(rig.parties.recorded.single.kind, CreditKind.charge);
    expect(find.text('2 customers added'), findsOneWidget);
  });
}
