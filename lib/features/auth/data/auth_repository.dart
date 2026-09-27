import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/connection.dart';
import '../../../shared/offline/local_store.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/api_exception.dart';
import '../../../shared/services/device_info.dart';
import '../../../shared/services/secure_token_storage.dart';
import '../domain/auth_models.dart';

/// REAL, network-backed repository for the auth + profile endpoints
/// aimify-web exposes. See `docs/desktop-api.md`.
class AuthRepository {
  AuthRepository(this._api, this._tokenStorage, this._store, [this._onNetworkResult]);

  final ApiClient _api;
  final TokenStorage _tokenStorage;
  final LocalStore _store;

  /// Told after each `/me` attempt whether the network answered, so the
  /// app's connection status stays accurate (`true` = it did).
  final void Function(bool reachable, Duration elapsed, NetworkException? error)? _onNetworkResult;

  /// The last `/me` the server sent, kept so the app can reopen and work
  /// with no connection. It's the account, organization, role, permissions
  /// and plan — never the token, which lives only in the OS secure store.
  static const _sessionKey = 'session_me';

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
  ///
  /// If the network can't answer, the saved copy from the last successful
  /// call is used instead, so a person who was signed in can keep working
  /// offline. (A `401` still means the session ended and is not softened.)
  Future<MeResponse?> fetchMe() async {
    final token = await _tokenStorage.readToken();
    if (token == null) return null;

    final clock = Stopwatch()..start();
    try {
      final json = await _api.getJson(ApiConstants.me, bearerToken: token);
      _onNetworkResult?.call(true, clock.elapsed, null);
      await _saveSession(json);
      return MeResponse.fromJson(json);
    } on NetworkException catch (e) {
      _onNetworkResult?.call(false, clock.elapsed, e);
      final cached = await _readSession();
      if (cached == null) rethrow;
      return cached;
    } on ApiException {
      _onNetworkResult?.call(true, clock.elapsed, null);
      rethrow;
    }
  }

  Future<void> _saveSession(Map<String, dynamic> json) async {
    try {
      await writeJson(_store, _sessionKey, json);
    } catch (_) {
      // Not being able to cache must never fail a successful sign-in.
    }
  }

  Future<MeResponse?> _readSession() async {
    try {
      final raw = await readJson(_store, _sessionKey);
      return raw is Map<String, dynamic> ? MeResponse.fromJson(raw) : null;
    } catch (_) {
      return null;
    }
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
    // Signed out: the next launch must show the sign-in screen, not a
    // cached session. (Changes still waiting to sync are kept — they belong
    // to the user's own saved queue and sync after the next sign-in.)
    await _store.delete(_sessionKey);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureTokenStorageProvider),
    ref.watch(localStoreProvider),
    (reachable, elapsed, error) {
      final connection = ref.read(connectionProvider.notifier);
      reachable ? connection.reportSuccess(elapsed) : connection.reportFailure(error!);
    },
  );
});
