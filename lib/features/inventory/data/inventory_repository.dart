import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/connection.dart';
import '../../../shared/offline/outbox.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../sync/sync_engine.dart';
import '../domain/stock_movement.dart';
import 'outbox_overlay.dart';

/// Products currently below their reorder level or out of stock, as
/// `GET /api/v1/alerts/stock` reports them.
class StockAlerts {
  const StockAlerts({this.lowStock = const [], this.outOfStock = const []});

  final List<Product> lowStock;
  final List<Product> outOfStock;

  bool get isEmpty => lowStock.isEmpty && outOfStock.isEmpty;
  int get total => lowStock.length + outOfStock.length;
}

/// REAL `/api/v1/inventory/movements` and `/api/v1/alerts/stock`.
///
/// Movements are the only way a product's stock ever changes.
class InventoryRepository {
  InventoryRepository(this._api);

  final AuthedApi _api;

  /// The 100 most recent movements, newest first. Falls back to the last
  /// saved copy when the network can't answer.
  Future<List<StockMovement>> movements() => _readMovements(cacheKey: 'movements');

  /// The ledger straight from the server — never the saved copy. Used to
  /// check whether an interrupted movement actually landed.
  Future<List<StockMovement>> movementsFresh() => _readMovements();

  Future<List<StockMovement>> _readMovements({String? cacheKey}) async {
    final json = await _api.get(ApiConstants.movements, cacheKey: cacheKey);
    return [
      for (final row in (json['movements'] as List<dynamic>? ?? const []))
        StockMovement.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// [quantity] is a signed whole-number delta: positive adds stock,
  /// negative removes it. The server applies it atomically.
  Future<MovementResult> record({
    required String productId,
    required String warehouseId,
    required StockMovementType type,
    required int quantity,
    String? reason,
  }) async {
    final json = await _api.post(ApiConstants.movements, {
      'productId': productId,
      'warehouseId': warehouseId,
      'type': type.apiValue,
      'quantity': quantity,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return MovementResult.fromJson(json);
  }

  Future<StockAlerts> alerts() async {
    final json = await _api.get(ApiConstants.stockAlerts, cacheKey: 'alerts');
    List<Product> parse(String key) => [
          for (final row in (json[key] as List<dynamic>? ?? const []))
            Product.fromJson(row as Map<String, dynamic>),
        ];
    return StockAlerts(lowStock: parse('lowStock'), outOfStock: parse('outOfStock'));
  }
}

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepository(ref.watch(authedApiProvider)),
);

class MovementsNotifier extends AsyncNotifier<List<StockMovement>> {
  @override
  Future<List<StockMovement>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    return ref.watch(inventoryRepositoryProvider).movements();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(ref.read(inventoryRepositoryProvider).movements);
  }

  /// Records a movement — now if the connection is good, otherwise saved on
  /// this computer and synced later (it shows in the ledger and moves the
  /// stock figure immediately, marked pending). [quantity] is the signed
  /// delta the server expects.
  Future<SubmitResult<MovementResult>> record({
    required String productId,
    required String warehouseId,
    required StockMovementType type,
    required int quantity,
    String? reason,
  }) async {
    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.movement,
      payload: {
        'productId': productId,
        'warehouseId': warehouseId,
        'type': type.apiValue,
        'quantity': quantity,
        'reason': reason?.trim().isEmpty ?? true ? null : reason!.trim(),
      },
      createdAt: DateTime.now(),
    );

    final result = await ref.read(syncEngineProvider.notifier).submit(
          op,
          () => ref.read(inventoryRepositoryProvider).record(
                productId: productId,
                warehouseId: warehouseId,
                type: type,
                quantity: quantity,
                reason: reason,
              ),
        );

    if (!result.queued) {
      await Future.wait([
        refresh(),
        ref.read(productsProvider.notifier).refresh(),
        ref.read(stockAlertsProvider.notifier).refresh(),
      ]);
    }
    return result;
  }
}

final movementsProvider =
    AsyncNotifierProvider<MovementsNotifier, List<StockMovement>>(MovementsNotifier.new);

/// The ledger: movements still waiting to sync (marked pending) on top of
/// what the server has.
final movementListProvider = Provider<List<StockMovement>>((ref) {
  final saved = ref.watch(movementsProvider).valueOrNull ?? const <StockMovement>[];
  return [...ref.watch(outboxViewProvider).movements, ...saved];
});

class StockAlertsNotifier extends AsyncNotifier<StockAlerts> {
  @override
  Future<StockAlerts> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const StockAlerts();
    return ref.watch(inventoryRepositoryProvider).alerts();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(ref.read(inventoryRepositoryProvider).alerts);
  }
}

final stockAlertsProvider =
    AsyncNotifierProvider<StockAlertsNotifier, StockAlerts>(StockAlertsNotifier.new);

/// The low/out-of-stock lists. Straight from the server's alerts endpoint
/// when everything is in sync; worked out from the products (with the same
/// rule the server uses) while changes are waiting or the server can't be
/// reached, so an offline stock-out raises its alert immediately.
final stockAlertListProvider = Provider<StockAlerts>((ref) {
  final server = ref.watch(stockAlertsProvider).valueOrNull;
  final hasPending = ref.watch(pendingCountProvider) > 0;
  final connected = ref.watch(connectionProvider) == ConnectionQuality.good;

  if (server != null && !hasPending && connected) return server;

  final products = ref.watch(productListProvider);
  return StockAlerts(
    lowStock: products.where((p) => p.isLowStock).toList(),
    outOfStock: products.where((p) => p.isOutOfStock).toList(),
  );
});
