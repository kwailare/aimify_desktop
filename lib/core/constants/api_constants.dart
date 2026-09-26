/// Connection details for the aimify-web `/api/v1` backend.
///
/// See `docs/desktop-api.md` for the full contract. Auth, `/me`, warehouses,
/// products (with images), categories/units, stock movements and stock
/// alerts are real. Customers, suppliers, purchases, expenses and credit
/// tracking have no backend yet, so those screens stay local-only and are
/// marked as such.
class ApiConstants {
  ApiConstants._();

  /// aimify-web running locally via `next dev`.
  ///
  /// TODO: swap for the production Vercel domain once aimify-web is
  /// deployed, ideally via a build-time flavor/environment flag rather than
  /// editing this constant by hand.
  static const String baseUrl = 'http://localhost:3000';

  static const String _v1 = '$baseUrl/api/v1';

  static const String login = '$_v1/auth/login';
  static const String logout = '$_v1/auth/logout';
  static const String me = '$_v1/me';

  static const String warehouses = '$_v1/warehouses';
  static String warehouse(String id) => '$_v1/warehouses/$id';

  static const String products = '$_v1/products';
  static String product(String id) => '$_v1/products/$id';
  static String productImage(String id) => '$_v1/products/$id/image';

  static const String categories = '$_v1/categories';
  static String category(String id) => '$_v1/categories/$id';
  static const String units = '$_v1/units';
  static String unit(String id) => '$_v1/units/$id';

  static const String movements = '$_v1/inventory/movements';
  static const String stockAlerts = '$_v1/alerts/stock';

  /// Where "manage your subscription" links in the locked-account screen
  /// point — confirmed against the aimify-web source
  /// (`app/dashboard/billing/page.tsx`, `lib/site.ts`), not guessed.
  static const String billingUrl = '$baseUrl/dashboard/billing';

  /// The website's Team page, where owners and administrators invite people
  /// and change roles (`app/dashboard/team`). The desktop app has no team
  /// screen of its own.
  static const String teamUrl = '$baseUrl/dashboard/team';
}
