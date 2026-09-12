/// Thrown by [ApiClient] for any non-2xx response from aimify-web.
///
/// Carries the HTTP [statusCode] and the human-readable `error` message the
/// API sent back (see `docs/desktop-api.md`), so callers can branch on
/// status (e.g. 401 -> force re-login) without re-parsing the body.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
