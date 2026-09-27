import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/outbox.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../inventory/data/outbox_overlay.dart';
import '../../sync/sync_engine.dart';
import '../domain/product.dart';

/// REAL `/api/v1/products` — list, create, edit, archive, and the image
/// upload/remove endpoints. Archiving (not deleting) keeps a product's
/// stock history intact; the API hides archived products from the list.
class ProductsRepository {
  ProductsRepository(this._api);

  final AuthedApi _api;

  /// The product list. Falls back to the last saved copy when the network
  /// can't answer, so the screens still open offline.
  Future<List<Product>> list() => _read(cacheKey: 'products');

  /// The product list straight from the server — never the saved copy. Used
  /// to check whether an interrupted create actually landed.
  Future<List<Product>> listFresh() => _read();

  Future<List<Product>> _read({String? cacheKey}) async {
    final json = await _api.get(ApiConstants.products, cacheKey: cacheKey);
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

  SyncEngine get _sync => ref.read(syncEngineProvider.notifier);

  /// Creates a product — now if the connection is good, otherwise saved on
  /// this computer and synced later (the product appears immediately, marked
  /// pending).
  Future<SubmitResult<Product>> add(ProductInput input) async {
    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.productCreate,
      payload: {'input': input.toJson()},
      createdAt: DateTime.now(),
    );
    final result = await _sync.submit(op, () => ref.read(productsRepositoryProvider).create(input));
    if (!result.queued) {
      await refresh();
      _refreshPlanUsage();
    }
    return result;
  }

  Future<SubmitResult<Product>> edit(String id, ProductInput input) async {
    final outbox = ref.read(outboxProvider.notifier);

    // A product that only exists locally: fold the edit into its pending
    // create instead of queueing a second change.
    if (id.startsWith('local:')) {
      final create = ref
          .read(outboxOpsProvider)
          .where((o) => o.kind == OpKind.productCreate && o.localProductId == id)
          .firstOrNull;
      if (create != null) {
        await outbox.replace(
          OutboxOp(
            id: create.id,
            kind: create.kind,
            payload: {'input': input.toJson()},
            createdAt: create.createdAt,
            attempted: create.attempted,
            error: create.error,
          ),
        );
      }
      return const SubmitResult.queued();
    }

    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.productUpdate,
      payload: {'id': id, 'input': input.toJson()},
      createdAt: DateTime.now(),
    );
    final result = await _sync.submit(op, () => ref.read(productsRepositoryProvider).update(id, input));
    if (!result.queued) await refresh();
    return result;
  }

  Future<SubmitResult<Product>> archive(String id) async {
    // Archiving a product that never reached the server just forgets it,
    // together with any stock changes that were waiting on it.
    if (id.startsWith('local:')) {
      await ref.read(outboxProvider.notifier).removeWhere(
            (o) =>
                o.localProductId == id ||
                o.payload['id'] == id ||
                o.payload['productId'] == id,
          );
      return const SubmitResult.queued();
    }

    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.productArchive,
      payload: {'id': id},
      createdAt: DateTime.now(),
    );
    final result = await _sync.submit(op, () => ref.read(productsRepositoryProvider).archive(id));
    if (!result.queued) {
      await refresh();
      _refreshPlanUsage();
    }
    return result;
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
///
/// This is the server's list with every change still waiting to sync applied
/// on top (see `outbox_overlay.dart`), so offline changes show at once.
final productListProvider = Provider<List<Product>>(
  (ref) => ref.watch(outboxViewProvider).products,
);

/// True when the plan's product cap is reached, counting products created
/// (or archived) offline that the server's usage figure doesn't include yet.
final productSlotsFullProvider = Provider<bool>((ref) {
  final plan = ref.watch(authControllerProvider).valueOrNull?.plan;
  final limit = plan?.limits.products;
  if (plan == null || limit == null) return false;
  final ops = ref.watch(outboxOpsProvider).where((o) => !o.failed);
  final created = ops.where((o) => o.kind == OpKind.productCreate).length;
  final archived = ops
      .where((o) => o.kind == OpKind.productArchive && !(o.payload['id'] as String).startsWith('local:'))
      .length;
  return plan.usage.products + created - archived >= limit;
});
