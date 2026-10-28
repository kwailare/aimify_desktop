import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../parties/data/parties_repository.dart';
import '../../purchases/data/purchases_repository.dart';

/// One price paid to a supplier for a product.
class PricePoint {
  const PricePoint({required this.date, required this.reference, required this.unitCost, required this.quantity});

  final DateTime date;
  final String reference;
  final double unitCost;
  final int quantity;

  factory PricePoint.fromJson(Map<String, dynamic> json) => PricePoint(
        date: DateTime.parse(json['date'] as String).toLocal(),
        reference: json['reference'] as String,
        unitCost: (json['unitCost'] as num).toDouble(),
        quantity: (json['quantity'] as num).toInt(),
      );
}

/// What a product has cost from one supplier: the latest price, the change
/// from the one before, and the history (newest first).
class SupplierProductPrice {
  const SupplierProductPrice({
    required this.productId,
    required this.name,
    required this.sku,
    required this.unit,
    required this.currentCost,
    required this.lastCost,
    required this.lastDate,
    required this.lastReference,
    this.previousCost,
    this.change,
    this.changePercent,
    required this.timesBought,
    this.history = const [],
  });

  final String productId;
  final String name;
  final String sku;
  final String unit;

  /// The product's purchase price now.
  final double currentCost;
  final double lastCost;
  final DateTime lastDate;
  final String lastReference;
  final double? previousCost;
  final double? change;
  final double? changePercent;
  final int timesBought;
  final List<PricePoint> history;

  bool get wentUp => (change ?? 0) > 0.004;
  bool get wentDown => (change ?? 0) < -0.004;

  factory SupplierProductPrice.fromJson(Map<String, dynamic> json) => SupplierProductPrice(
        productId: json['productId'] as String,
        name: json['name'] as String,
        sku: json['sku'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        currentCost: (json['currentCost'] as num).toDouble(),
        lastCost: (json['lastCost'] as num).toDouble(),
        lastDate: DateTime.parse(json['lastDate'] as String).toLocal(),
        lastReference: json['lastReference'] as String,
        previousCost: (json['previousCost'] as num?)?.toDouble(),
        change: (json['change'] as num?)?.toDouble(),
        changePercent: (json['changePercent'] as num?)?.toDouble(),
        timesBought: (json['timesBought'] as num?)?.toInt() ?? 1,
        history: [
          for (final row in (json['history'] as List<dynamic>? ?? const []))
            PricePoint.fromJson(row as Map<String, dynamic>),
        ],
      );
}

/// REAL `GET /api/v1/suppliers/{id}/prices` (falls back to the saved copy).
class SupplierPricesRepository {
  SupplierPricesRepository(this._api);

  final AuthedApi _api;

  Future<List<SupplierProductPrice>> fetch(String supplierId) async {
    final json = await _api.get(ApiConstants.supplierPrices(supplierId), cacheKey: 'prices_$supplierId');
    return [
      for (final row in (json['products'] as List<dynamic>? ?? const []))
        SupplierProductPrice.fromJson(row as Map<String, dynamic>),
    ];
  }
}

final supplierPricesRepositoryProvider = Provider<SupplierPricesRepository>(
  (ref) => SupplierPricesRepository(ref.watch(authedApiProvider)),
);

/// One supplier's prices; re-read when purchases change.
final supplierPricesProvider = FutureProvider.autoDispose.family<List<SupplierProductPrice>, String>((ref, supplierId) {
  if (supplierId.startsWith('local:') || !ref.watch(holdsPermissionProvider(Permissions.suppliersView))) {
    return const <SupplierProductPrice>[];
  }
  ref.watch(purchasesChangedProvider);
  ref.watch(debtsChangedProvider);
  return ref.watch(supplierPricesRepositoryProvider).fetch(supplierId);
});
