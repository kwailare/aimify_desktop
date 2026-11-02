// The business overview on the dashboard (feature checklist step 13): the
// summary models, the periods and what each is compared with, the cards and
// charts per role, switching the period, errors, the dark theme and narrow
// windows.

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/dashboard/data/business_summary.dart';
import 'package:aimify_desktop/features/dashboard/presentation/widgets/business_overview.dart';
import 'package:aimify_desktop/shared/utils/formatters.dart';
import 'package:aimify_desktop/shared/widgets/async_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';

class _Auth extends AuthController {
  _Auth(this.role);

  final String role;

  @override
  Future<MeResponse?> build() async => MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
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

Future<FakeBusinessSummaryRepository> _pump(
  WidgetTester tester, {
  String role = 'Owner',
  Map<String, dynamic>? json,
  ThemeData? theme,
  double width = 1280,
  Object? error,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = FakeBusinessSummaryRepository(json)..error = error;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(role)),
        ...fakeDataOverrides(summary: repo),
      ],
      child: MaterialApp(
        theme: theme ?? ThemeData(),
        home: const Scaffold(
          body: SingleChildScrollView(padding: EdgeInsets.all(24), child: BusinessOverview()),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return repo;
}

Map<String, dynamic> _only(List<String> keys) {
  final all = fixtureSummaryJson();
  return {
    'bucket': 'day',
    for (final k in keys) k: all[k],
  };
}

void main() {
  group('BusinessSummary.fromJson', () {
    test('reads every section', () {
      final s = BusinessSummary.fromJson(DashboardPeriod.month, fixtureSummaryJson(now: DateTime(2026, 11, 2)));
      expect(s.bucket, 'day');
      expect(s.sales!.total, 210000);
      expect(s.sales!.grossProfit, 50000);
      expect(s.sales!.margin, 25);
      expect(s.sales!.change, 40);
      expect(s.sales!.previousTotal, 150000);
      expect(s.sales!.trend.first.bucket, DateTime(2026, 11, 1));
      expect(s.sales!.trend.last.second, 30000);
      expect(s.sales!.topProducts.first.name, 'Golden Penny Rice 50kg');
      expect(s.sales!.topProducts.first.units, 2);
      expect(s.sales!.topCustomers.single.count, 2);
      expect(s.sales!.byWarehouse.single.warehouseId, 'w1');
      expect(s.purchases!.total, 300000);
      expect(s.purchases!.change, isNull);
      expect(s.expenses!.byCategory.single.name, 'Rent');
      expect(s.netProfit, 30000);
      expect(s.netProfitChange, 0);
      expect(s.receivables!.overdue, 25000);
      expect(s.payables!.owed, 100000);
      expect(s.stock!.byWarehouse.single.valueAtCost, 900000);
      expect(s.hasMoney, isTrue);
    });

    test('a saved copy shows only what this person may see', () {
      final all = BusinessSummary.fromJson(DashboardPeriod.month, fixtureSummaryJson());
      final sales = all.onlyWhat((p) => p == 'sales.view' || p == 'customers.view');
      expect(sales.sales, isNotNull);
      expect(sales.receivables, isNotNull);
      expect(sales.expenses, isNull);
      expect(sales.netProfit, isNull, reason: 'net profit needs expenses too');
      expect(sales.purchases, isNull);
      expect(sales.payables, isNull);
      expect(sales.stock, isNull);
      expect(all.onlyWhat((_) => true).netProfit, 30000);
    });

    test('sections the role may not see are left out', () {
      final s = BusinessSummary.fromJson(DashboardPeriod.today, _only(['stock']));
      expect(s.sales, isNull);
      expect(s.netProfit, isNull);
      expect(s.receivables, isNull);
      expect(s.stock, isNotNull);
      expect(s.hasMoney, isFalse);
    });
  });

  group('DashboardPeriod', () {
    final now = DateTime(2026, 11, 4, 15, 30); // a Wednesday

    test('today against yesterday', () {
      expect(DashboardPeriod.today.ranges(now),
          (DateTime(2026, 11, 4), DateTime(2026, 11, 5), DateTime(2026, 11, 3), DateTime(2026, 11, 4)));
    });

    test('this week from Monday, against last week', () {
      expect(DashboardPeriod.week.ranges(now),
          (DateTime(2026, 11, 2), DateTime(2026, 11, 9), DateTime(2026, 10, 26), DateTime(2026, 11, 2)));
    });

    test('this month against last month', () {
      expect(DashboardPeriod.month.ranges(now),
          (DateTime(2026, 11), DateTime(2026, 12), DateTime(2026, 10), DateTime(2026, 11)));
    });

    test('last month across a new year', () {
      expect(DashboardPeriod.lastMonth.ranges(DateTime(2027, 1, 10)),
          (DateTime(2026, 12), DateTime(2027, 1), DateTime(2026, 11), DateTime(2026, 12)));
    });

    test('this year by month, against last year', () {
      expect(DashboardPeriod.year.ranges(now), (DateTime(2026), DateTime(2027), DateTime(2025), DateTime(2026)));
      expect(DashboardPeriod.year.bucket, 'month');
      expect(DashboardPeriod.month.bucket, 'day');
      expect(DashboardPeriod.year.versus, 'vs last year');
    });
  });

  group('BusinessOverview', () {
    testWidgets('an Owner sees every card, change and chart', (tester) async {
      await _pump(tester);
      expect(find.text('Business overview'), findsOneWidget);
      for (final k in ['sales', 'gross', 'net', 'expenses', 'purchases', 'receivables', 'payables']) {
        expect(find.byKey(Key('kpi-$k')), findsOneWidget, reason: k);
      }
      expect(find.text(currencyFormat.format(210000)), findsWidgets);
      expect(find.text('25.0% margin'), findsOneWidget);
      expect(find.text('▲ 40.0% vs last month'), findsOneWidget);
      expect(find.text('▲ 100.0% vs last month'), findsOneWidget); // expenses up
      expect(find.text('Nothing vs last month to compare'), findsOneWidget); // purchases had none
      expect(find.text('${currencyFormat.format(25000)} overdue'), findsOneWidget);
      for (final k in ['sales-trend', 'money-flow', 'top-sellers', 'debt-warehouses']) {
        expect(find.byKey(Key('chart-$k')), findsOneWidget, reason: k);
      }
      expect(find.text('Golden Penny Rice 50kg'), findsOneWidget);
      expect(find.text('Ada Stores'), findsOneWidget);
      expect(find.text('Main Warehouse'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expenses going up are red, sales going up are not', (tester) async {
      await _pump(tester);
      final theme = Theme.of(tester.element(find.byKey(const Key('kpi-expenses'))));
      final expensesUp = tester.widget<Text>(find.text('▲ 100.0% vs last month'));
      final salesUp = tester.widget<Text>(find.text('▲ 40.0% vs last month'));
      expect(expensesUp.style!.color, theme.colorScheme.error);
      expect(salesUp.style!.color, isNot(theme.colorScheme.error));
    });

    testWidgets('a loss shows in red', (tester) async {
      final json = fixtureSummaryJson();
      json['netProfit'] = {'value': -5000, 'previous': 1000, 'change': -600};
      await _pump(tester, json: json);
      expect(find.text('▼ 600.0% vs last month'), findsOneWidget);
      final value = tester.widget<Text>(find.descendant(of: find.byKey(const Key('kpi-net')), matching: find.text(currencyFormat.format(-5000))));
      expect(value.style!.color, Theme.of(tester.element(find.byKey(const Key('kpi-net')))).colorScheme.error);
    });

    testWidgets('Sales Staff see sales only: no net profit and no money in vs out', (tester) async {
      await _pump(tester, role: 'Sales Staff', json: _only(['sales', 'receivables']));
      expect(find.byKey(const Key('kpi-sales')), findsOneWidget);
      expect(find.byKey(const Key('kpi-receivables')), findsOneWidget);
      expect(find.byKey(const Key('kpi-net')), findsNothing);
      expect(find.byKey(const Key('kpi-expenses')), findsNothing);
      expect(find.byKey(const Key('chart-money-flow')), findsNothing);
      expect(find.byKey(const Key('chart-sales-trend')), findsOneWidget);
    });

    testWidgets('a role with no money figures sees nothing', (tester) async {
      await _pump(tester, role: 'Inventory Staff', json: _only(['stock']));
      expect(find.text('Business overview'), findsNothing);
      expect(find.byKey(const Key('kpi-sales')), findsNothing);
    });

    testWidgets('choosing another period asks for it and relabels the changes', (tester) async {
      final repo = await _pump(tester);
      expect(repo.asked, [DashboardPeriod.month]);
      await tester.tap(find.byKey(const Key('dashboard-period')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('This year').last);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(repo.asked.last, DashboardPeriod.year);
      expect(find.text('▲ 40.0% vs last year'), findsOneWidget);
    });

    testWidgets('an error offers a retry', (tester) async {
      final repo = await _pump(tester, error: Exception('offline'));
      expect(find.byType(ErrorRetryCard), findsOneWidget);
      repo.error = null;
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('kpi-sales')), findsOneWidget);
    });

    testWidgets('readable in the dark theme', (tester) async {
      final dark = ThemeData(brightness: Brightness.dark);
      await _pump(tester, theme: dark);
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.descendant(of: find.byKey(const Key('kpi-sales')), matching: find.text(currencyFormat.format(210000))));
      expect(title.style!.color, dark.colorScheme.onSurface);
      final overdue = tester.widget<Text>(find.text('${currencyFormat.format(25000)} overdue'));
      expect(overdue.style!.color, dark.colorScheme.error);
      final card = tester.widget<Card>(find.descendant(of: find.byKey(const Key('kpi-sales')), matching: find.byType(Card)).first);
      expect(card.color, isNull, reason: 'cards take the theme colour, not a fixed one');
    });

    for (final width in [360.0, 700.0, 1000.0, 1600.0]) {
      testWidgets('no overflow at width $width', (tester) async {
        await _pump(tester, width: width);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('chart-sales-trend')), findsOneWidget);
      });
    }
  });
}
