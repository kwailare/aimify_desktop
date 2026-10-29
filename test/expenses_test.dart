// Expenses on the server (feature checklist step 12): the models and the
// offline queue, uploading old local expenses, the report with budgets (and
// its PDF and Excel), the screen (cards, filters, due recurring expenses),
// the form with a receipt, the detail (receipt, edit, void) per role, and
// categories with budgets.

import 'dart:convert';
import 'dart:typed_data';

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/documents/document_kit.dart';
import 'package:aimify_desktop/features/documents/document_preview.dart';
import 'package:aimify_desktop/features/documents/expense_documents.dart';
import 'package:aimify_desktop/features/expenses/data/expense_report.dart';
import 'package:aimify_desktop/features/expenses/data/expenses_repository.dart';
import 'package:aimify_desktop/features/expenses/domain/expense.dart';
import 'package:aimify_desktop/features/expenses/presentation/expense_categories_dialog.dart';
import 'package:aimify_desktop/features/expenses/presentation/expense_detail_dialog.dart';
import 'package:aimify_desktop/features/expenses/presentation/expense_form_dialog.dart';
import 'package:aimify_desktop/features/expenses/presentation/expenses_screen.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
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
  _Auth(this.role, {this.userId = 'u1'});

  final String role;
  final String userId;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: AuthUser(id: userId, name: 'Ada', email: 'ada@company.com'),
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
  final List<String> opened = [];

  @override
  Future<void> open(BuildContext context, WidgetRef ref, {required String title, required String fileName, required DocumentBuilder build}) async {
    await build(await DocumentKit.load(_org));
    opened.add(fileName);
  }
}

final _now = DateTime.now();
DateTime _thisMonth(int day) => DateTime(_now.year, _now.month, day.clamp(1, 28));
DateTime _lastMonth(int day) => DateTime(_now.year, _now.month - 1, day);

List<Expense> _expenses() => [
      fixtureExpense('e1', reference: 'EXP-0001', categoryId: 'cat-fuel', categoryName: 'Fuel & generator', amount: 40000, date: _thisMonth(2), description: 'Diesel', warehouseId: 'w1', warehouseName: 'Main Warehouse'),
      fixtureExpense('e2', reference: 'EXP-0002', categoryId: 'cat-fuel', categoryName: 'Fuel & generator', amount: 20000, date: _thisMonth(3), description: 'Petrol for the van'),
      fixtureExpense('e3', reference: 'EXP-0003', categoryId: 'cat-rent', categoryName: 'Rent', amount: 300000, date: _thisMonth(1), description: 'Shop rent'),
      fixtureExpense('e4', reference: 'EXP-0004', categoryId: 'cat-other', categoryName: 'Other', amount: 9999, date: _thisMonth(4), voided: true),
      fixtureExpense('e5', reference: 'EXP-0005', categoryId: 'cat-rent', categoryName: 'Rent', amount: 300000, date: _lastMonth(1), description: 'Shop rent'),
    ];

class _Rig {
  _Rig({this.role = 'Owner', this.userId = 'u1', List<RecurringExpense>? recurring, this.store})
      : repo = FakeExpensesRepository(expenses: _expenses(), recurring: recurring);

  final String role;
  final String userId;
  final FakeExpensesRepository repo;
  final MemoryLocalStore? store;
  final opener = _FakeOpener();
  final openedUrls = <String>[];
  PickedReceipt? receipt = (name: 'receipt.png', bytes: [1, 2, 3]);
}

Future<_Rig> _pump(WidgetTester tester, Widget home, {_Rig? rig, Size size = const Size(1500, 1100), ThemeData? theme}) async {
  final r = rig ?? _Rig();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(r.role, userId: r.userId)),
        documentOpenerProvider.overrideWithValue(r.opener),
        receiptPickerProvider.overrideWithValue(() async => r.receipt),
        openUrlProvider.overrideWithValue((url) async => r.openedUrls.add(url)),
        ...fakeDataOverrides(expenses: r.repo, store: r.store),
      ],
      child: MaterialApp(theme: theme ?? ThemeData(), home: Scaffold(body: home)),
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

Finder _inCard(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.textContaining(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('models', () {
    test('an expense parses with its receipt, recorder and void', () {
      final e = Expense.fromJson({
        'id': 'e1', 'reference': 'EXP-0007', 'categoryId': 'c1', 'categoryName': 'Rent', 'amount': 300000,
        'expenseDate': '2026-10-01T09:00:00.000Z', 'paymentMethod': 'transfer', 'payee': 'Landlord',
        'attachmentUrl': 'https://x/r.pdf', 'attachmentType': 'application/pdf', 'status': 'voided',
        'voidReason': 'Paid twice', 'createdBy': 'u9', 'createdByName': 'Musa',
      });
      expect(e.isVoided, isTrue);
      expect(e.attachmentIsPdf, isTrue);
      expect(e.paymentMethod, SalePaymentMethod.transfer);
      expect(e.title, 'Landlord');
      expect(e.createdById, 'u9');
    });

    test('the input round-trips through the offline queue', () {
      final input = ExpenseInput(
        categoryId: 'c1',
        amount: 1500,
        expenseDate: DateTime(2026, 10, 5, 9),
        paymentMethod: SalePaymentMethod.pos,
        warehouseId: 'w1',
        payee: 'Bolt',
        description: 'Taxi',
      );
      final back = ExpenseInput.fromJson(jsonDecode(jsonEncode(input.toJson())) as Map<String, dynamic>);
      expect(back.amount, 1500);
      expect(back.paymentMethod, SalePaymentMethod.pos);
      expect(back.expenseDate, DateTime(2026, 10, 5, 9));
      expect(back.payee, 'Bolt');
    });

    test('an old local expense goes into the category of the same name, or Other', () {
      const cats = [ExpenseCategory(id: 'c-t', name: 'Transport'), ExpenseCategory(id: 'c-o', name: 'Other')];
      final matched = legacyExpenseInput(
        LegacyExpense(id: '1', category: ' transport ', amount: 10, date: DateTime(2026, 9, 1), paymentMethod: 'bankTransfer', note: 'Van'),
        cats,
      )!;
      expect(matched.categoryId, 'c-t');
      expect(matched.description, 'Van');
      expect(matched.paymentMethod, SalePaymentMethod.transfer);
      final other = legacyExpenseInput(
        LegacyExpense(id: '2', category: 'Snacks', amount: 10, date: DateTime(2026, 9, 1), paymentMethod: 'mobileMoney', note: ''),
        cats,
      )!;
      expect(other.categoryId, 'c-o');
      expect(other.description, '(was Snacks)');
      expect(legacyExpenseInput(LegacyExpense(id: '3', category: 'x', amount: 1, date: DateTime(2026), paymentMethod: 'cash', note: ''), const []), isNull);
    });
  });

  group('report', () {
    const cats = [
      ExpenseCategory(id: 'cat-rent', name: 'Rent', monthlyBudget: 300000),
      ExpenseCategory(id: 'cat-fuel', name: 'Fuel & generator', monthlyBudget: 50000),
      ExpenseCategory(id: 'cat-repairs', name: 'Repairs', monthlyBudget: 20000),
    ];

    test('this month: totals, budgets, over budget, voided left out', () {
      final r = buildExpenseReport(_expenses(), cats, DateTime(_now.year, _now.month), DateTime(_now.year, _now.month + 1));
      expect(r.total, 360000);
      expect(r.count, 3);
      final fuel = r.byCategory.firstWhere((c) => c.name == 'Fuel & generator');
      expect(fuel.total, 60000);
      expect(fuel.overBudget, isTrue);
      expect(fuel.left, -10000);
      final repairs = r.byCategory.firstWhere((c) => c.name == 'Repairs');
      expect(repairs.total, 0, reason: 'a budget with nothing spent still shows');
      expect(r.byCategory.first.name, 'Rent', reason: 'biggest first');
      expect(r.byWarehouse.map((w) => w.$1), containsAll(['The whole business', 'Main Warehouse']));
      expect(r.budget, 370000);
    });

    test('two months: budgets count twice, and each month is listed', () {
      final r = buildExpenseReport(_expenses(), cats, DateTime(_now.year, _now.month - 1), DateTime(_now.year, _now.month + 1));
      expect(r.months, 2);
      expect(r.byCategory.firstWhere((c) => c.name == 'Rent').budget, 600000);
      expect(r.byMonth.length, 2);
      expect(r.total, 660000);
    });

    test('Excel and PDF', () async {
      final r = buildExpenseReport(_expenses(), cats, DateTime(_now.year, _now.month), DateTime(_now.year, _now.month + 1));
      final book = Excel.decodeBytes(buildExpenseReportExcel(r));
      expect(book.sheets.keys, containsAll(['Summary', 'Expenses']));
      expect(book.sheets['Expenses']!.rows.length, 4, reason: 'header and three expenses');
      final pdf = await buildExpenseReportPdf(await DocumentKit.load(_org), r);
      expect(String.fromCharCodes(Uint8List.fromList(pdf).take(5)), '%PDF-');
    });
  });

  group('the screen', () {
    testWidgets('cards, filters and voided on request', (tester) async {
      await _pump(tester, const ExpensesScreen());
      expect(_inCard('expenses-stat-month', '₦360,000'), findsOneWidget);
      expect(_inCard('expenses-stat-over', 'Fuel & generator'), findsOneWidget);
      expect(find.text('EXP-0003'), findsOneWidget);
      expect(find.text('EXP-0005'), findsNothing, reason: 'last month');
      expect(find.text('EXP-0004'), findsNothing, reason: 'voided');

      await tester.tap(find.byKey(const Key('expenses-show-voided')));
      await _settle(tester);
      expect(find.text('EXP-0004'), findsOneWidget);

      await tester.tap(find.text('Last month').first);
      await _settle(tester);
      expect(find.text('EXP-0005'), findsOneWidget);
      expect(find.text('EXP-0003'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a recurring expense that is due is recorded from the banner, with the due date shown', (tester) async {
      final due = DateTime.utc(_now.year, _now.month, 1);
      final rig = await _pump(
        tester,
        const ExpensesScreen(),
        rig: _Rig(recurring: [
          RecurringExpense(id: 'rec1', categoryId: 'cat-rent', categoryName: 'Rent', description: 'Shop rent', amount: 300000, frequency: Frequency.monthly, nextDueDate: due, due: true),
        ]),
      );
      expect(find.byKey(const Key('expenses-due')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('due-record-rec1')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('recurring-record-amount')), '310000');
      await tester.tap(find.byKey(const Key('recurring-record-confirm')));
      await _settle(tester);
      expect(rig.repo.recorded.single.dueDate, due);
      expect(rig.repo.recorded.single.amount, 310000);
      expect(find.textContaining('Shop rent ₦310,000'), findsOneWidget);
    });

    testWidgets('the due banner reads in the dark theme: theme colours, not a fixed light background', (tester) async {
      final dark = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC9800C), brightness: Brightness.dark));
      await _pump(
        tester,
        const ExpensesScreen(),
        theme: dark,
        rig: _Rig(recurring: [
          RecurringExpense(id: 'rec1', categoryId: 'cat-rent', categoryName: 'Rent', description: 'Shop rent', amount: 300000, frequency: Frequency.monthly, nextDueDate: DateTime.utc(_now.year, _now.month, 1), due: true),
        ]),
      );
      final banner = tester.widget<Container>(find.byKey(const Key('expenses-due')));
      final background = (banner.decoration! as BoxDecoration).color!;
      final onScreen = Color.alphaBlend(background, dark.colorScheme.surface);
      expect(onScreen.computeLuminance(), lessThan(0.3), reason: 'a dark-theme banner is dark');
      final title = tester.widget<Text>(find.text('1 recurring expense is due'));
      expect(title.style!.color, dark.colorScheme.onSurface);
    });

    testWidgets('old local expenses are offered for upload, with legacy clientRefs', (tester) async {
      final store = MemoryLocalStore();
      await writeJson(store, 'u_u1_expenses', [
        LegacyExpense(id: 'old1', category: 'Rent', amount: 250000, date: DateTime(2026, 8, 1), paymentMethod: 'bankTransfer', note: 'August').toJson(),
      ]);
      final rig = await _pump(tester, const ExpensesScreen(), rig: _Rig(store: store));
      await tester.tap(find.byKey(const Key('expenses-legacy')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('legacy-expenses-upload')));
      await _settle(tester);
      final sent = rig.repo.created.single;
      expect(sent.clientRef, 'legacy:old1');
      expect(sent.input.categoryId, 'cat-rent');
      expect(sent.input.amount, 250000);
      expect(find.text('1 uploaded.'), findsOneWidget);
    });

    testWidgets('the report tab: budgets and Print / PDF', (tester) async {
      final rig = await _pump(tester, const ExpensesScreen());
      await tester.tap(find.text('Report & budgets'));
      await _settle(tester);
      expect(find.textContaining('₦360,000 on 3 expenses'), findsOneWidget);
      expect(find.textContaining('Over budget by ₦10,000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-pdf')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await _settle(tester);
      expect(rig.opener.opened.single, startsWith('expenses-'));
    });

    testWidgets('the Accountant: no categories or recurring setup', (tester) async {
      await _pump(tester, const ExpensesScreen(), rig: _Rig(role: 'Accountant / Finance'));
      expect(find.byKey(const Key('expenses-categories')), findsNothing);
      await tester.tap(find.text('Recurring'));
      await _settle(tester);
      expect(find.byKey(const Key('recurring-add')), findsNothing);
    });
  });

  group('the form', () {
    testWidgets('records an expense and attaches the receipt', (tester) async {
      final rig = await _pump(tester, _opener(const ExpenseFormDialog()));
      await _open(tester);
      await tester.tap(find.byKey(const Key('expense-save')));
      await _settle(tester);
      expect(find.text('Choose a category'), findsOneWidget);

      await tester.tap(find.byKey(const Key('expense-category')));
      await _settle(tester);
      await tester.tap(find.text('Fuel & generator').last);
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('expense-amount')), '12,500');
      await tester.enterText(find.byKey(const Key('expense-payee')), 'Total');
      await tester.tap(find.byKey(const Key('expense-pick-receipt')));
      await _settle(tester);
      expect(find.text('receipt.png'), findsOneWidget);
      await tester.tap(find.byKey(const Key('expense-save')));
      await _settle(tester);

      final sent = rig.repo.created.single;
      expect(sent.input.categoryId, 'cat-fuel');
      expect(sent.input.amount, 12500);
      expect(sent.input.payee, 'Total');
      expect(sent.clientRef, isNotNull);
      expect(rig.repo.attached.single.filename, 'receipt.png');
      expect(find.textContaining('recorded · ₦12,500'), findsOneWidget);
    });

    testWidgets('a receipt over 5 MB is refused before sending', (tester) async {
      final rig = _Rig()..receipt = (name: 'huge.pdf', bytes: List.filled(5 * 1024 * 1024 + 1, 0));
      await _pump(tester, _opener(const ExpenseFormDialog()), rig: rig);
      await _open(tester);
      await tester.tap(find.byKey(const Key('expense-pick-receipt')));
      await _settle(tester);
      expect(find.text('The receipt must be 5 MB or smaller.'), findsOneWidget);
    });
  });

  group('the detail', () {
    testWidgets('the Owner opens the receipt, edits and voids', (tester) async {
      final rig = _Rig();
      rig.repo.expenses = [
        fixtureExpense('e1', attachmentUrl: 'https://example.test/r.pdf', attachmentType: 'application/pdf'),
      ];
      await _pump(tester, _opener(const ExpenseDetailDialog(expenseId: 'e1')), rig: rig);
      await _open(tester);
      await tester.tap(find.byKey(const Key('expense-open-receipt')));
      await _settle(tester);
      expect(rig.openedUrls.single, 'https://example.test/r.pdf');
      expect(find.byKey(const Key('expense-edit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('expense-void')));
      await _settle(tester);
      expect(tester.widget<ElevatedButton>(find.byKey(const Key('expense-void-confirm'))).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('expense-void-reason')), 'Recorded twice');
      await _settle(tester);
      await tester.tap(find.byKey(const Key('expense-void-confirm')));
      await _settle(tester);
      expect(rig.repo.voided.single, (id: 'e1', reason: 'Recorded twice'));
      expect(find.byKey(const Key('expense-voided-note')), findsOneWidget);
      expect(find.byKey(const Key('expense-edit')), findsNothing);
    });

    testWidgets('the Warehouse Manager attaches a receipt to their own expense, but cannot edit or void', (tester) async {
      final rig = _Rig(role: 'Warehouse Manager', userId: 'u1');
      rig.repo.expenses = [fixtureExpense('e1', createdById: 'u1'), fixtureExpense('e2', createdById: 'someone-else')];
      await _pump(tester, _opener(const ExpenseDetailDialog(expenseId: 'e1')), rig: rig);
      await _open(tester);
      expect(find.byKey(const Key('expense-edit')), findsNothing);
      expect(find.byKey(const Key('expense-void')), findsNothing);
      await tester.tap(find.byKey(const Key('expense-attach')));
      await _settle(tester);
      expect(rig.repo.attached.single.id, 'e1');
    });

    testWidgets("…and not to someone else's", (tester) async {
      final rig = _Rig(role: 'Warehouse Manager', userId: 'u1');
      rig.repo.expenses = [fixtureExpense('e2', createdById: 'someone-else')];
      await _pump(tester, _opener(const ExpenseDetailDialog(expenseId: 'e2')), rig: rig);
      await _open(tester);
      expect(find.byKey(const Key('expense-attach')), findsNothing);
    });
  });

  testWidgets('categories: add with a budget; one in use cannot be removed', (tester) async {
    final rig = _Rig();
    rig.repo.cats = [const ExpenseCategory(id: 'cat-rent', name: 'Rent', expenseCount: 3), const ExpenseCategory(id: 'cat-x', name: 'Spare')];
    await _pump(tester, _opener(const ExpenseCategoriesDialog()), rig: rig);
    await _open(tester);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('expense-category-delete-cat-rent'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('expense-category-name')), 'Security');
    await tester.enterText(find.byKey(const Key('expense-category-budget')), '80000');
    await tester.tap(find.byKey(const Key('expense-category-add')));
    await _settle(tester);
    expect(rig.repo.cats.last.name, 'Security');
    expect(rig.repo.cats.last.monthlyBudget, 80000);
    await tester.tap(find.byKey(const ValueKey('expense-category-delete-cat-x')));
    await _settle(tester);
    expect(rig.repo.cats.any((c) => c.id == 'cat-x'), isFalse);
  });

  test('expensesProvider asks the server only with expenses.view', () async {
    final repo = FakeExpensesRepository(expenses: _expenses());
    for (final (role, expected) in [('Owner', 5), ('Sales Staff', 0)]) {
      final container = ProviderContainer(
        overrides: [authControllerProvider.overrideWith(() => _Auth(role)), ...fakeDataOverrides(expenses: repo)],
      );
      await container.read(authControllerProvider.future);
      expect((await container.read(expensesProvider.future)).length, expected, reason: role);
      container.dispose();
    }
  });
}
