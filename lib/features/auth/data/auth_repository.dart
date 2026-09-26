import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/device_info.dart';
import '../../../shared/services/secure_token_storage.dart';
import '../domain/auth_models.dart';

/// REAL, network-backed repository for the auth + profile endpoints
/// aimify-web exposes. See `docs/desktop-api.md`.
class AuthRepository {
  AuthRepository(this._api, this._tokenStorage);

  final ApiClient _api;
  final TokenStorage _tokenStorage;

  /// Logs in against `POST /api/v1/auth/login` and persists the returned
  /// JWT to secure storage.
  ///
  /// Sends this computer's name as `deviceName` so it shows up labeled on
  /// the website's "Signed-in devices" list. If the account has two-factor
  /// authentication on, a correct password with no [code] throws an
  /// [ApiException] with `isTwoFactorRequired` true (and *no* token is
  /// saved) — call this again with the 6-digit `code` (or a backup code)
  /// once the person enters one. A wrong/reused code throws with
  /// `isInvalidTwoFactorCode` true instead.
  Future<void> login({
    required String email,
    required String password,
    String? code,
  }) async {
    final json = await _api.postJson(ApiConstants.login, {
      'email': email,
      'password': password,
      'deviceName': currentDeviceName(),
      if (code != null && code.isNotEmpty) 'code': code,
    });
    final token = json['token'] as String;
    await _tokenStorage.saveToken(token);
  }

  /// Fetches `GET /api/v1/me` using the stored token. Returns `null` if no
  /// token is stored (never attempted a network call in that case).
  Future<MeResponse?> fetchMe() async {
    final token = await _tokenStorage.readToken();
    if (token == null) return null;

    final json = await _api.getJson(ApiConstants.me, bearerToken: token);
    return MeResponse.fromJson(json);
  }

  /// Revokes the session on the server (`POST /api/v1/auth/logout`) so the
  /// token stops working immediately, then discards it locally either way —
  /// a sign-out should never leave the person "stuck" signed in locally just
  /// because the revoke call failed (offline, server hiccup, already
  /// revoked from the website, ...).
  Future<void> logout() async {
    final token = await _tokenStorage.readToken();
    if (token != null) {
      try {
        await _api.postJson(ApiConstants.logout, const {}, bearerToken: token);
      } catch (_) {
        // Best-effort — the local token is cleared below regardless.
      }
    }
    await _tokenStorage.clearToken();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureTokenStorageProvider),
  );
});
