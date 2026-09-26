import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/product.dart';

/// REAL `/api/v1/products` — list, create, edit, archive, and the image
/// upload/remove endpoints. Archiving (not deleting) keeps a product's
/// stock history intact; the API hides archived products from the list.
class ProductsRepository {
  ProductsRepository(this._api);

  final AuthedApi _api;

  Future<List<Product>> list() async {
    final json = await _api.get(ApiConstants.products);
    return [
      for (final row in (json['products'] as List<dynamic>? ?? const []))
        Product.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<Product> create(ProductInput input) async {
    final json = await _api.post(ApiConstants.products, input.toJson());
    return Product.fromJson(json['product'] as Map<String, dynamic>);
  }

  Future<Product> update(String id, ProductInput input) async {
    final json = await _api.patch(ApiConstants.product(id), input.toJson());
    return Product.fromJson(json['product'] as Map<String, dynamic>);
  }

  Future<Product> archive(String id) async {
    final json = await _api.delete(ApiConstants.product(id));
    return Product.fromJson((json['product'] ?? json) as Map<String, dynamic>);
  }

  /// PNG, JPEG or WebP up to 2 MB; the server checks the file's contents,
  /// not its name. Replaces any existing picture.
  Future<Product> uploadImage(String id, {required List<int> bytes, required String filename}) async {
    final json = await _api.postFile(
      ApiConstants.productImage(id),
      field: 'image',
      bytes: bytes,
      filename: filename,
    );
    return Product.fromJson(json['product'] as Map<String, dynamic>);
  }

  Future<Product> removeImage(String id) async {
    final json = await _api.delete(ApiConstants.productImage(id));
    return Product.fromJson(json['product'] as Map<String, dynamic>);
  }
}

final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => ProductsRepository(ref.watch(authedApiProvider)),
);

class ProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    return ref.watch(productsRepositoryProvider).list();
  }

  /// Re-reads the list from the server. Called after every write and after
  /// every stock movement, since movements change `currentStock`.
  Future<void> refresh() async {
    state = await AsyncValue.guard(ref.read(productsRepositoryProvider).list);
  }

  Future<Product> add(ProductInput input) async {
    final created = await ref.read(productsRepositoryProvider).create(input);
    await refresh();
    _refreshPlanUsage();
    return created;
  }

  Future<Product> edit(String id, ProductInput input) async {
    final updated = await ref.read(productsRepositoryProvider).update(id, input);
    await refresh();
    return updated;
  }

  Future<void> archive(String id) async {
    await ref.read(productsRepositoryProvider).archive(id);
    await refresh();
    _refreshPlanUsage();
  }

  /// Creating or archiving changes the plan's product usage, which lives on
  /// `/me` — re-read it so the "x/y products used" line and the add button's
  /// cap check stay right.
  void _refreshPlanUsage() => unawaited(ref.read(authControllerProvider.notifier).refresh());

  Future<void> setImage(String id, {required List<int> bytes, required String filename}) async {
    await ref.read(productsRepositoryProvider).uploadImage(id, bytes: bytes, filename: filename);
    await refresh();
  }

  Future<void> clearImage(String id) async {
    await ref.read(productsRepositoryProvider).removeImage(id);
    await refresh();
  }
}

final productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<Product>>(ProductsNotifier.new);

/// Products for anything that just needs the list — empty while loading or
/// after a failure. Screens that show loading/error states watch
/// [productsProvider] itself.
final productListProvider = Provider<List<Product>>(
  (ref) => ref.watch(productsProvider).valueOrNull ?? const [],
);
