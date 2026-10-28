/// Connection details for the aimify-web `/api/v1` backend.
///
/// See `docs/desktop-api.md` for the full contract. Auth, `/me`, warehouses,
/// products (with images), categories/units, stock movements, stock alerts,
/// customers, suppliers and the credit ledger are real. Purchases and
/// expenses have no backend yet, so those two screens stay local-only and are
/// marked as such.
class ApiConstants {
  ApiConstants._();

  /// The aimify-web server this build talks to. Defaults to a local
  /// `next dev`; a release build points at production by defining it:
  ///
  ///   flutter build windows --dart-define=AIMIFY_API_URL=https://www.aimify.app
  static const String baseUrl = String.fromEnvironment(
    'AIMIFY_API_URL',
    defaultValue: 'http://localhost:3000',
  );

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

  static const String customers = '$_v1/customers';
  static String customer(String id) => '$_v1/customers/$id';
  static const String suppliers = '$_v1/suppliers';
  static String supplier(String id) => '$_v1/suppliers/$id';

  /// Supplier ids and names only — for showing and picking a product's
  /// supplier without `suppliers.view`.
  static const String supplierOptions = '$_v1/suppliers/options';
  static const String creditEntries = '$_v1/credit-entries';

  static const String movements = '$_v1/inventory/movements';
  static const String stockAlerts = '$_v1/alerts/stock';
  static const String valuationReport = '$_v1/reports/valuation';
  static const String purchases = '$_v1/purchases';
  static String purchase(String id) => '$_v1/purchases/$id';
  static String purchaseReceive(String id) => '$_v1/purchases/$id/receive';
  static String purchasePayments(String id) => '$_v1/purchases/$id/payments';
  static String purchaseCancel(String id) => '$_v1/purchases/$id/cancel';
  static const String sales = '$_v1/sales';
  static const String customerTypes = '$_v1/customer-types';
  static String customerType(String id) => '$_v1/customer-types/$id';
  static const String debtReport = '$_v1/reports/debts';
  static String sale(String id) => '$_v1/sales/$id';
  static String salePayments(String id) => '$_v1/sales/$id/payments';
  static String saleVoid(String id) => '$_v1/sales/$id/void';

  static const String team = '$_v1/team';
  static const String teamInvitations = '$_v1/team/invitations';
  static const String organizationSetup = '$_v1/organization/setup';

  /// Where "manage your subscription" links in the locked-account screen
  /// point — confirmed against the aimify-web source
  /// (`app/dashboard/billing/page.tsx`, `lib/site.ts`), not guessed.
  static const String billingUrl = '$baseUrl/dashboard/billing';

  /// The website's Team page, where owners and administrators change roles,
  /// remove members and revoke invitations (`app/dashboard/team`). Inviting
  /// can also be done in the app's guided setup.
  static const String teamUrl = '$baseUrl/dashboard/team';

  /// The website's Organization page, where the company profile is edited
  /// (`app/dashboard/organization`).
  static const String organizationUrl = '$baseUrl/dashboard/organization';
}
