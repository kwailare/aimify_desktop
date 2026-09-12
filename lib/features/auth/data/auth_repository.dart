import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/secure_token_storage.dart';
import '../domain/auth_models.dart';

/// REAL, network-backed repository for the two endpoints aimify-web
/// currently exposes: login and profile fetch. See `docs/desktop-api.md`.
class AuthRepository {
  AuthRepository(this._api, this._tokenStorage);

  final ApiClient _api;
  final TokenStorage _tokenStorage;

  /// Logs in against `POST /api/v1/auth/login` and persists the returned
  /// JWT to secure storage. Throws [ApiException] on 400/401.
  Future<void> login({required String email, required String password}) async {
    final json = await _api.postJson(ApiConstants.login, {
      'email': email,
      'password': password,
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

  Future<void> logout() => _tokenStorage.clearToken();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureTokenStorageProvider),
  );
});
