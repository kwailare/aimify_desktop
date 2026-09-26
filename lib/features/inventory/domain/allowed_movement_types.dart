import '../../auth/domain/permissions.dart';
import 'stock_movement.dart';

/// Which [StockMovementType]s the given permission list unlocks — `stock.out`
/// for [StockMovementType.stockOut], `stock.adjust` for the rest. See "Roles
/// and permissions" in `docs/desktop-api.md`. A pure function (no Riverpod,
/// no BuildContext) so it's directly unit-testable, and safe to call from
/// `initState()` where reactive `ref.watch` isn't allowed yet.
List<StockMovementType> allowedMovementTypes(List<String> permissions) {
  final canOut = permissions.contains(Permissions.stockOut);
  final canAdjust = permissions.contains(Permissions.stockAdjust);
  return [
    if (canAdjust) StockMovementType.stockIn,
    if (canOut) StockMovementType.stockOut,
    if (canAdjust) StockMovementType.adjustment,
    if (canAdjust) StockMovementType.count,
  ];
}
