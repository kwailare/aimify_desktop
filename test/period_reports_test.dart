// The period reports (feature checklist step 14): periods, reading what the
// server sends, the report documents (the same tables on screen, in the PDF
// and in Excel), and the Reports screen's tabs per role, filters, periods,
// export, errors, the dark theme and narrow windows.

import 'dart:typed_data';

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/documents/document_kit.dart';
import 'package:aimify_desktop/features/documents/document_preview.dart';
import 'package:aimify_desktop/features/documents/report_documents.dart';
import 'package:aimify_desktop/features/reports/data/period_reports.dart';
import 'package:aimify_desktop/features/reports/data/report_document.dart';
import 'package:aimify_desktop/features/reports/presentation/reports_screen.dart';
import 'package:aimify_desktop/shared/utils/formatters.dart';
import 'package:aimify_desktop/shared/widgets/async_state.dart';
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
        user: AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
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
  final opened = <String>[];
  Uint8List? bytes;

  @override
  Future<void> open(BuildContext context, WidgetRef ref, {required String title, required String fileName, required DocumentBuilder build}) async {
    bytes = await build(await DocumentKit.load(_org));
    opened.add(fileName);
  }
}

final _october = ReportRange.custom(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
ReportQuery _q(ReportKind kind, [Map<String, String> filters = const {}]) => ReportQuery(kind, _october, filters);

SalesReport _sales() => SalesReport.fromJson(_q(ReportKind.sales), fixtureReportJson(ReportKind.sales));
PurchasesReport _purchases() => PurchasesReport.fromJson(_q(ReportKind.purchases), fixtureReportJson(ReportKind.purchases));
ProfitLossReport _pl([Map<String, String> filters = const {}]) =>
    ProfitLossReport.fromJson(_q(ReportKind.profitLoss, filters), fixtureReportJson(ReportKind.profitLoss));
StockMovementsReport _stock() =>
    StockMovementsReport.fromJson(_q(ReportKind.stockMovements), fixtureReportJson(ReportKind.stockMovements));

Future<(FakePeriodReportsRepository, _FakeOpener)> _pump(
  WidgetTester tester, {
  String role = 'Owner',
  ThemeData? theme,
  double width = 1400,
  FakePeriodReportsRepository? reports,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = reports ?? FakePeriodReportsRepository();
  final opener = _FakeOpener();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(role)),
        documentOpenerProvider.overrideWithValue(opener),
        reportRangeProvider.overrideWith((ref) => _october),
        ...fakeDataOverrides(reports: repo),
      ],
      child: MaterialApp(theme: theme ?? ThemeData(), home: const ReportsScreen()),
    ),
  );
  await _settle(tester);
  return (repo, opener);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byKey(const Key('reports-tabs')), matching: find.text(label)));
  await _settle(tester);
}

Future<void> _choose(WidgetTester tester, Key menu, String option) async {
  await tester.tap(find.byKey(menu));
  await _settle(tester);
  await tester.tap(find.widgetWithText(MenuItemButton, option).last);
  await _settle(tester);
}

List<String> _tabs(WidgetTester tester) => tester
    .widget<SegmentedButton<Object>>(find.byKey(const Key('reports-tabs')))
    .segments
    .map((s) => (s.label as Text).data!)
    .toList();

void main() {
  group('ReportRange', () {
    final now = DateTime(2026, 11, 4, 15); // a Wednesday

    test('the presets', () {
      expect(ReportRange.of(ReportPreset.today, now).from, DateTime(2026, 11, 4));
      expect(ReportRange.of(ReportPreset.thisWeek, now).from, DateTime(2026, 11, 2));
      expect(ReportRange.of(ReportPreset.thisWeek, now).to, DateTime(2026, 11, 9));
      expect(ReportRange.of(ReportPreset.lastMonth, now).from, DateTime(2026, 10));
      final q = ReportRange.of(ReportPreset.thisQuarter, now);
      expect((q.from, q.to), (DateTime(2026, 10), DateTime(2027)));
      final y = ReportRange.of(ReportPreset.last12Months, now);
      expect((y.from, y.to), (DateTime(2025, 12), DateTime(2026, 12)));
    });

    test('custom dates include the last day', () {
      final r = ReportRange.custom(DateTime(2026, 10, 3, 18), DateTime(2026, 10, 9));
      expect(r.from, DateTime(2026, 10, 3));
      expect(r.to, DateTime(2026, 10, 10));
      expect(r.dates, '3 Oct 2026 – 9 Oct 2026');
      expect(r.label, r.dates);
      expect(r.slug, '2026-10-03_2026-10-09');
      expect(_october.slug, '2026-10');
      expect(ReportRange.custom(DateTime(2026, 10, 3), DateTime(2026, 10, 3)).dates, '3 Oct 2026');
    });

    test('queries with the same filters are the same', () {
      expect(_q(ReportKind.sales, {'a': '1', 'b': '2'}), _q(ReportKind.sales, {'b': '2', 'a': '1'}));
      expect(_q(ReportKind.sales, {'a': '1'}).hashCode, _q(ReportKind.sales, {'a': '1'}).hashCode);
      expect(_q(ReportKind.sales, {'a': '1'}), isNot(_q(ReportKind.sales, {'a': '2'})));
      expect(_q(ReportKind.sales), isNot(_q(ReportKind.purchases)));
    });
  });

  group('reading the reports', () {
    test('sales', () {
      final r = _sales();
      expect(r.totals.total, 1385);
      expect(r.totals.margin, 33.33);
      expect(r.voidedCount, 1);
      expect(r.byPeriod[1].bucket, DateTime(2026, 10, 20));
      expect(r.byCustomer.first.id, isNull);
      expect(r.byCustomer.first.name, 'Walk-in');
      expect(r.byStaff.last.id, 'u2');
      expect(r.sales.last.reference, 'INV-0001');
      expect(r.sales.last.outstanding, 235);
      expect(r.people.length, 2);
    });

    test('purchases', () {
      final r = _purchases();
      expect(r.totals.unpaid, 5050);
      expect(r.orderedValue, 6350);
      expect(r.byStatus.first.status, 'pending');
      expect(r.byProduct.single.averageCost, 100);
      expect(r.purchases.first.status, 'pending');
    });

    test('profit & loss', () {
      final r = _pl();
      expect(r.netProfit, 200);
      expect(r.expensesByCategory.map((c) => c.name), ['Rent', 'Fuel']);
      expect(r.moneyIn, 1300);
      expect(r.moneyOut, 1550);
      expect(r.netCash, -250);
      expect(r.inByMethod.first.method, 'cash');
      expect(r.byPeriod.last.netProfit, -200);
    });

    test('stock history', () {
      final r = _stock();
      expect(r.totals.net, 93);
      expect(r.movements.first.reference, 'INV-0002');
      expect(r.movements.first.source, 'sale');
      expect(r.byProduct.single.netValue, 9300);
      expect(r.byUser.last.figures.unitsOut, 4);
    });
  });

  group('report documents', () {
    test('every cell formats in its column', () {
      for (final doc in [
        salesDocument(_sales(), const []),
        purchasesDocument(_purchases(), const []),
        profitLossDocument(_pl(), const []),
        stockMovementsDocument(_stock(), const []),
      ]) {
        for (final s in doc.sections) {
          for (final row in [...s.rows, ?s.footer]) {
            expect(row.length, s.columns.length, reason: '${doc.title} · ${s.title}');
            for (final (i, v) in row.indexed) {
              expect(() => formatCell(v, s.columns[i].kind), returnsNormally, reason: '${doc.title} · ${s.title} · ${s.columns[i].label}');
            }
          }
        }
      }
    });

    test('sales: headline figures and tables', () {
      final doc = salesDocument(_sales(), const [('Warehouse', 'Kano')]);
      expect(doc.fileStem, 'sales-report-2026-10');
      expect(doc.kpis.first.value, currencyFormat.format(1385));
      expect(doc.kpis.first.caption, '3 sales · 12 units');
      expect(doc.kpis.firstWhere((k) => k.label == 'Outstanding').tone, KpiTone.bad);
      expect(doc.kpis.last.caption, '1 voided sale (${currencyFormat.format(150)}) not counted');
      expect(doc.sections.map((s) => s.title), ['By day', 'By product', 'By customer', 'By staff', 'By warehouse', 'Sales']);
      expect(doc.sections.first.footer![3], 1385);
      expect(doc.notes, isEmpty);
      final byProduct = salesDocument(SalesReport.fromJson(_q(ReportKind.sales, {'productId': 'p1'}), fixtureReportJson(ReportKind.sales)), const []);
      expect(byProduct.notes.single, contains('chosen product'));
    });

    test('profit & loss: the statement, with subtotals in bold', () {
      final doc = profitLossDocument(_pl(), const []);
      final statement = doc.sections.first;
      expect(statement.rows.map((r) => r.first), [
        'Sales (goods, before tax)',
        'Less discounts',
        'Net sales',
        'Less cost of goods sold',
        'Gross profit',
        'Less Rent',
        'Less Fuel',
        'Total expenses',
        'Net profit',
      ]);
      expect(statement.rows.last[1], 200);
      expect(statement.rows.last[2], closeTo(14.81, 0.01));
      expect(statement.strongRows, {2, 4, 8});
      final cash = doc.sections[1];
      expect([for (final i in cash.strongRows) cash.rows[i].first], containsAll(['Money in', 'Money out', 'Net cash']));
      expect(doc.kpis.last.tone, KpiTone.bad);
      expect(doc.notes.first, contains('tax collected'));
    });

    test('profit & loss for one warehouse leaves account payments out', () {
      final doc = profitLossDocument(_pl({'warehouseId': 'w1'}), const [('Warehouse', 'Main Warehouse')]);
      final cash = doc.sections[1];
      expect(cash.rows.map((r) => r.first), isNot(contains('Received on customer accounts')));
      expect([for (final i in cash.strongRows) cash.rows[i].first], ['Money in', 'Money out', 'Net cash']);
      expect(doc.notes.last, contains('one warehouse'));
    });

    test('Excel: a summary sheet and a sheet per table, with numbers as numbers', () {
      final doc = salesDocument(_sales(), const [('Warehouse', 'Kano')]);
      final book = Excel.decodeBytes(buildReportExcel(doc));
      expect(book.tables.keys, containsAll(['Summary', 'By day', 'By product', 'By customer', 'By staff', 'By warehouse', 'Sales']));
      final summary = book.tables['Summary']!;
      expect(summary.rows[1][1]!.value.toString(), _october.dates);
      expect(summary.rows[2][0]!.value.toString(), 'Warehouse');
      final list = book.tables['Sales']!;
      expect(list.rows.first.map((c) => c?.value.toString()), contains('Outstanding'));
      expect(list.rows[1][0]!.value.toString(), 'INV-0005');
      expect(list.rows[1][1]!.value.toString(), '2026-10-25');
      final owed = list.rows[3][9]!.value;
      expect(owed is DoubleCellValue ? owed.value : (owed as IntCellValue).value, 235);
      final stock = Excel.decodeBytes(buildReportExcel(stockMovementsDocument(_stock(), const [])));
      expect((stock.tables['Movements']!.rows[1][4]!.value as IntCellValue).value, -4);
    });

    test('PDF: every report prints', () async {
      final kit = await DocumentKit.load(_org);
      for (final doc in [
        salesDocument(_sales(), const []),
        purchasesDocument(_purchases(), const []),
        profitLossDocument(_pl(), const []),
        stockMovementsDocument(_stock(), const []),
      ]) {
        final bytes = await buildReportPdf(kit, doc);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: doc.title);
      }
    });
  });

  group('the Reports screen', () {
    testWidgets('the Owner sees every report', (tester) async {
      await _pump(tester);
      expect(_tabs(tester), ['Overview', 'Valuation', 'Sales', 'Purchases', 'Profit & loss', 'Stock history']);
    });

    for (final (role, tabs) in [
      ('Sales Staff', ['Overview', 'Valuation', 'Sales', 'Stock history']),
      ('Accountant / Finance', ['Overview', 'Valuation', 'Sales', 'Purchases', 'Profit & loss', 'Stock history']),
      ('Inventory Staff', ['Overview', 'Valuation', 'Stock history']),
      ('Warehouse Manager', ['Overview', 'Valuation', 'Purchases', 'Stock history']),
    ]) {
      testWidgets('$role sees the reports for their modules', (tester) async {
        await _pump(tester, role: role);
        expect(_tabs(tester), tabs);
      });
    }

    testWidgets('sales: figures, tables, filters and the period', (tester) async {
      final (repo, _) = await _pump(tester);
      await _openTab(tester, 'Sales');
      expect(repo.asked.last, _q(ReportKind.sales));
      expect(find.text(currencyFormat.format(1385)), findsWidgets);
      expect(find.text('3 sales · 12 units'), findsOneWidget);
      expect(find.text(_october.dates), findsOneWidget);
      // The first table is by day; the totals row is at the bottom.
      expect(find.text('Total'), findsWidgets);
      await tester.tap(find.byKey(const Key('section-2')));
      await _settle(tester);
      expect(find.text('Walk-in'), findsOneWidget);
      expect(find.text('Ada Stores'), findsOneWidget);
      await tester.tap(find.byKey(const Key('section-5')));
      await _settle(tester);
      expect(find.text('INV-0001'), findsOneWidget);

      await _choose(tester, const Key('filter-customerId'), 'Walk-in customers');
      expect(repo.asked.last.filters, {'customerId': 'walk-in'});
      await _choose(tester, const Key('filter-userId'), 'Sade Sales');
      expect(repo.asked.last.filters, {'customerId': 'walk-in', 'userId': 'u2'});
      expect(find.byKey(const Key('report-clear-filters')), findsOneWidget);
      await tester.tap(find.byKey(const Key('report-clear-filters')));
      await _settle(tester);
      expect(repo.asked.last.filters, isEmpty);

      await _choose(tester, const Key('report-range'), 'This year');
      expect(repo.asked.last.range.preset, ReportPreset.thisYear);
      expect(tester.takeException(), isNull);
    });

    testWidgets('profit & loss: the statement and money in and out', (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Profit & loss');
      expect(find.text('Net profit'), findsWidgets);
      expect(find.text('Less Rent'), findsOneWidget);
      expect(find.textContaining('tax collected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('section-1')));
      await _settle(tester);
      expect(find.text('Received on customer accounts'), findsOneWidget);
      expect(find.text(currencyFormat.format(-250)), findsWidgets);
    });

    testWidgets('purchases and stock history show their tables', (tester) async {
      final (repo, _) = await _pump(tester);
      await _openTab(tester, 'Purchases');
      expect(find.text('Dangote Foods'), findsNothing); // by day first
      await tester.tap(find.byKey(const Key('section-1')));
      await _settle(tester);
      expect(find.text('Dangote Foods'), findsOneWidget);
      await _openTab(tester, 'Stock history');
      expect(repo.asked.last.kind, ReportKind.stockMovements);
      expect(find.text('INV-0002'), findsOneWidget);
      expect(find.text('Damaged'), findsOneWidget);
      await _choose(tester, const Key('filter-type'), 'Adjustment');
      expect(repo.asked.last.filters, {'type': 'adjustment'});
    });

    testWidgets('Print / PDF and an empty table', (tester) async {
      final repo = FakePeriodReportsRepository({
        ReportKind.purchases: {...fixtureReportJson(ReportKind.purchases), 'byPeriod': <Object>[]},
      });
      final (_, opener) = await _pump(tester, reports: repo);
      await _openTab(tester, 'Purchases');
      expect(find.byKey(const Key('report-empty')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('report-pdf')));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await _settle(tester);
      expect(opener.opened, ['purchase-report-2026-10.pdf']);
      expect(String.fromCharCodes(opener.bytes!.take(5)), '%PDF-');
    });

    testWidgets('long tables show 200 rows, then all', (tester) async {
      final json = fixtureReportJson(ReportKind.stockMovements);
      final one = (json['movements'] as List).first as Map<String, dynamic>;
      final repo = FakePeriodReportsRepository({
        ReportKind.stockMovements: {
          ...json,
          'movements': [for (var i = 0; i < 230; i++) {...one, 'id': 'm$i'}],
        },
      });
      await _pump(tester, reports: repo);
      await _openTab(tester, 'Stock history');
      expect(find.textContaining('Showing 200 of 230'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('report-show-all')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('report-show-all')));
      await _settle(tester);
      expect(find.byKey(const Key('report-show-all')), findsNothing);
    });

    testWidgets('an error offers a retry', (tester) async {
      final repo = FakePeriodReportsRepository()..error = Exception('offline');
      await _pump(tester, reports: repo);
      await _openTab(tester, 'Sales');
      expect(find.byType(ErrorRetryCard), findsOneWidget);
      repo.error = null;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(find.text('3 sales · 12 units'), findsOneWidget);
    });

    testWidgets('readable in the dark theme', (tester) async {
      final dark = ThemeData(brightness: Brightness.dark);
      await _pump(tester, theme: dark);
      await _openTab(tester, 'Profit & loss');
      expect(tester.takeException(), isNull);
      final cash = tester.widget<Text>(find.descendant(of: find.byKey(const Key('kpi-Net cash')), matching: find.text(currencyFormat.format(-250))));
      expect(cash.style!.color, dark.colorScheme.error);
      final sales = tester.widget<Text>(find.descendant(of: find.byKey(const Key('kpi-Net sales')), matching: find.text(currencyFormat.format(1350))));
      expect(sales.style!.color, dark.colorScheme.onSurface);
      final card = tester.widget<Card>(find.byKey(const Key('report-table')));
      expect(card.color, isNull, reason: 'the table card takes the theme colour');
    });

    for (final width in [420.0, 800.0, 1200.0]) {
      testWidgets('no overflow at width $width', (tester) async {
        await _pump(tester, width: width);
        for (final tab in ['Sales', 'Purchases', 'Profit & loss', 'Stock history']) {
          final tabs = find.byKey(const Key('reports-tabs'));
          final label = find.descendant(of: tabs, matching: find.text(tab));
          await tester.ensureVisible(label);
          await _settle(tester);
          await tester.tap(label);
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: tab);
        }
      });
    }
  });
}
