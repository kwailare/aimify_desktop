/// Permission keys returned in `/api/v1/me`'s `permissions` array — see
/// "Roles and permissions" in `docs/desktop-api.md`. Each organization's
/// Owner sets which roles hold which of these on the website, so they are
/// the only thing the app should check: never the role name. Every read is
/// permissioned too (`*.view`), and the sidebar shows a screen only to people
/// who can view it.
///
/// `/me` also still sends older combined keys (`products.write`,
/// `warehouses.manage`...) for app builds released before the grid existed;
/// this app doesn't use them.
class Permissions {
  Permissions._();

  static const productsView = 'products.view';
  static const productsCreate = 'products.create';

  /// Edit a product's details, upload or remove its image.
  static const productsEdit = 'products.edit';

  /// Archive or restore a product.
  static const productsArchive = 'products.archive';

  static const catalogView = 'catalog.view';
  static const catalogCreate = 'catalog.create';
  static const catalogDelete = 'catalog.delete';

  /// See movements and stock alerts.
  static const stockView = 'stock.view';
  static const stockIn = 'stock.in';
  static const stockOut = 'stock.out';

  /// Record `adjustment` and `count` movements.
  static const stockAdjust = 'stock.adjust';

  static const warehousesView = 'warehouses.view';
  static const warehousesCreate = 'warehouses.create';
  static const warehousesEdit = 'warehouses.edit';

  /// Disable or re-enable a warehouse.
  static const warehousesDisable = 'warehouses.disable';

  /// See customers and their credit ledger.
  static const customersView = 'customers.view';
  static const customersCreate = 'customers.create';
  static const customersEdit = 'customers.edit';

  /// Archive or restore a customer.
  static const customersArchive = 'customers.archive';

  /// Add, rename and remove customer types and their default credit limits.
  static const customersTypes = 'customers.types';

  /// See suppliers and their credit ledger.
  static const suppliersView = 'suppliers.view';
  static const suppliersCreate = 'suppliers.create';
  static const suppliersEdit = 'suppliers.edit';

  /// Archive or restore a supplier.
  static const suppliersArchive = 'suppliers.archive';

  /// Record a charge, payment or adjustment on a credit ledger (the server
  /// also requires view of that customer or supplier).
  static const creditRecord = 'credit.record';

  /// See purchases (Owner, Administrator, Warehouse Manager, Accountant).
  static const purchasesView = 'purchases.view';

  /// Record purchases and edit them while nothing has been received.
  static const purchasesCreate = 'purchases.create';

  /// Receive deliveries, which adds stock.
  static const purchasesReceive = 'purchases.receive';

  /// Cancel a purchase nothing was received on.
  static const purchasesCancel = 'purchases.cancel';

  /// See sales (Owner, Administrator, Sales Staff, Accountant).
  static const salesView = 'sales.view';

  /// Record a sale and take payment at the counter.
  static const salesCreate = 'sales.create';

  /// Sell at another price than the product's, or give a discount.
  static const salesDiscount = 'sales.discount';

  /// Complete a credit sale over the customer's credit limit.
  static const salesOverride = 'sales.override';

  /// Void a sale (stock goes back).
  static const salesVoid = 'sales.void';

  /// List the team and invite people (Owner, Administrator; not editable).
  static const teamManage = 'team.manage';

  /// Run the guided setup and mark it finished (Owner, Administrator; not
  /// editable).
  static const setupComplete = 'setup.complete';
}
