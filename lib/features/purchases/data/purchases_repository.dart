import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/outbox.dart';
import '../../../shared/offline/persisted_list.dart';
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
import '../domain/legacy_purchase.dart';
import '../domain/purchase.dart';

/// What a receipt changed: the purchase afterwards, and any product whose
/// purchase price moved to the cost just paid.
class ReceiveOutcome {
  const ReceiveOutcome({required this.purchase, required this.priceChanges});

  final Purchase purchase;
  final List<({String productId, double previous, double next})> priceChanges;
}

/// REAL `/api/v1/purchases`. Creating a purchase can be queued offline
/// (sent later with its op id as the clientRef, so it's never recorded
/// twice); receiving, payments, edits and cancelling need a connection.
class PurchasesRepository {
  PurchasesRepository(this._api);

  final AuthedApi _api;

  Future<List<Purchase>> list() async {
    final json = await _api.get(ApiConstants.purchases, cacheKey: 'purchases');
    return [
      for (final row in (json['purchases'] as List<dynamic>? ?? const []))
        Purchase.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<Purchase> get(String id) async {
    final json = await _api.get(ApiConstants.purchase(id));
    return Purchase.fromJson(json['purchase'] as Map<String, dynamic>);
  }

  Future<Purchase> create(PurchaseInput input, {String? clientRef}) async {
    final json = await _api.post(ApiConstants.purchases, {
      ...input.toJson(),
      'clientRef': ?clientRef,
    });
    return Purchase.fromJson(json['purchase'] as Map<String, dynamic>);
  }

  /// Any subset of the fields `PATCH /purchases/{id}` takes.
  Future<Purchase> update(String id, Map<String, dynamic> changes) async {
    final json = await _api.patch(ApiConstants.purchase(id), changes);
    return Purchase.fromJson(json['purchase'] as Map<String, dynamic>);
  }

  /// [lines] is what arrived per line id; `null` receives everything
  /// outstanding.
  Future<ReceiveOutcome> receive(String id, {Map<String, int>? lines}) async {
    final json = await _api.post(
      ApiConstants.purchaseReceive(id),
      lines == null
          ? {'all': true}
          : {
              'lines': [
                for (final entry in lines.entries) {'lineId': entry.key, 'quantity': entry.value},
              ],
            },
    );
    return ReceiveOutcome(
      purchase: Purchase.fromJson(json['purchase'] as Map<String, dynamic>),
      priceChanges: [
        for (final row in (json['priceChanges'] as List<dynamic>? ?? const []))
          (
            productId: (row as Map<String, dynamic>)['productId'] as String,
            previous: (row['previous'] as num?)?.toDouble() ?? 0,
            next: (row['new'] as num?)?.toDouble() ?? 0,
          ),
      ],
    );
  }

  Future<Purchase> pay(String id, {required double amount, String? note}) async {
    final json = await _api.post(ApiConstants.purchasePayments(id), {
      'amount': amount,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return Purchase.fromJson(json['purchase'] as Map<String, dynamic>);
  }

  /// Returns the purchase and how much the supplier now owes back (money
  /// paid on it before it was cancelled).
  Future<({Purchase purchase, double refundOwed})> cancel(String id) async {
    final json = await _api.post(ApiConstants.purchaseCancel(id), const {});
    return (
      purchase: Purchase.fromJson(json['purchase'] as Map<String, dynamic>),
      refundOwed: (json['refundOwed'] as num?)?.toDouble() ?? 0,
    );
  }
}

final purchasesRepositoryProvider = Provider<PurchasesRepository>(
  (ref) => PurchasesRepository(ref.watch(authedApiProvider)),
);

class PurchasesNotifier extends AsyncNotifier<List<Purchase>> {
  @override
  Future<List<Purchase>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    if (!ref.watch(holdsPermissionProvider(Permissions.purchasesView))) return const [];
    // A payment on a supplier's account can settle purchases.
    ref.watch(debtsChangedProvider);
    return ref.watch(purchasesRepositoryProvider).list();
  }

  Future<void> refresh() async {
    if (!ref.read(holdsPermissionProvider(Permissions.purchasesView))) return;
    state = await AsyncValue.guard(ref.read(purchasesRepositoryProvider).list);
  }

  /// Records a purchase — now if the connection is good, otherwise saved on
  /// this computer and sent later (it shows as "waiting to sync").
  Future<SubmitResult<Purchase>> add(PurchaseInput input) async {
    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.purchaseCreate,
      payload: {'input': input.toJson()},
      createdAt: DateTime.now(),
    );
    final result = await ref
        .read(syncEngineProvider.notifier)
        .submit(op, () => ref.read(purchasesRepositoryProvider).create(input, clientRef: op.id));
    if (!result.queued) await _afterChange(stockMoved: input.receive);
    return result;
  }

  Future<Purchase> edit(String id, PurchaseInput input) async {
    final purchase = await ref.read(purchasesRepositoryProvider).update(id, input.toEditJson());
    await _afterChange(purchaseId: id);
    return purchase;
  }

  Future<Purchase> placeOrder(String id) async {
    final purchase = await ref.read(purchasesRepositoryProvider).update(id, {'status': 'pending'});
    await _afterChange(purchaseId: id);
    return purchase;
  }

  Future<ReceiveOutcome> receive(String id, {Map<String, int>? lines}) async {
    final outcome = await ref.read(purchasesRepositoryProvider).receive(id, lines: lines);
    await _afterChange(purchaseId: id, stockMoved: true);
    return outcome;
  }

  Future<Purchase> pay(String id, {required double amount, String? note}) async {
    final purchase = await ref
        .read(purchasesRepositoryProvider)
        .pay(id, amount: amount, note: note);
    await _afterChange(purchaseId: id);
    return purchase;
  }

  Future<double> cancel(String id) async {
    final result = await ref.read(purchasesRepositoryProvider).cancel(id);
    await _afterChange(purchaseId: id);
    return result.refundOwed;
  }

  /// Purchases touch stock, prices, the supplier's balance and the valuation,
  /// so everything those screens show is re-read.
  Future<void> _afterChange({String? purchaseId, bool stockMoved = false}) async {
    if (purchaseId != null) ref.invalidate(purchaseDetailProvider(purchaseId));
    await Future.wait([
      refresh(),
      ref.read(partiesProvider(PartyType.supplier).notifier).refresh(),
      if (stockMoved) ...[
        ref.read(productsProvider.notifier).refresh(),
        ref.read(movementsProvider.notifier).refresh(),
        ref.read(stockAlertsProvider.notifier).refresh(),
        ref.read(warehousesProvider.notifier).refresh(),
      ],
    ]);
    ref.invalidate(creditEntriesProvider);
    ref.invalidate(valuationReportProvider);
  }
}

final purchasesProvider = AsyncNotifierProvider<PurchasesNotifier, List<Purchase>>(
  PurchasesNotifier.new,
);

/// One purchase with its receipts and payments, straight from the server.
final purchaseDetailProvider = FutureProvider.autoDispose.family<Purchase, String>((ref, id) {
  ref.watch(debtsChangedProvider);
  return ref.watch(purchasesRepositoryProvider).get(id);
});

/// Purchases from one supplier, for the supplier's history.
final supplierPurchasesProvider = Provider.family<List<Purchase>, String>((ref, supplierId) {
  final all = ref.watch(purchasesProvider).valueOrNull ?? const <Purchase>[];
  return all.where((p) => p.supplierId == supplierId).toList();
});

/// Purchases saved on this computer by older versions of the app, waiting to
/// be imported (or dismissed). Nothing new is ever added here.
class LegacyPurchasesNotifier extends PersistedListNotifier<LegacyPurchase> {
  @override
  String get name => 'purchases';

  @override
  Map<String, dynamic> encode(LegacyPurchase item) => item.toJson();

  @override
  LegacyPurchase decode(Map<String, dynamic> json) => LegacyPurchase.fromJson(json);

  /// Forgets [id] once it has been imported or dismissed.
  void remove(String id) => setAndSave([
    for (final p in state)
      if (p.id != id) p,
  ]);
}

final legacyPurchasesProvider = NotifierProvider<LegacyPurchasesNotifier, List<LegacyPurchase>>(
  LegacyPurchasesNotifier.new,
);
