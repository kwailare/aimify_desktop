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

/// Which screens each role sees at all, derived from the same role/permission
/// design as `lib/permissions.ts` on aimify-web: a screen is visible to a
/// role when that role holds a permission the screen is actually about, or
/// (for the two local-only, unpermissioned screens, Purchases and Expenses)
/// when the role's day-to-day work is naturally about money coming in or out.
/// Dashboard is the one screen everyone always sees.
///
/// This decides what appears in the sidebar and what a direct navigation is
/// allowed to reach — not what a control inside a visible screen can do
/// (which is still each screen's own `hasPermission` check, since a role can
/// see a screen it can only partly act on, e.g. Warehouse Manager on
/// Credits & Debts sees the supplier side but has no `credit.record`).
const _all = {
  AppScreen.dashboard,
  AppScreen.products,
  AppScreen.inventory,
  AppScreen.purchases,
  AppScreen.suppliers,
  AppScreen.customers,
  AppScreen.expenses,
  AppScreen.creditsDebts,
  AppScreen.warehouses,
  AppScreen.reports,
};

const _visibleScreensByRole = <String, Set<AppScreen>>{
  'Owner': _all,
  'Administrator': _all,
  'Warehouse Manager': {
    AppScreen.dashboard,
    AppScreen.products,
    AppScreen.inventory,
    AppScreen.purchases,
    AppScreen.suppliers,
    AppScreen.creditsDebts,
    AppScreen.warehouses,
    AppScreen.reports,
  },
  'Inventory Staff': {
    AppScreen.dashboard,
    AppScreen.products,
    AppScreen.inventory,
    AppScreen.reports,
  },
  'Sales Staff': {
    AppScreen.dashboard,
    AppScreen.products,
    AppScreen.inventory,
    AppScreen.customers,
    AppScreen.creditsDebts,
  },
  'Accountant / Finance': {
    AppScreen.dashboard,
    AppScreen.purchases,
    AppScreen.suppliers,
    AppScreen.customers,
    AppScreen.expenses,
    AppScreen.creditsDebts,
    AppScreen.reports,
  },
};

/// True if [role] should see [screen] at all. An unrecognized or missing role
/// (still onboarding, or a role the app doesn't know about) sees only the
/// dashboard — fails closed, the same way permission checks do.
bool isScreenVisible(String? role, AppScreen screen) {
  final allowed = _visibleScreensByRole[role];
  if (allowed == null) return screen == AppScreen.dashboard;
  return allowed.contains(screen);
}

/// Every screen [role] may see, in [AppScreen] declaration order.
List<AppScreen> visibleScreensFor(String? role) =>
    AppScreen.values.where((s) => isScreenVisible(role, s)).toList();

final _screensByPath = {for (final entry in screenPaths.entries) entry.value: entry.key};

/// The screen at router location [path], or `null` for a location that
/// isn't one of the module screens (splash, login, locked).
AppScreen? screenForPath(String path) => _screensByPath[path];
