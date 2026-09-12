/// Connection details for the aimify-web `/api/v1` backend.
///
/// See `docs/desktop-api.md` for the full contract. Only `/auth/login` and
/// `/me` exist server-side today — everything else in this app (products,
/// inventory, purchases, sales, customers, suppliers, expenses) runs on
/// local mock data until matching endpoints are built there.
class ApiConstants {
  ApiConstants._();

  /// aimify-web running locally via `next dev`.
  ///
  /// TODO: swap for the production Vercel domain once aimify-web is
  /// deployed, ideally via a build-time flavor/environment flag rather than
  /// editing this constant by hand.
  static const String baseUrl = 'http://localhost:3000';

  static const String login = '$baseUrl/api/v1/auth/login';
  static const String me = '$baseUrl/api/v1/me';
}
