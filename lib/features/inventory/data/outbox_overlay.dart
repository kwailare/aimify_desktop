import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/offline/outbox.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../domain/stock_movement.dart';

/// What the screens should show: the last data from the server with every
/// change still waiting in the outbox applied on top, so an offline change
/// is visible immediately and simply disappears from this overlay (because
/// the server data now includes it) once it has synced.
class OutboxView {
  const OutboxView({required this.products, required this.movements});

  final List<Product> products;

  /// The pending movements as ledger rows, newest first.
  final List<StockMovement> movements;
}

/// Applies the outbox [ops] (in order) to the server's [base] products.
///
/// Ops the server refused ([OutboxOp.failed]) are left out — they didn't
/// happen. A movement can refer to a product created offline, using its
/// `local:<id>` id.
OutboxView overlayOutbox(List<Product> base, List<OutboxOp> ops) {
  final products = [...base];
  final movements = <StockMovement>[];

  int indexOf(String id) => products.indexWhere((p) => p.id == id);

  for (final op in ops) {
    if (op.failed) continue;
    switch (op.kind) {
      case OpKind.productCreate:
        products.add(
          ProductInput.fromJson(Map<String, dynamic>.from(op.payload['input'] as Map))
              .toLocalProduct(op.localId),
        );
      case OpKind.productUpdate:
        final i = indexOf(op.payload['id'] as String);
        if (i >= 0) {
          products[i] = products[i].withInput(
            ProductInput.fromJson(Map<String, dynamic>.from(op.payload['input'] as Map)),
          );
        }
      case OpKind.productArchive:
        final i = indexOf(op.payload['id'] as String);
        if (i >= 0) products.removeAt(i);
      case OpKind.partyCreate:
      case OpKind.partyUpdate:
      case OpKind.partyArchive:
      case OpKind.creditEntry:
        break;
      case OpKind.movement:
        final productId = op.payload['productId'] as String;
        final i = indexOf(productId);
        final quantity = (op.payload['quantity'] as num).toInt();
        final previous = i >= 0 ? products[i].currentStock : 0;
        if (i >= 0) products[i] = products[i].withStock(previous + quantity);
        movements.add(
          StockMovement(
            id: 'pending:${op.id}',
            productId: productId,
            warehouseId: op.payload['warehouseId'] as String,
            type: StockMovementTypeX.fromApi(op.payload['type'] as String),
            quantity: quantity,
            reason: op.payload['reason'] as String?,
            previousStock: previous,
            newStock: previous + quantity,
            createdAt: op.createdAt,
            isPending: true,
          ),
        );
    }
  }

  movements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return OutboxView(products: products, movements: movements);
}

/// The server's products with the outbox applied — what every screen reads.
final outboxViewProvider = Provider<OutboxView>((ref) {
  final base = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
  return overlayOutbox(base, ref.watch(outboxOpsProvider));
});
