// LIVE end-to-end check of expenses against a running aimify-web
// (`npm run dev` on http://localhost:3000): categories and budgets, an
// expense with a receipt (a real upload, removed again), editing, voiding,
// a recurring expense recorded once even when pressed twice, uploading an
// old local expense, and the report. Same repositories and notifiers the
// screens use, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with two active warehouses (Lagos and
// Kano) and an Owner:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...
//   AIMIFY_OWNER_EMAIL=...
//
//   flutter test test/live/live_expenses_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/expenses/data/expense_report.dart';
import 'package:aimify_desktop/features/expenses/data/expenses_repository.dart';
import 'package:aimify_desktop/features/expenses/domain/expense.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_token_storage.dart';

final _env = Platform.environment;
final _live = _env['AIMIFY_LIVE'] == '1';
String _need(String name) => _env[name] ?? (throw StateError('Set $name'));

// A 1×1 PNG.
const _png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41,
  0x54, 0x78, 0xda, 0x63, 0xf8, 0xff, 0xff, 0x3f, 0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0xd6, 0xa4, 0xa0, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

void main() {
  test(
    'expenses against the real backend',
    () async {
      final c = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      await c
          .read(authControllerProvider.notifier)
          .login(email: _need('AIMIFY_OWNER_EMAIL'), password: _need('AIMIFY_PASSWORD'));
      expect(c.read(authControllerProvider).value!.hasPermission('expenses.manage'), isTrue);

      final lagos = (await c.read(warehousesProvider.future)).firstWhere((w) => w.name == 'Lagos').id;

      // Categories with budgets.
      final categories = c.read(expenseCategoriesProvider.notifier);
      await c.read(expenseCategoriesProvider.future);
      await categories.add('Live Fuel', monthlyBudget: 50000);
      await categories.add('Other');
      final fuel = c.read(expenseCategoriesProvider).value!.firstWhere((x) => x.name == 'Live Fuel');
      expect(fuel.monthlyBudget, 50000);

      // An expense with a receipt.
      final expenses = c.read(expensesProvider.notifier);
      await c.read(expensesProvider.future);
      final added = await expenses.add(
        ExpenseInput(
          categoryId: fuel.id,
          amount: 45000,
          expenseDate: DateTime.now(),
          paymentMethod: SalePaymentMethod.cash,
          warehouseId: lagos,
          payee: 'Total',
          description: 'Diesel',
        ),
      );
      expect(added.queued, isFalse, reason: 'the connection should be good for this test');
      final e = added.value!;
      expect(e.reference, startsWith('EXP-'));
      final attached = await expenses.attach(e.id, bytes: _png, filename: 'receipt.png');
      expect(attached.attachmentType, 'image/png');
      expect(attached.attachmentUrl, startsWith('https://'));

      // Edit and the report's budget.
      final edited = await expenses.edit(
        e.id,
        ExpenseInput(categoryId: fuel.id, amount: 60000, expenseDate: e.expenseDate, warehouseId: lagos, payee: 'Total', description: 'Diesel'),
      );
      expect(edited.amount, 60000);
      expect(edited.updatedByName, isNotNull);
      final now = DateTime.now();
      final report = buildExpenseReport(
        c.read(expensesProvider).value!,
        c.read(expenseCategoriesProvider).value!,
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      );
      expect(report.byCategory.firstWhere((x) => x.name == 'Live Fuel').overBudget, isTrue);

      // Remove the receipt (cleans storage) and void.
      final removed = await expenses.removeAttachment(e.id);
      expect(removed.attachmentUrl, isNull);
      final voided = await expenses.voidExpense(e.id, reason: 'Live test');
      expect(voided.isVoided, isTrue);
      try {
        await expenses.edit(e.id, ExpenseInput(categoryId: fuel.id, amount: 1, expenseDate: now));
        fail('a voided expense should not change');
      } on ApiException catch (err) {
        expect(err.statusCode, 409);
      }

      // A recurring expense, recorded once even when pressed twice.
      final recurring = c.read(recurringExpensesProvider.notifier);
      await c.read(recurringExpensesProvider.future);
      await recurring.save(null, {
        'categoryId': fuel.id,
        'description': 'Generator service',
        'amount': 15000,
        'frequency': 'monthly',
        'nextDueDate': DateTime.utc(now.year, now.month, 1).toIso8601String(),
      });
      final due = c.read(dueRecurringProvider).single;
      final results = await Future.wait([
        expenses.recordRecurring(due).then<Object>((x) => x, onError: (Object err) => err),
        expenses.recordRecurring(due).then<Object>((x) => x, onError: (Object err) => err),
      ]);
      expect(results.whereType<Expense>().length, 1);
      expect(results.whereType<ApiException>().single.code, 'already_recorded');
      expect(c.read(dueRecurringProvider), isEmpty, reason: 'next due a month later');

      // An old local expense uploads once.
      final legacy = legacyExpenseInput(
        LegacyExpense(id: 'old1', category: 'Snacks', amount: 900, date: DateTime(2026, 9, 3), paymentMethod: 'mobileMoney', note: 'Tea'),
        c.read(expenseCategoriesProvider).value!,
      )!;
      final first = await expenses.add(legacy, clientRef: 'legacy:old1');
      final again = await expenses.add(legacy, clientRef: 'legacy:old1');
      expect(again.value!.id, first.value!.id);
      expect(first.value!.categoryName, 'Other');
      expect(first.value!.description, 'Tea (was Snacks)');
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
