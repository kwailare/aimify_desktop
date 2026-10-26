import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/outbox.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../products/data/products_repository.dart';
import '../../reports/data/valuation_report.dart';
import '../../sync/sync_engine.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../domain/sale.dart';

/// What recording a sale returned: the sale, and any product it took down
/// to its reorder level or out of stock.
class SaleOutcome {
  const SaleOutcome({required this.sale, this.alerts = const []});

  final Sale sale;
  final List<({String productId, String alert})> alerts;
}

/// REAL `/api/v1/sales`. A sale can be recorded offline (sent later with
/// its op id as the clientRef, so it's never recorded twice); payments and
/// voiding need a connection.
class SalesRepository {
  SalesRepository(this._api);

  final AuthedApi _api;

  Future<List<Sale>> list() async {
    final json = await _api.get('${ApiConstants.sales}?limit=200', cacheKey: 'sales');
    return [
      for (final row in (json['sales'] as List<dynamic>? ?? const [])) Sale.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// One customer's sales, newest first (up to 200).
  Future<List<Sale>> listForCustomer(String customerId) async {
    final json = await _api.get(
      '${ApiConstants.sales}?customerId=$customerId&limit=200',
      cacheKey: 'sales_customer_$customerId',
    );
    return [
      for (final row in (json['sales'] as List<dynamic>? ?? const [])) Sale.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<Sale> get(String id) async {
    final json = await _api.get(ApiConstants.sale(id));
    return Sale.fromJson(json['sale'] as Map<String, dynamic>);
  }

  Future<SaleOutcome> create(SaleInput input, {String? clientRef}) async {
    final json = await _api.post(ApiConstants.sales, {...input.toJson(), 'clientRef': ?clientRef});
    return SaleOutcome(
      sale: Sale.fromJson(json['sale'] as Map<String, dynamic>),
      alerts: [
        for (final row in (json['alerts'] as List<dynamic>? ?? const []))
          (
            productId: (row as Map<String, dynamic>)['productId'] as String,
            alert: row['alert'] as String,
          ),
      ],
    );
  }

  Future<Sale> pay(String id, {required double amount, required SalePaymentMethod method, String? note}) async {
    final json = await _api.post(ApiConstants.salePayments(id), {
      'amount': amount,
      'method': method.apiValue,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return Sale.fromJson(json['sale'] as Map<String, dynamic>);
  }

  /// Returns the sale and how much is now owed back to the customer.
  Future<({Sale sale, double refundOwed})> voidSale(String id, {required String reason}) async {
    final json = await _api.post(ApiConstants.saleVoid(id), {'reason': reason});
    return (
      sale: Sale.fromJson(json['sale'] as Map<String, dynamic>),
      refundOwed: (json['refundOwed'] as num?)?.toDouble() ?? 0,
    );
  }
}

final salesRepositoryProvider = Provider<SalesRepository>((ref) => SalesRepository(ref.watch(authedApiProvider)));

class SalesNotifier extends AsyncNotifier<List<Sale>> {
  @override
  Future<List<Sale>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    if (!ref.watch(holdsPermissionProvider(Permissions.salesView))) return const [];
    return ref.watch(salesRepositoryProvider).list();
  }

  Future<void> refresh() async {
    if (!ref.read(holdsPermissionProvider(Permissions.salesView))) return;
    state = await AsyncValue.guard(ref.read(salesRepositoryProvider).list);
  }

  /// Records a sale — now if the connection is good, otherwise saved on this
  /// computer and sent later (the stock and the customer's balance change
  /// on screen at once).
  Future<SubmitResult<SaleOutcome>> add(SaleInput input) async {
    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.saleCreate,
      payload: {'input': input.toJson()},
      createdAt: DateTime.now(),
    );
    final result = await ref.read(syncEngineProvider.notifier).submit(
          op,
          () => ref.read(salesRepositoryProvider).create(input, clientRef: op.id),
        );
    if (!result.queued) await _afterChange(stockMoved: true);
    return result;
  }

  Future<Sale> pay(String id, {required double amount, required SalePaymentMethod method, String? note}) async {
    final sale = await ref.read(salesRepositoryProvider).pay(id, amount: amount, method: method, note: note);
    await _afterChange(saleId: id);
    return sale;
  }

  Future<double> voidSale(String id, {required String reason}) async {
    final result = await ref.read(salesRepositoryProvider).voidSale(id, reason: reason);
    await _afterChange(saleId: id, stockMoved: true);
    return result.refundOwed;
  }

  /// Sales touch stock, the customer's balance and the valuation, so
  /// everything those screens show is re-read.
  Future<void> _afterChange({String? saleId, bool stockMoved = false}) async {
    if (saleId != null) ref.invalidate(saleDetailProvider(saleId));
    await Future.wait([
      refresh(),
      ref.read(partiesProvider(PartyType.customer).notifier).refresh(),
      if (stockMoved) ...[
        ref.read(productsProvider.notifier).refresh(),
        ref.read(movementsProvider.notifier).refresh(),
        ref.read(stockAlertsProvider.notifier).refresh(),
        ref.read(warehousesProvider.notifier).refresh(),
      ],
    ]);
    ref.invalidate(creditEntriesProvider);
    ref.invalidate(valuationReportProvider);
    ref.invalidate(customerSaleHistoryProvider);
  }
}

final salesProvider = AsyncNotifierProvider<SalesNotifier, List<Sale>>(SalesNotifier.new);

/// One sale with its payments, straight from the server.
final saleDetailProvider = FutureProvider.autoDispose.family<Sale, String>(
  (ref, id) => ref.watch(salesRepositoryProvider).get(id),
);

/// All of one customer's sales (not only the latest 200 of everyone's),
/// for the customer's page.
final customerSaleHistoryProvider = FutureProvider.autoDispose.family<List<Sale>, String>((ref, customerId) {
  if (customerId.startsWith('local:') || !ref.watch(holdsPermissionProvider(Permissions.salesView))) {
    return const <Sale>[];
  }
  return ref.watch(salesRepositoryProvider).listForCustomer(customerId);
});

/// Sales to one customer, for the customer's history.
final customerSalesProvider = Provider.family<List<Sale>, String>((ref, customerId) {
  final all = ref.watch(salesProvider).valueOrNull ?? const <Sale>[];
  return all.where((s) => s.customerId == customerId).toList();
});
