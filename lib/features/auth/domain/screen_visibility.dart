import 'permissions.dart';

/// Every module screen the sidebar/router can show — one entry per branch in
/// `core/router/app_router.dart`, in the same order as `navItems` in
/// `app_sidebar.dart`.
enum AppScreen {
  dashboard,
  products,
  inventory,
  purchases,
  suppliers,
  customers,
  expenses,
  creditsDebts,
  warehouses,
  reports,
}

/// The path each screen lives at — used by the router to work out which
/// screen a location is, so a role can't reach a hidden one by a stale deep
/// link or a role change while they're already sitting on it.
const screenPaths = {
  AppScreen.dashboard: '/',
  AppScreen.products: '/products',
  AppScreen.inventory: '/inventory',
  AppScreen.purchases: '/purchases',
  AppScreen.suppliers: '/suppliers',
  AppScreen.customers: '/customers',
  AppScreen.expenses: '/expenses',
  AppScreen.creditsDebts: '/credits-debts',
  AppScreen.warehouses: '/warehouses',
  AppScreen.reports: '/reports',
};

/// Which screen each module permission opens. A screen backed by the API is
/// visible exactly when the person holds its `*.view` permission, so the
/// Owner's Roles & permissions grid on the website decides the sidebar. Credits
/// & Debts shows whichever side (customers, suppliers) the person can see.
///
/// This decides what appears in the sidebar and what a direct navigation is
/// allowed to reach — not what a control inside a visible screen can do
/// (each screen still checks the specific action, e.g. `products.edit`).
const _viewPermission = {
  AppScreen.products: Permissions.productsView,
  AppScreen.inventory: Permissions.stockView,
  AppScreen.suppliers: Permissions.suppliersView,
  AppScreen.customers: Permissions.customersView,
  AppScreen.warehouses: Permissions.warehousesView,
};

/// Purchases, Expenses and Reports have no backend permissions yet (purchases
/// and expenses are saved on this computer only), so they keep the fixed
/// role rules they had before the permission grid, until those modules move
/// to the server.
const _localScreensByRole = <String, Set<AppScreen>>{
  'Owner': {AppScreen.purchases, AppScreen.expenses, AppScreen.reports},
  'Administrator': {AppScreen.purchases, AppScreen.expenses, AppScreen.reports},
  'Warehouse Manager': {AppScreen.purchases, AppScreen.reports},
  'Inventory Staff': {AppScreen.reports},
  'Sales Staff': {},
  'Accountant / Finance': {AppScreen.purchases, AppScreen.expenses, AppScreen.reports},
};

/// True if someone with [role] and [permissions] should see [screen] at all.
/// Dashboard is always visible; with no permissions (still loading, or an
/// unknown role) everything else is hidden — fails closed, the same way
/// permission checks do.
bool isScreenVisible(String? role, List<String> permissions, AppScreen screen) {
  switch (screen) {
    case AppScreen.dashboard:
      return true;
    case AppScreen.creditsDebts:
      return permissions.contains(Permissions.customersView) ||
          permissions.contains(Permissions.suppliersView);
    case AppScreen.purchases:
    case AppScreen.expenses:
    case AppScreen.reports:
      return _localScreensByRole[role]?.contains(screen) ?? false;
    default:
      return permissions.contains(_viewPermission[screen]);
  }
}

/// Every screen visible to [role] with [permissions], in [AppScreen]
/// declaration order.
List<AppScreen> visibleScreensFor(String? role, List<String> permissions) =>
    AppScreen.values.where((s) => isScreenVisible(role, permissions, s)).toList();

final _screensByPath = {for (final entry in screenPaths.entries) entry.value: entry.key};

/// The screen at router location [path], or `null` for a location that
/// isn't one of the module screens (splash, login, locked).
AppScreen? screenForPath(String path) => _screensByPath[path];
