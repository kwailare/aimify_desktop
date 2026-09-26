/// Thrown by [ApiClient] for any non-2xx response from aimify-web.
///
/// Carries the HTTP [statusCode], the human-readable `error` message, the
/// machine-readable `code` (e.g. `"subscription_inactive"`,
/// `"forbidden_role"`, `"plan_limit"`, `"two_factor_required"`) and the raw
/// [details] map for whatever else that `code` came with (`limit`/`used`
/// for `plan_limit`, `role`/`permission` for `forbidden_role`,
/// `subscriptionStatus` for `subscription_inactive`) — see "Error handling"
/// in `docs/desktop-api.md` for the full list this app branches on.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code, Map<String, dynamic>? details})
      : details = details ?? const {};

  final int statusCode;
  final String message;
  final String? code;
  final Map<String, dynamic> details;

  /// Any `401` means the session ended — revoked, expired, or the token was
  /// never valid. Every authenticated call should treat this as "sign in
  /// again," not a generic error.
  bool get isUnauthorized => statusCode == 401;

  bool get isRateLimited => statusCode == 429;

  bool get isTwoFactorRequired => code == 'two_factor_required';
  bool get isInvalidTwoFactorCode => code == 'invalid_two_factor_code';

  /// `402` (pending/expired/cancelled) or `403` (suspended) — the
  /// organization's subscription doesn't unlock the API right now.
  bool get isSubscriptionInactive => code == 'subscription_inactive';

  /// `403` — the signed-in role isn't allowed to do this. Carries `role`
  /// and `permission` in [details].
  bool get isForbiddenRole => code == 'forbidden_role';

  /// `403` — the write would exceed the plan's cap. Carries `limit` and
  /// `used` in [details].
  bool get isPlanLimit => code == 'plan_limit';

  int? get limit => details['limit'] as int?;
  int? get used => details['used'] as int?;
  String? get requiredPermission => details['permission'] as String?;
  String? get subscriptionStatus => details['subscriptionStatus'] as String?;

  @override
  String toString() => 'ApiException($statusCode${code != null ? ', $code' : ''}): $message';
}

/// Thrown when a request never got an answer — no connection, DNS failure,
/// timeout. Distinct from [ApiException] so screens can show the offline
/// banner and a retry instead of a server-style error message.
class NetworkException implements Exception {
  const NetworkException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'NetworkException';
}
