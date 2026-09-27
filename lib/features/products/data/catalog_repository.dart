import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/presentation/auth_controller.dart';

/// One entry in the organization's category or unit list.
class CatalogOption {
  const CatalogOption({required this.id, required this.name});

  final String id;
  final String name;

  factory CatalogOption.fromJson(Map<String, dynamic> json) =>
      CatalogOption(id: json['id'] as String, name: json['name'] as String);
}

enum CatalogKind { category, unit }

/// REAL `/api/v1/categories` and `/api/v1/units`. Product categories and
/// units are configurable per organization; any value sent on a product is
/// added to the list automatically, so custom ones "just work".
class CatalogRepository {
  CatalogRepository(this._api);

  final AuthedApi _api;

  String _listUrl(CatalogKind kind) =>
      kind == CatalogKind.category ? ApiConstants.categories : ApiConstants.units;

  String _itemUrl(CatalogKind kind, String id) =>
      kind == CatalogKind.category ? ApiConstants.category(id) : ApiConstants.unit(id);

  Future<List<CatalogOption>> list(CatalogKind kind) async {
    final json = await _api.get(_listUrl(kind), cacheKey: kind.name);
    final key = kind == CatalogKind.category ? 'categories' : 'units';
    return [
      for (final row in (json[key] as List<dynamic>? ?? const []))
        CatalogOption.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<void> add(CatalogKind kind, String name) async {
    await _api.post(_listUrl(kind), {'name': name});
  }

  /// `409` (still used by products) surfaces as an [ApiException] whose
  /// message says how many products to change first.
  Future<void> remove(CatalogKind kind, String id) async {
    await _api.delete(_itemUrl(kind, id));
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(authedApiProvider)),
);

class CatalogNotifier extends FamilyAsyncNotifier<List<CatalogOption>, CatalogKind> {
  @override
  Future<List<CatalogOption>> build(CatalogKind arg) async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    return ref.watch(catalogRepositoryProvider).list(arg);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() => ref.read(catalogRepositoryProvider).list(arg));
  }

  Future<void> add(String name) async {
    await ref.read(catalogRepositoryProvider).add(arg, name);
    await refresh();
  }

  Future<void> remove(String id) async {
    await ref.read(catalogRepositoryProvider).remove(arg, id);
    await refresh();
  }
}

final catalogProvider =
    AsyncNotifierProvider.family<CatalogNotifier, List<CatalogOption>, CatalogKind>(
  CatalogNotifier.new,
);
