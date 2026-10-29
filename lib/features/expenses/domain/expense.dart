import '../../sales/domain/sale.dart';

/// Expenses exactly as `/api/v1/expenses` returns them. See "Expenses" in
/// `docs/desktop-api.md`. Payment methods are the same as for sales.
enum ExpenseStatus { recorded, voided }

class Expense {
  const Expense({
    required this.id,
    required this.reference,
    required this.categoryId,
    required this.categoryName,
    this.description,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod = SalePaymentMethod.cash,
    this.warehouseId,
    this.warehouseName,
    this.payee,
    this.receiptNumber,
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentType,
    this.status = ExpenseStatus.recorded,
    this.voidReason,
    this.voidedAt,
    this.voidedByName,
    this.recurringId,
    this.createdById,
    this.createdByName,
    this.createdAt,
    this.updatedByName,
    this.updatedAt,
  });

  final String id;
  final String reference;
  final String categoryId;
  final String categoryName;
  final String? description;
  final double amount;
  final DateTime expenseDate;
  final SalePaymentMethod paymentMethod;
  final String? warehouseId;
  final String? warehouseName;
  final String? payee;

  /// The supplier's receipt or invoice number.
  final String? receiptNumber;
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentType;
  final ExpenseStatus status;
  final String? voidReason;
  final DateTime? voidedAt;
  final String? voidedByName;
  final String? recurringId;
  final String? createdById;
  final String? createdByName;
  final DateTime? createdAt;
  final String? updatedByName;
  final DateTime? updatedAt;

  bool get isVoided => status == ExpenseStatus.voided;
  bool get hasAttachment => attachmentUrl != null;
  bool get attachmentIsPdf => attachmentType == 'application/pdf';

  /// What the list shows: the description, else the payee, else the category.
  String get title => description ?? payee ?? categoryName;

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        reference: json['reference'] as String,
        categoryId: json['categoryId'] as String,
        categoryName: json['categoryName'] as String? ?? 'Expense',
        description: json['description'] as String?,
        amount: (json['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(json['expenseDate'] as String).toLocal(),
        paymentMethod: SalePaymentMethodX.fromApi(json['paymentMethod'] as String?),
        warehouseId: json['warehouseId'] as String?,
        warehouseName: json['warehouseName'] as String?,
        payee: json['payee'] as String?,
        receiptNumber: json['receiptNumber'] as String?,
        attachmentUrl: json['attachmentUrl'] as String?,
        attachmentName: json['attachmentName'] as String?,
        attachmentType: json['attachmentType'] as String?,
        status: json['status'] == 'voided' ? ExpenseStatus.voided : ExpenseStatus.recorded,
        voidReason: json['voidReason'] as String?,
        voidedAt: _date(json['voidedAt']),
        voidedByName: json['voidedByName'] as String?,
        recurringId: json['recurringId'] as String?,
        createdById: json['createdBy'] as String?,
        createdByName: json['createdByName'] as String?,
        createdAt: _date(json['createdAt']),
        updatedByName: json['updatedByName'] as String?,
        updatedAt: _date(json['updatedAt']),
      );
}

/// What the expense form sends (and what is queued offline).
class ExpenseInput {
  const ExpenseInput({
    required this.categoryId,
    required this.amount,
    required this.expenseDate,
    this.paymentMethod = SalePaymentMethod.cash,
    this.warehouseId,
    this.payee,
    this.receiptNumber,
    this.description,
  });

  final String categoryId;
  final double amount;
  final DateTime expenseDate;
  final SalePaymentMethod paymentMethod;
  final String? warehouseId;
  final String? payee;
  final String? receiptNumber;
  final String? description;

  Map<String, dynamic> toJson() => {
        'categoryId': categoryId,
        'amount': amount,
        'expenseDate': expenseDate.toUtc().toIso8601String(),
        'paymentMethod': paymentMethod.apiValue,
        'warehouseId': warehouseId,
        'payee': payee,
        'receiptNumber': receiptNumber,
        'description': description,
      };

  factory ExpenseInput.fromJson(Map<String, dynamic> json) => ExpenseInput(
        categoryId: json['categoryId'] as String,
        amount: (json['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(json['expenseDate'] as String).toLocal(),
        paymentMethod: SalePaymentMethodX.fromApi(json['paymentMethod'] as String?),
        warehouseId: json['warehouseId'] as String?,
        payee: json['payee'] as String?,
        receiptNumber: json['receiptNumber'] as String?,
        description: json['description'] as String?,
      );
}

class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.name, this.monthlyBudget = 0, this.expenseCount = 0});

  final String id;
  final String name;

  /// 0 means no budget.
  final double monthlyBudget;
  final int expenseCount;

  bool get hasBudget => monthlyBudget > 0;

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) => ExpenseCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        monthlyBudget: (json['monthlyBudget'] as num?)?.toDouble() ?? 0,
        expenseCount: (json['expenseCount'] as num?)?.toInt() ?? 0,
      );
}

enum Frequency { weekly, monthly, yearly }

extension FrequencyX on Frequency {
  String get label => switch (this) {
        Frequency.weekly => 'Weekly',
        Frequency.monthly => 'Monthly',
        Frequency.yearly => 'Yearly',
      };

  static Frequency fromApi(String? value) => Frequency.values.where((f) => f.name == value).firstOrNull ?? Frequency.monthly;
}

class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.description,
    required this.amount,
    this.paymentMethod = SalePaymentMethod.cash,
    this.warehouseId,
    this.warehouseName,
    this.payee,
    required this.frequency,
    required this.nextDueDate,
    this.active = true,
    this.due = false,
  });

  final String id;
  final String categoryId;
  final String categoryName;
  final String description;
  final double amount;
  final SalePaymentMethod paymentMethod;
  final String? warehouseId;
  final String? warehouseName;
  final String? payee;
  final Frequency frequency;

  /// Exactly as the server sent it (UTC): sent back when recording, so a
  /// double click records once.
  final DateTime nextDueDate;
  final bool active;
  final bool due;

  factory RecurringExpense.fromJson(Map<String, dynamic> json) => RecurringExpense(
        id: json['id'] as String,
        categoryId: json['categoryId'] as String,
        categoryName: json['categoryName'] as String? ?? 'Expense',
        description: json['description'] as String,
        amount: (json['amount'] as num).toDouble(),
        paymentMethod: SalePaymentMethodX.fromApi(json['paymentMethod'] as String?),
        warehouseId: json['warehouseId'] as String?,
        warehouseName: json['warehouseName'] as String?,
        payee: json['payee'] as String?,
        frequency: FrequencyX.fromApi(json['frequency'] as String?),
        nextDueDate: DateTime.parse(json['nextDueDate'] as String),
        active: json['active'] as bool? ?? true,
        due: json['due'] as bool? ?? false,
      );
}

/// An expense saved on this computer by older versions of the app, waiting
/// to be uploaded (or dismissed). Its category is a name, matched to the
/// organization's categories when importing.
class LegacyExpense {
  const LegacyExpense({
    required this.id,
    required this.category,
    required this.amount,
    required this.date,
    required this.paymentMethod,
    required this.note,
  });

  final String id;
  final String category;
  final double amount;
  final DateTime date;

  /// The old names: cash, bankTransfer, card, mobileMoney.
  final String paymentMethod;
  final String note;

  /// The server's method for the old one (mobile money counts as a transfer).
  SalePaymentMethod get method => switch (paymentMethod) {
        'bankTransfer' || 'mobileMoney' => SalePaymentMethod.transfer,
        'card' => SalePaymentMethod.card,
        _ => SalePaymentMethod.cash,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'amount': amount,
        'date': date.toUtc().toIso8601String(),
        'paymentMethod': paymentMethod,
        'note': note,
      };

  factory LegacyExpense.fromJson(Map<String, dynamic> json) => LegacyExpense(
        id: json['id'] as String,
        category: json['category'] as String? ?? 'Other',
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String).toLocal(),
        paymentMethod: json['paymentMethod'] as String? ?? 'cash',
        note: json['note'] as String? ?? '',
      );
}
