/// Permission keys returned in `/api/v1/me`'s `permissions` array — see
/// "Roles and permissions" in `docs/desktop-api.md`. Reading products,
/// warehouses, categories, units, movements and alerts is open to every role
/// and has no permission key; customers, suppliers and the credit ledger hold
/// money records, so they have their own read permissions.
class Permissions {
  Permissions._();

  /// Create/edit a product, upload or remove its image.
  static const productsWrite = 'products.write';

  /// Archive a product.
  static const productsArchive = 'products.archive';

  /// Add or delete a category/unit.
  static const catalogWrite = 'catalog.write';

  /// Create, edit or disable a warehouse.
  static const warehousesManage = 'warehouses.manage';

  /// Record a `stock_out` movement.
  static const stockOut = 'stock.out';

  /// Record `stock_in`, `adjustment` or `count` movements.
  static const stockAdjust = 'stock.adjust';

  /// See customers and their credit ledger.
  static const customersRead = 'customers.read';

  /// Add, edit or archive a customer.
  static const customersWrite = 'customers.write';

  /// See suppliers and their credit ledger.
  static const suppliersRead = 'suppliers.read';

  /// Add, edit or archive a supplier.
  static const suppliersWrite = 'suppliers.write';

  /// Record a charge, payment or adjustment on a credit ledger.
  static const creditRecord = 'credit.record';
}
