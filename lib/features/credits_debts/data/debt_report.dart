import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';

/// How old a debt is: not yet due, or 1–30 / 31–60 / 61–90 / over 90 days
/// past its due date.
enum AgeBucket { current, days1to30, days31to60, days61to90, over90 }

extension AgeBucketX on AgeBucket {
  String get apiKey => name;

  String get label => switch (this) {
        AgeBucket.current => 'Not yet due',
        AgeBucket.days1to30 => '1–30 days',
        AgeBucket.days31to60 => '31–60 days',
        AgeBucket.days61to90 => '61–90 days',
        AgeBucket.over90 => 'Over 90 days',
      };
}

Map<AgeBucket, double> _buckets(Map<dynamic, dynamic>? json) => {
      for (final b in AgeBucket.values) b: ((json ?? const {})[b.apiKey] as num?)?.toDouble() ?? 0,
    };

/// One debt still open: a sale, a purchase, a charge or an adjustment up.
class OpenDebt {
  const OpenDebt({
    required this.reference,
    required this.date,
    required this.dueDate,
    required this.amount,
    required this.openAmount,
    required this.daysOverdue,
    this.saleId,
    this.purchaseId,
  });

  final String reference;
  final DateTime date;
  final DateTime dueDate;
  final double amount;
  final double openAmount;
  final int daysOverdue;
  final String? saleId;
  final String? purchaseId;

  factory OpenDebt.fromJson(Map<String, dynamic> json) => OpenDebt(
        reference: json['reference'] as String? ?? 'Charge',
        date: DateTime.parse(json['date'] as String).toLocal(),
        dueDate: DateTime.parse(json['dueDate'] as String).toLocal(),
        amount: (json['amount'] as num).toDouble(),
        openAmount: (json['openAmount'] as num).toDouble(),
        daysOverdue: (json['daysOverdue'] as num?)?.toInt() ?? 0,
        saleId: json['saleId'] as String?,
        purchaseId: json['purchaseId'] as String?,
      );
}

/// One customer's or supplier's debt by age.
class DebtorRow {
  const DebtorRow({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    required this.isActive,
    required this.balance,
    this.creditLimit,
    required this.paymentTermsDays,
    required this.buckets,
    required this.overdue,
    required this.maxDaysOverdue,
    this.lastPaymentAt,
    this.daysSinceLastPayment,
    this.items = const [],
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final bool isActive;

  /// Negative when they are in credit.
  final double balance;
  final double? creditLimit;
  final int paymentTermsDays;
  final Map<AgeBucket, double> buckets;
  final double overdue;
  final int maxDaysOverdue;
  final DateTime? lastPaymentAt;
  final int? daysSinceLastPayment;
  final List<OpenDebt> items;

  factory DebtorRow.fromJson(Map<String, dynamic> json) => DebtorRow(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        isActive: json['status'] != 'archived',
        balance: (json['balance'] as num).toDouble(),
        creditLimit: (json['creditLimit'] as num?)?.toDouble(),
        paymentTermsDays: (json['paymentTermsDays'] as num?)?.toInt() ?? 30,
        buckets: _buckets(json['buckets'] as Map?),
        overdue: (json['overdue'] as num?)?.toDouble() ?? 0,
        maxDaysOverdue: (json['maxDaysOverdue'] as num?)?.toInt() ?? 0,
        lastPaymentAt: DateTime.tryParse(json['lastPaymentAt'] as String? ?? '')?.toLocal(),
        daysSinceLastPayment: (json['daysSinceLastPayment'] as num?)?.toInt(),
        items: [
          for (final row in (json['items'] as List<dynamic>? ?? const [])) OpenDebt.fromJson(row as Map<String, dynamic>),
        ],
      );
}

/// `GET /api/v1/reports/debts` — what is owed, by age, as of [asOf].
class DebtReport {
  const DebtReport({
    required this.asOf,
    required this.type,
    required this.balance,
    required this.overdue,
    required this.credit,
    required this.buckets,
    required this.parties,
  });

  final DateTime asOf;
  final PartyType type;

  /// What is owed in all (parties in credit not counted).
  final double balance;
  final double overdue;

  /// What the business holds in credit for parties (owed back).
  final double credit;
  final Map<AgeBucket, double> buckets;

  /// Most overdue first.
  final List<DebtorRow> parties;

  /// Who to chase first: overdue debts, biggest first.
  List<DebtorRow> get toChase => parties.where((p) => p.overdue > 0).toList()
    ..sort((a, b) => b.overdue.compareTo(a.overdue) != 0 ? b.overdue.compareTo(a.overdue) : b.maxDaysOverdue.compareTo(a.maxDaysOverdue));

  factory DebtReport.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    return DebtReport(
      asOf: DateTime.parse(json['asOf'] as String).toLocal(),
      type: PartyTypeX.fromApi(json['partyType'] as String? ?? 'customer'),
      balance: (totals['balance'] as num?)?.toDouble() ?? 0,
      overdue: (totals['overdue'] as num?)?.toDouble() ?? 0,
      credit: (totals['credit'] as num?)?.toDouble() ?? 0,
      buckets: _buckets(totals),
      parties: [
        for (final row in (json['parties'] as List<dynamic>? ?? const [])) DebtorRow.fromJson(row as Map<String, dynamic>),
      ],
    );
  }
}

class DebtReportRepository {
  DebtReportRepository(this._api);

  final AuthedApi _api;

  /// Falls back to the last saved copy offline (the report says when it was
  /// made).
  Future<DebtReport> fetch(PartyType type) async {
    final json = await _api.get('${ApiConstants.debtReport}?partyType=${type.apiValue}', cacheKey: 'debts_${type.apiValue}');
    return DebtReport.fromJson(json);
  }
}

final debtReportRepositoryProvider = Provider<DebtReportRepository>(
  (ref) => DebtReportRepository(ref.watch(authedApiProvider)),
);

/// The report for one side; re-read when payments or balances change.
final debtReportProvider = FutureProvider.autoDispose.family<DebtReport?, PartyType>((ref, type) {
  final permission = type == PartyType.customer ? Permissions.customersView : Permissions.suppliersView;
  if (ref.watch(sessionUserIdProvider) == null || !ref.watch(holdsPermissionProvider(permission))) {
    return null;
  }
  ref.watch(debtsChangedProvider);
  ref.watch(partiesProvider(type));
  return ref.watch(debtReportRepositoryProvider).fetch(type);
});
