import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/warehouse.dart';

/// REAL `/api/v1/warehouses` — list, create, and edit/disable. There is no
/// delete: retiring a warehouse means setting it inactive.
class WarehousesRepository {
  WarehousesRepository(this._api);

  final AuthedApi _api;

  Future<List<Warehouse>> list() async {
    final json = await _api.get(ApiConstants.warehouses, cacheKey: 'warehouses');
    return [
      for (final row in (json['warehouses'] as List<dynamic>? ?? const []))
        Warehouse.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<Warehouse> create({
    required String name,
    String? address,
    String? managerName,
    String? phone,
  }) async {
    final json = await _api.post(ApiConstants.warehouses, {
      'name': name,
      if (address != null && address.isNotEmpty) 'address': address,
      if (managerName != null && managerName.isNotEmpty) 'managerName': managerName,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
    return Warehouse.fromJson(json['warehouse'] as Map<String, dynamic>);
  }

  /// Any subset of `name`, `address`, `managerName`, `phone` (string or
  /// null to clear) and `status` (`active`/`inactive`).
  Future<Warehouse> update(String id, Map<String, dynamic> changes) async {
    final json = await _api.patch(ApiConstants.warehouse(id), changes);
    return Warehouse.fromJson(json['warehouse'] as Map<String, dynamic>);
  }
}

final warehousesRepositoryProvider = Provider<WarehousesRepository>(
  (ref) => WarehousesRepository(ref.watch(authedApiProvider)),
);

class WarehousesNotifier extends AsyncNotifier<List<Warehouse>> {
  @override
  Future<List<Warehouse>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    return ref.watch(warehousesRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(ref.read(warehousesRepositoryProvider).list);
  }

  Future<void> add({
    required String name,
    String? address,
    String? managerName,
    String? phone,
  }) async {
    await ref.read(warehousesRepositoryProvider).create(
          name: name,
          address: address,
          managerName: managerName,
          phone: phone,
        );
    await refresh();
    _refreshPlanUsage();
  }

  Future<void> edit(String id, Map<String, dynamic> changes) async {
    await ref.read(warehousesRepositoryProvider).update(id, changes);
    await refresh();
    _refreshPlanUsage();
  }

  /// Adding, disabling or re-enabling a warehouse changes the plan's
  /// warehouse usage on `/me` — re-read it so the usage line and the add
  /// button's cap check stay right.
  void _refreshPlanUsage() => unawaited(ref.read(authControllerProvider.notifier).refresh());
}

final warehousesProvider =
    AsyncNotifierProvider<WarehousesNotifier, List<Warehouse>>(WarehousesNotifier.new);

/// Every warehouse the screens can read synchronously — empty while
/// loading or if the request failed (screens that care about those states
/// watch [warehousesProvider] directly).
final warehouseListProvider = Provider<List<Warehouse>>(
  (ref) => ref.watch(warehousesProvider).valueOrNull ?? const [],
);

/// The warehouses a stock movement can be recorded in.
final activeWarehousesProvider = Provider<List<Warehouse>>(
  (ref) => ref.watch(warehouseListProvider).where((w) => w.isActive).toList(),
);
