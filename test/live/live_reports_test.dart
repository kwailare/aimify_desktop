// LIVE end-to-end check of the period reports against a running aimify-web
// (`npm run dev` on http://localhost:3000): the sales, purchase, profit &
// loss and stock movement reports for this month with filters, their
// spreadsheets, and Sales Staff seeing sales but not profit & loss or
// purchases. Same repositories and providers the screen uses, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with a Lagos warehouse, an Owner and a
// Sales Staff member, where this month: 20 bags of rice (cost 60,000, price
// 70,000) were stocked in; Ada Stores bought 3 and paid 100,000; 10 more were
// bought from Dangote at 60,000, received, with 100,000 paid; and 25,000
// "Rent" was spent:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//   AIMIFY_SALES_EMAIL=...
//
//   flutter test test/live/live_reports_test.dart

import 'dart:async';
import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/reports/data/period_reports.dart';
import 'package:aimify_desktop/features/reports/data/report_document.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_token_storage.dart';

final _env = Platform.environment;
final _live = _env['AIMIFY_LIVE'] == '1';
String _need(String name) => _env[name] ?? (throw StateError('Set $name'));

Future<ProviderContainer> _signIn(String email) async {
  final c = ProviderContainer(
    overrides: [
      secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
    ],
  );
  addTearDown(c.dispose);
  await c.read(authControllerProvider.future);
  await c.read(authControllerProvider.notifier).login(email: email, password: _need('AIMIFY_PASSWORD'));
  return c;
}

/// Reads an auto-disposing report, kept alive until it arrives.
Future<T> _read<T>(ProviderContainer c, ProviderListenable<AsyncValue<T>> provider) async {
  final done = Completer<T>();
  final sub = c.listen<AsyncValue<T>>(provider, (_, next) {
    if (done.isCompleted || next.isLoading) return;
    next.whenOrNull(data: done.complete, error: (e, s) => done.completeError(e, s));
  }, fireImmediately: true);
  try {
    return await done.future.timeout(const Duration(seconds: 30));
  } finally {
    sub.close();
  }
}

void main() {
  test(
    'the period reports against the real backend',
    () async {
      final c = await _signIn(_need('AIMIFY_OWNER_EMAIL'));
      final month = ReportRange.of(ReportPreset.thisMonth, DateTime.now());
      ReportQuery q(ReportKind kind, [Map<String, String> filters = const {}]) => ReportQuery(kind, month, filters);

      // Sales.
      final sales = (await _read(c, salesReportProvider(q(ReportKind.sales))))!;
      expect(sales.totals.count, 1);
      expect(sales.totals.total, 210000);
      expect(sales.totals.revenue, 210000);
      expect(sales.totals.cogs, 180000);
      expect(sales.totals.grossProfit, 30000);
      expect(sales.totals.paid, 100000);
      expect(sales.totals.outstanding, 110000);
      expect(sales.byCustomer.single.name, 'Ada Stores');
      expect(sales.byStaff.single.name, 'Owner Live');
      expect(sales.byProduct.single.units, 3);
      expect(sales.sales.single.reference, startsWith('INV-'));
      expect(sales.people.map((p) => p.name), containsAll(['Owner Live', 'Sales Live']));
      final walkIns = (await _read(c, salesReportProvider(q(ReportKind.sales, {'customerId': 'walk-in'}))))!;
      expect(walkIns.totals.count, 0);
      final salesDoc = salesDocument(sales, const []);
      final book = Excel.decodeBytes(buildReportExcel(salesDoc));
      expect(book.tables['Sales']!.rows[1][0]!.value.toString(), sales.sales.single.reference);

      // Purchases.
      final purchases = (await _read(c, purchasesReportProvider(q(ReportKind.purchases))))!;
      expect(purchases.totals.count, 1);
      expect(purchases.totals.total, 600000);
      expect(purchases.totals.paid, 100000);
      expect(purchases.totals.unpaid, 500000);
      expect(purchases.totals.unitsReceived, 10);
      expect(purchases.bySupplier.single.name, 'Dangote');
      expect(purchases.byStatus.single.status, 'received');

      // Profit & loss, and money in and out.
      final pl = (await _read(c, profitLossReportProvider(q(ReportKind.profitLoss))))!;
      expect(pl.netSales, 210000);
      expect(pl.cogs, 180000);
      expect(pl.grossProfit, 30000);
      expect(pl.expenses, 25000);
      expect(pl.expensesByCategory.single.name, 'Rent');
      expect(pl.netProfit, 5000);
      expect(pl.inFromSales, 100000);
      expect(pl.moneyIn, 100000);
      expect(pl.outOnPurchases, 100000);
      expect(pl.outOnExpenses, 25000);
      expect(pl.moneyOut, 125000);
      expect(pl.netCash, -25000);
      expect(profitLossDocument(pl, const []).sections.first.rows.last.first, 'Net profit');

      // Stock movement history.
      final stock = (await _read(c, stockMovementsReportProvider(q(ReportKind.stockMovements))))!;
      expect(stock.totals.count, 3);
      expect(stock.totals.unitsIn, 30);
      expect(stock.totals.unitsOut, 3);
      expect(stock.movements.where((m) => m.source == 'purchase').single.reference, startsWith('PO-'));
      final fromSales = (await _read(c, stockMovementsReportProvider(q(ReportKind.stockMovements, {'source': 'sale'}))))!;
      expect(fromSales.totals.count, 1);
      expect(fromSales.movements.single.quantity, -3);

      // Sales Staff: sales and stock history, not purchases or profit & loss.
      final staff = await _signIn(_need('AIMIFY_SALES_EMAIL'));
      expect(staff.read(canSeeReportProvider(ReportKind.sales)), isTrue);
      expect(staff.read(canSeeReportProvider(ReportKind.stockMovements)), isTrue);
      expect(staff.read(canSeeReportProvider(ReportKind.purchases)), isFalse);
      expect(staff.read(canSeeReportProvider(ReportKind.profitLoss)), isFalse);
      expect((await _read(staff, salesReportProvider(q(ReportKind.sales))))!.totals.total, 210000);
      expect(await _read(staff, profitLossReportProvider(q(ReportKind.profitLoss))), isNull);
      // And the server agrees, even when asked directly.
      try {
        await staff.read(periodReportsRepositoryProvider).fetch(q(ReportKind.profitLoss));
        fail('Sales Staff should not get profit & loss');
      } on ApiException catch (e) {
        expect(e.statusCode, 403);
      }
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
