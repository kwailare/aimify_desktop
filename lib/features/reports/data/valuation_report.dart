import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../products/data/products_repository.dart';

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

/// A subtotal: how many products hold stock, units, and value at purchase
/// and selling price, with the potential margin between them.
class ValuationTotals {
  const ValuationTotals({
    required this.products,
    required this.units,
    required this.valueAtCost,
    required this.valueAtRetail,
    required this.margin,
    this.marginPercent,
  });

  static const zero = ValuationTotals(products: 0, units: 0, valueAtCost: 0, valueAtRetail: 0, margin: 0);

  final int products;
  final int units;
  final double valueAtCost;
  final double valueAtRetail;
  final double margin;

  /// Margin as a share of the selling-price value; `null` when that is 0.
  final double? marginPercent;

  factory ValuationTotals.fromJson(Map<String, dynamic> json) => ValuationTotals(
        products: (json['products'] as num?)?.toInt() ?? 0,
        units: (json['units'] as num?)?.toInt() ?? 0,
        valueAtCost: _num(json['valueAtCost']),
        valueAtRetail: _num(json['valueAtRetail']),
        margin: _num(json['margin']),
        marginPercent: (json['marginPercent'] as num?)?.toDouble(),
      );
}

/// Why a row makes the valuation unreliable.
enum ValuationFlag { negativeStock, noCost, archived }

class ValuationProductRow {
  const ValuationProductRow({
    required this.productId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.unitPrice,
    required this.valueAtCost,
    required this.valueAtRetail,
    required this.margin,
    this.category,
    this.flags = const {},
  });

  final String productId;
  final String sku;
  final String name;
  final String? category;
  final String unit;
  final int quantity;
  final double unitCost;
  final double unitPrice;
  final double valueAtCost;
  final double valueAtRetail;
  final double margin;
  final Set<ValuationFlag> flags;

  factory ValuationProductRow.fromJson(Map<String, dynamic> json) => ValuationProductRow(
        productId: json['productId'] as String,
        sku: json['sku'] as String,
        name: json['name'] as String,
        category: json['category'] as String?,
        unit: json['unit'] as String? ?? 'piece',
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        unitCost: _num(json['unitCost']),
        unitPrice: _num(json['unitPrice']),
        valueAtCost: _num(json['valueAtCost']),
        valueAtRetail: _num(json['valueAtRetail']),
        margin: _num(json['margin']),
        flags: {
          for (final flag in (json['flags'] as List<dynamic>? ?? const []))
            ?switch (flag) {
              'negative_stock' => ValuationFlag.negativeStock,
              'no_cost' => ValuationFlag.noCost,
              'archived' => ValuationFlag.archived,
              _ => null,
            },
        },
      );
}

/// A category or warehouse subtotal.
class ValuationGroupRow {
  const ValuationGroupRow({required this.id, required this.label, required this.totals});

  final String? id;
  final String label;
  final ValuationTotals totals;
}

/// `GET /api/v1/reports/valuation`: stock on hand priced at each product's
/// current purchase and selling price, as of [asOf].
class ValuationReport {
  const ValuationReport({
    required this.asOf,
    required this.totals,
    required this.byProduct,
    required this.byCategory,
    required this.byWarehouse,
    required this.negativeStockCount,
    required this.noCostCount,
  });

  final DateTime asOf;
  final ValuationTotals totals;
  final List<ValuationProductRow> byProduct;
  final List<ValuationGroupRow> byCategory;
  final List<ValuationGroupRow> byWarehouse;
  final int negativeStockCount;
  final int noCostCount;

  factory ValuationReport.fromJson(Map<String, dynamic> json) {
    final warnings = json['warnings'] as Map<String, dynamic>? ?? const {};
    return ValuationReport(
      asOf: DateTime.tryParse(json['asOf'] as String? ?? '') ?? DateTime.now(),
      totals: ValuationTotals.fromJson(json['totals'] as Map<String, dynamic>? ?? const {}),
      byProduct: [
        for (final row in (json['byProduct'] as List<dynamic>? ?? const []))
          ValuationProductRow.fromJson(row as Map<String, dynamic>),
      ],
      byCategory: [
        for (final row in (json['byCategory'] as List<dynamic>? ?? const []))
          ValuationGroupRow(
            id: (row as Map<String, dynamic>)['category'] as String?,
            label: row['category'] as String? ?? 'Uncategorised',
            totals: ValuationTotals.fromJson(row),
          ),
      ],
      byWarehouse: [
        for (final row in (json['byWarehouse'] as List<dynamic>? ?? const []))
          ValuationGroupRow(
            id: (row as Map<String, dynamic>)['warehouseId'] as String?,
            label: row['status'] == 'inactive' ? '${row['name']} (disabled)' : row['name'] as String,
            totals: ValuationTotals.fromJson(row),
          ),
      ],
      negativeStockCount: (warnings['negativeStock'] as num?)?.toInt() ?? 0,
      noCostCount: (warnings['noCost'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What the report is narrowed to; `null` means all. An empty [category]
/// means uncategorised products.
typedef ValuationFilter = ({String? warehouseId, String? category});

class ValuationRepository {
  ValuationRepository(this._api);

  final AuthedApi _api;

  Future<ValuationReport> fetch(ValuationFilter filter) async {
    final query = {
      if (filter.warehouseId != null) 'warehouseId': filter.warehouseId!,
      if (filter.category != null) 'category': filter.category!,
    };
    final url = Uri.parse(ApiConstants.valuationReport).replace(queryParameters: query.isEmpty ? null : query);
    final json = await _api.get(
      url.toString(),
      cacheKey: 'valuation_${filter.warehouseId ?? 'all'}_${filter.category ?? 'all'}',
    );
    return ValuationReport.fromJson(json);
  }
}

final valuationRepositoryProvider = Provider<ValuationRepository>(
  (ref) => ValuationRepository(ref.watch(authedApiProvider)),
);

/// Whether this person may see the valuation (`products.view` and
/// `stock.view`).
final canSeeValuationProvider = Provider<bool>(
  (ref) =>
      ref.watch(holdsPermissionProvider(Permissions.productsView)) &&
      ref.watch(holdsPermissionProvider(Permissions.stockView)),
);

/// The report for a filter. It re-reads whenever the product list changes
/// (a movement, a price change, an archive), so it never shows stale
/// figures next to the rest of the app.
final valuationReportProvider = FutureProvider.family<ValuationReport?, ValuationFilter>((ref, filter) async {
  if (ref.watch(sessionUserIdProvider) == null || !ref.watch(canSeeValuationProvider)) return null;
  ref.watch(productsProvider.select((state) => state.valueOrNull));
  return ref.watch(valuationRepositoryProvider).fetch(filter);
});
