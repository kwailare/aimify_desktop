// LIVE end-to-end check of the dashboard's business overview against a
// running aimify-web (`npm run dev` on http://localhost:3000): this month's
// sales, gross and net profit, expenses, debts and stock as the server works
// them out, the year by month, the figures refreshing after an expense is
// recorded in the app, and Sales Staff seeing no expenses or net profit.
// Same repositories and providers the screen uses, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with a Lagos warehouse, an Owner and a
// Sales Staff member, where this month one sale of 3 bags of rice (cost
// 60,000, price 70,000 each) was made to a customer who paid 100,000, 20
// bags were stocked in, and a 25,000 "Rent" expense was recorded:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//   AIMIFY_SALES_EMAIL=...
//
//   flutter test test/live/live_dashboard_test.dart

import 'dart:async';
import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/dashboard/data/business_summary.dart';
import 'package:aimify_desktop/features/expenses/data/expenses_repository.dart';
import 'package:aimify_desktop/features/expenses/domain/expense.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
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

/// Waits for the summary to satisfy [ok], re-reading as it refreshes.
Future<BusinessSummary> _summary(ProviderContainer c, DashboardPeriod period, [bool Function(BusinessSummary)? ok]) async {
  final done = Completer<BusinessSummary>();
  final sub = c.listen<AsyncValue<BusinessSummary?>>(businessSummaryProvider(period), (_, next) {
    final s = next.valueOrNull;
    if (s != null && !next.isLoading && (ok == null || ok(s)) && !done.isCompleted) done.complete(s);
  }, fireImmediately: true);
  try {
    return await done.future.timeout(const Duration(seconds: 30));
  } finally {
    sub.close();
  }
}

void main() {
  test(
    'the business overview against the real backend',
    () async {
      final c = await _signIn(_need('AIMIFY_OWNER_EMAIL'));
      // Keep this month's summary alive, as the screen would.
      final keep = c.listen(businessSummaryProvider(DashboardPeriod.month), (_, _) {});
      addTearDown(keep.close);

      final month = await _summary(c, DashboardPeriod.month);
      expect(month.bucket, 'day');
      final sales = month.sales!;
      expect(sales.total, 210000);
      expect(sales.count, 1);
      expect(sales.revenue, 210000);
      expect(sales.cogs, 180000);
      expect(sales.grossProfit, 30000);
      expect(sales.margin, closeTo(14.29, 0.01));
      expect(sales.trend.single.value, 210000);
      final today = DateTime.now();
      expect(sales.trend.single.bucket, DateTime(today.year, today.month, today.day));
      expect(sales.topProducts.single.units, 3);
      expect(sales.topCustomers.single.name, 'Ada Stores');
      expect(sales.byWarehouse.single.name, 'Lagos');
      expect(month.expenses!.total, 25000);
      expect(month.expenses!.byCategory.single.name, 'Rent');
      expect(month.netProfit, 5000);
      expect(month.receivables!.owed, 110000);
      expect(month.receivables!.parties, 1);
      expect(month.payables!.owed, 0);
      expect(month.stock!.valueAtCost, 17 * 60000);

      final year = await _summary(c, DashboardPeriod.year);
      expect(year.bucket, 'month');
      expect(year.sales!.total, 210000);
      expect(year.sales!.trend.single.bucket, DateTime(today.year, today.month));

      final lastMonth = await _summary(c, DashboardPeriod.lastMonth);
      expect(lastMonth.sales!.total, 0);
      expect(lastMonth.sales!.trend, isEmpty);

      // Recording an expense in the app refreshes the figures.
      await c.read(expensesProvider.future);
      final rent = (await c.read(expenseCategoriesProvider.future)).firstWhere((x) => x.name == 'Rent');
      final added = await c.read(expensesProvider.notifier).add(
            ExpenseInput(categoryId: rent.id, amount: 5000, expenseDate: DateTime.now(), paymentMethod: SalePaymentMethod.cash),
          );
      expect(added.queued, isFalse);
      final after = await _summary(c, DashboardPeriod.month, (s) => s.expenses!.total == 30000);
      expect(after.netProfit, 0);

      // Sales Staff see sales, but no expenses or net profit.
      final staff = await _signIn(_need('AIMIFY_SALES_EMAIL'));
      final theirs = await _summary(staff, DashboardPeriod.month);
      expect(theirs.sales!.total, 210000);
      expect(theirs.expenses, isNull);
      expect(theirs.netProfit, isNull);
      expect(theirs.purchases, isNull);
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
