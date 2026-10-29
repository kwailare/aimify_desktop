import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/outbox.dart';
import '../../../shared/offline/persisted_list.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sales/domain/sale.dart';
import '../../sync/sync_engine.dart';
import '../domain/expense.dart';

/// REAL `/api/v1/expenses`, `/expense-categories` and `/recurring-expenses`.
/// A new expense can be recorded offline (sent later with its op id as the
/// clientRef, so never twice); editing, voiding, receipts, categories and
/// recurring expenses need a connection.
class ExpensesRepository {
  ExpensesRepository(this._api);

  final AuthedApi _api;

  /// The last 13 months (enough for this year's and last year's same month),
  /// newest first.
  Future<List<Expense>> list() async {
    final now = DateTime.now();
    final from = DateTime(now.year - 1, now.month).toUtc().toIso8601String();
    final json = await _api.get(
      '${ApiConstants.expenses}?from=${Uri.encodeQueryComponent(from)}&limit=2000',
      cacheKey: 'expenses',
    );
    return [
      for (final row in (json['expenses'] as List<dynamic>? ?? const [])) Expense.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<Expense> get(String id) async =>
      Expense.fromJson((await _api.get(ApiConstants.expense(id)))['expense'] as Map<String, dynamic>);

  Future<Expense> create(ExpenseInput input, {String? clientRef}) async {
    final json = await _api.post(ApiConstants.expenses, {...input.toJson(), 'clientRef': ?clientRef});
    return Expense.fromJson(json['expense'] as Map<String, dynamic>);
  }

  Future<Expense> update(String id, ExpenseInput input) async {
    final json = await _api.patch(ApiConstants.expense(id), input.toJson());
    return Expense.fromJson(json['expense'] as Map<String, dynamic>);
  }

  Future<Expense> voidExpense(String id, {required String reason}) async {
    final json = await _api.post(ApiConstants.expenseVoid(id), {'reason': reason});
    return Expense.fromJson(json['expense'] as Map<String, dynamic>);
  }

  Future<Expense> attach(String id, {required List<int> bytes, required String filename}) async {
    final json = await _api.postFile(ApiConstants.expenseAttachment(id), field: 'file', bytes: bytes, filename: filename);
    return Expense.fromJson(json['expense'] as Map<String, dynamic>);
  }

  Future<Expense> removeAttachment(String id) async {
    final json = await _api.delete(ApiConstants.expenseAttachment(id));
    return Expense.fromJson(json['expense'] as Map<String, dynamic>);
  }

  Future<List<ExpenseCategory>> categories() async {
    final json = await _api.get(ApiConstants.expenseCategories, cacheKey: 'expense_categories');
    return [
      for (final row in (json['categories'] as List<dynamic>? ?? const []))
        ExpenseCategory.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<ExpenseCategory> createCategory(String name, {double monthlyBudget = 0}) async {
    final json = await _api.post(ApiConstants.expenseCategories, {'name': name, 'monthlyBudget': monthlyBudget});
    return ExpenseCategory.fromJson(json['category'] as Map<String, dynamic>);
  }

  Future<ExpenseCategory> updateCategory(String id, {String? name, double? monthlyBudget}) async {
    final json = await _api.patch(ApiConstants.expenseCategory(id), {'name': ?name, 'monthlyBudget': ?monthlyBudget});
    return ExpenseCategory.fromJson(json['category'] as Map<String, dynamic>);
  }

  Future<void> deleteCategory(String id) => _api.delete(ApiConstants.expenseCategory(id));

  Future<List<RecurringExpense>> recurring() async {
    final json = await _api.get(ApiConstants.recurringExpenses, cacheKey: 'recurring_expenses');
    return [
      for (final row in (json['recurring'] as List<dynamic>? ?? const []))
        RecurringExpense.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<RecurringExpense> saveRecurring(String? id, Map<String, dynamic> fields) async {
    final json = id == null
        ? await _api.post(ApiConstants.recurringExpenses, fields)
        : await _api.patch(ApiConstants.recurringExpense(id), fields);
    return RecurringExpense.fromJson(json['recurring'] as Map<String, dynamic>);
  }

  Future<void> deleteRecurring(String id) => _api.delete(ApiConstants.recurringExpense(id));

  /// Records the occurrence due on [dueDate] (as the server sent it).
  Future<Expense> recordRecurring(String id, {required DateTime dueDate, double? amount}) async {
    final json = await _api.post(ApiConstants.recordRecurringExpense(id), {
      'dueDate': dueDate.toUtc().toIso8601String(),
      'amount': ?amount,
    });
    return Expense.fromJson(json['expense'] as Map<String, dynamic>);
  }
}

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) => ExpensesRepository(ref.watch(authedApiProvider)));

class ExpensesNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    if (!ref.watch(holdsPermissionProvider(Permissions.expensesView))) return const [];
    return ref.watch(expensesRepositoryProvider).list();
  }

  Future<void> refresh() async {
    if (!ref.read(holdsPermissionProvider(Permissions.expensesView))) return;
    state = await AsyncValue.guard(ref.read(expensesRepositoryProvider).list);
  }

  /// Records an expense — now on a good connection, otherwise saved on this
  /// computer and sent later.
  Future<SubmitResult<Expense>> add(ExpenseInput input, {String? clientRef}) async {
    final op = OutboxOp(
      id: clientRef ?? newOpId(),
      kind: OpKind.expenseCreate,
      payload: {'input': input.toJson()},
      createdAt: DateTime.now(),
    );
    final result = await ref.read(syncEngineProvider.notifier).submit(
          op,
          () => ref.read(expensesRepositoryProvider).create(input, clientRef: op.id),
        );
    if (!result.queued) await _changed();
    return result;
  }

  Future<Expense> edit(String id, ExpenseInput input) async {
    final expense = await ref.read(expensesRepositoryProvider).update(id, input);
    await _changed();
    return expense;
  }

  Future<Expense> voidExpense(String id, {required String reason}) async {
    final expense = await ref.read(expensesRepositoryProvider).voidExpense(id, reason: reason);
    await _changed();
    return expense;
  }

  Future<Expense> attach(String id, {required List<int> bytes, required String filename}) async {
    final expense = await ref.read(expensesRepositoryProvider).attach(id, bytes: bytes, filename: filename);
    await _changed();
    return expense;
  }

  Future<Expense> removeAttachment(String id) async {
    final expense = await ref.read(expensesRepositoryProvider).removeAttachment(id);
    await _changed();
    return expense;
  }

  Future<Expense> recordRecurring(RecurringExpense r, {double? amount}) async {
    final expense = await ref.read(expensesRepositoryProvider).recordRecurring(r.id, dueDate: r.nextDueDate, amount: amount);
    await _changed();
    await ref.read(recurringExpensesProvider.notifier).refresh();
    return expense;
  }

  Future<void> _changed() async {
    await refresh();
    ref.invalidate(expenseCategoriesProvider);
  }
}

final expensesProvider = AsyncNotifierProvider<ExpensesNotifier, List<Expense>>(ExpensesNotifier.new);

/// Whether this person can record expenses (and so read categories and what
/// is due).
final canRecordExpensesProvider = Provider<bool>(
  (ref) => ref.watch(holdsPermissionProvider(Permissions.expensesCreate)),
);

class ExpenseCategoriesNotifier extends AsyncNotifier<List<ExpenseCategory>> {
  @override
  Future<List<ExpenseCategory>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    if (!ref.watch(holdsPermissionProvider(Permissions.expensesView)) && !ref.watch(canRecordExpensesProvider)) {
      return const [];
    }
    return ref.watch(expensesRepositoryProvider).categories();
  }

  Future<void> refresh() async => state = await AsyncValue.guard(ref.read(expensesRepositoryProvider).categories);

  Future<void> add(String name, {double monthlyBudget = 0}) async {
    await ref.read(expensesRepositoryProvider).createCategory(name, monthlyBudget: monthlyBudget);
    await refresh();
  }

  /// A rename shows on every expense of the category, so they are re-read.
  Future<void> edit(String id, {String? name, double? monthlyBudget}) async {
    await ref.read(expensesRepositoryProvider).updateCategory(id, name: name, monthlyBudget: monthlyBudget);
    await Future.wait([refresh(), ref.read(expensesProvider.notifier).refresh()]);
  }

  Future<void> remove(String id) async {
    await ref.read(expensesRepositoryProvider).deleteCategory(id);
    await refresh();
  }
}

final expenseCategoriesProvider =
    AsyncNotifierProvider<ExpenseCategoriesNotifier, List<ExpenseCategory>>(ExpenseCategoriesNotifier.new);

class RecurringExpensesNotifier extends AsyncNotifier<List<RecurringExpense>> {
  @override
  Future<List<RecurringExpense>> build() async {
    if (ref.watch(sessionUserIdProvider) == null || !ref.watch(canRecordExpensesProvider)) return const [];
    return ref.watch(expensesRepositoryProvider).recurring();
  }

  Future<void> refresh() async {
    if (!ref.read(canRecordExpensesProvider)) return;
    state = await AsyncValue.guard(ref.read(expensesRepositoryProvider).recurring);
  }

  Future<void> save(String? id, Map<String, dynamic> fields) async {
    await ref.read(expensesRepositoryProvider).saveRecurring(id, fields);
    await refresh();
  }

  Future<void> remove(String id) async {
    await ref.read(expensesRepositoryProvider).deleteRecurring(id);
    await refresh();
  }
}

final recurringExpensesProvider =
    AsyncNotifierProvider<RecurringExpensesNotifier, List<RecurringExpense>>(RecurringExpensesNotifier.new);

/// Recurring expenses due now (and not paused).
final dueRecurringProvider = Provider<List<RecurringExpense>>(
  (ref) => (ref.watch(recurringExpensesProvider).valueOrNull ?? const <RecurringExpense>[]).where((r) => r.due).toList(),
);

/// Expenses saved on this computer by older versions, waiting to be uploaded
/// (or dismissed). Nothing new is ever added here.
class LegacyExpensesNotifier extends PersistedListNotifier<LegacyExpense> {
  @override
  String get name => 'expenses';

  @override
  Map<String, dynamic> encode(LegacyExpense item) => item.toJson();

  @override
  LegacyExpense decode(Map<String, dynamic> json) => LegacyExpense.fromJson(json);

  void remove(String id) => setAndSave([
        for (final e in state)
          if (e.id != id) e,
      ]);
}

final legacyExpensesProvider = NotifierProvider<LegacyExpensesNotifier, List<LegacyExpense>>(LegacyExpensesNotifier.new);

/// The expense input for an old local expense: its category matched by name
/// (ignoring case and spacing), else "Other", else the first category.
ExpenseInput? legacyExpenseInput(LegacyExpense e, List<ExpenseCategory> categories) {
  if (categories.isEmpty) return null;
  String key(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final category = categories.where((c) => key(c.name) == key(e.category)).firstOrNull ??
      categories.where((c) => key(c.name) == 'other').firstOrNull ??
      categories.first;
  final matched = key(category.name) == key(e.category);
  final description = [
    if (e.note.trim().isNotEmpty) e.note.trim(),
    if (!matched) '(was ${e.category})',
  ].join(' ');
  return ExpenseInput(
    categoryId: category.id,
    amount: e.amount,
    expenseDate: e.date,
    paymentMethod: e.method,
    description: description.isEmpty ? null : description,
  );
}

/// What this month has cost so far (recorded expenses only).
final expensesThisMonthProvider = Provider<double>((ref) {
  final now = DateTime.now();
  return (ref.watch(expensesProvider).valueOrNull ?? const <Expense>[])
      .where((e) => !e.isVoided && e.expenseDate.year == now.year && e.expenseDate.month == now.month)
      .fold(0.0, (sum, e) => sum + e.amount);
});

typedef ExpenseMethod = SalePaymentMethod;
