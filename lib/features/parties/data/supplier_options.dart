import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';

/// A supplier's id, name and status — all a product needs to show or pick
/// its supplier. From `GET /api/v1/suppliers/options`, which anyone who can
/// see products may read; balances and contacts stay behind
/// `suppliers.view`.
class SupplierOption {
  const SupplierOption({required this.id, required this.name, this.isArchived = false});

  final String id;
  final String name;
  final bool isArchived;

  /// How a linked supplier is shown, flagging one archived since.
  String get label => isArchived ? '$name (archived)' : name;

  factory SupplierOption.fromJson(Map<String, dynamic> json) => SupplierOption(
        id: json['id'] as String,
        name: json['name'] as String,
        isArchived: json['status'] == 'archived',
      );
}

class SupplierOptionsRepository {
  SupplierOptionsRepository(this._api);

  final AuthedApi _api;

  Future<List<SupplierOption>> list() async {
    final json = await _api.get(ApiConstants.supplierOptions, cacheKey: 'supplier_options');
    return [
      for (final row in (json['suppliers'] as List<dynamic>? ?? const []))
        SupplierOption.fromJson(row as Map<String, dynamic>),
    ];
  }
}

final supplierOptionsRepositoryProvider = Provider<SupplierOptionsRepository>(
  (ref) => SupplierOptionsRepository(ref.watch(authedApiProvider)),
);

class SupplierOptionsNotifier extends AsyncNotifier<List<SupplierOption>> {
  bool get _allowed =>
      ref.read(holdsPermissionProvider(Permissions.productsView)) ||
      ref.read(holdsPermissionProvider(Permissions.suppliersView));

  @override
  Future<List<SupplierOption>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    final canSee = ref.watch(holdsPermissionProvider(Permissions.productsView)) ||
        ref.watch(holdsPermissionProvider(Permissions.suppliersView));
    if (!canSee) return const [];
    return ref.watch(supplierOptionsRepositoryProvider).list();
  }

  /// Called after suppliers are added, renamed, archived or restored.
  Future<void> refresh() async {
    if (!_allowed) return;
    state = await AsyncValue.guard(ref.read(supplierOptionsRepositoryProvider).list);
  }
}

final supplierOptionsProvider =
    AsyncNotifierProvider<SupplierOptionsNotifier, List<SupplierOption>>(SupplierOptionsNotifier.new);

/// Supplier id to option, for showing a product's supplier name. Empty while
/// loading or without access.
final supplierOptionByIdProvider = Provider<Map<String, SupplierOption>>((ref) {
  final options = ref.watch(supplierOptionsProvider).valueOrNull ?? const [];
  return {for (final option in options) option.id: option};
});

/// The supplier [name] matches, ignoring case and extra spaces, or `null`.
/// Archived suppliers never match, since products can't be newly linked to
/// them.
SupplierOption? matchSupplierByName(List<SupplierOption> options, String name) {
  String norm(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final wanted = norm(name);
  if (wanted.isEmpty) return null;
  for (final option in options) {
    if (!option.isArchived && norm(option.name) == wanted) return option;
  }
  return null;
}
