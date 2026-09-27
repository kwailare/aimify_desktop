import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../offline/connection.dart';
import '../offline/local_store.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'secure_token_storage.dart';

/// Short message the login screen shows once after a session ends on its
/// own (revoked from the website, removed from the team, password
/// changed...), so being sent back to sign-in never feels unexplained.
final sessionEndedMessageProvider = StateProvider<String?>((ref) => null);

/// The one door every authenticated call goes through. It adds the stored
/// bearer token and applies the app-wide rules from `docs/desktop-api.md`:
///
/// - any `401` means the session ended: clear the token and go to sign-in;
/// - any `402`/`403` refreshes `/me`, so a locked subscription lands on the
///   locked screen and changed permissions or plan usage show up at once;
/// - every request feeds [connectionProvider], so the app knows whether the
///   network is good, poor or gone — and can choose between sending a change
///   now and saving it for later;
/// - reads given a `cacheKey` are saved after each success and served from
///   that saved copy when the network can't answer, so screens still open.
class AuthedApi {
  AuthedApi(this._ref);

  final Ref _ref;

  ApiClient get _client => _ref.read(apiClientProvider);

  /// [cacheKey] names this read in the per-user cache (e.g. `products`).
  Future<Map<String, dynamic>> get(String url, {String? cacheKey}) async {
    try {
      final json = await _run((t) => _client.getJson(url, bearerToken: t));
      if (cacheKey != null) await _saveCache(cacheKey, json);
      _ref.read(staleSinceProvider.notifier).state = null;
      return json;
    } on NetworkException {
      final cached = cacheKey == null ? null : await _readCache(cacheKey);
      if (cached == null) rethrow;
      final stale = _ref.read(staleSinceProvider);
      if (stale == null || cached.savedAt.isBefore(stale)) {
        _ref.read(staleSinceProvider.notifier).state = cached.savedAt;
      }
      return cached.data;
    }
  }

  Future<Map<String, dynamic>> post(String url, Map<String, dynamic> body) =>
      _run((t) => _client.postJson(url, body, bearerToken: t));

  Future<Map<String, dynamic>> patch(String url, Map<String, dynamic> body) =>
      _run((t) => _client.patchJson(url, body, bearerToken: t));

  Future<Map<String, dynamic>> delete(String url) =>
      _run((t) => _client.deleteJson(url, bearerToken: t));

  Future<Map<String, dynamic>> postFile(
    String url, {
    required String field,
    required List<int> bytes,
    required String filename,
  }) =>
      _run(
        (t) => _client.postFile(url, field: field, bytes: bytes, filename: filename, bearerToken: t),
      );

  Future<Map<String, dynamic>> _run(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final token = await _ref.read(secureTokenStorageProvider).readToken();
    if (token == null) {
      await _endSession();
      throw ApiException(401, 'Not signed in.');
    }

    final connection = _ref.read(connectionProvider.notifier);
    final clock = Stopwatch()..start();
    try {
      final result = await call(token);
      connection.reportSuccess(clock.elapsed);
      return result;
    } on ApiException catch (e) {
      // The server answered, so the network is fine.
      connection.reportSuccess(clock.elapsed);
      if (e.isUnauthorized) {
        await _endSession();
      } else if (e.statusCode == 402 || e.statusCode == 403) {
        unawaited(_ref.read(authControllerProvider.notifier).refresh());
      }
      rethrow;
    } on NetworkException catch (e) {
      connection.reportFailure(e);
      rethrow;
    }
  }

  Future<void> _endSession() async {
    _ref.read(sessionEndedMessageProvider.notifier).state =
        'Your session ended. Please sign in again.';
    await _ref.read(authControllerProvider.notifier).logout();
  }

  String? _cacheKey(String name) {
    final userId = _ref.read(sessionUserIdProvider);
    return userId == null ? null : 'u_${userId}_cache_$name';
  }

  Future<void> _saveCache(String name, Map<String, dynamic> data) async {
    final key = _cacheKey(name);
    if (key == null) return;
    try {
      await writeJson(_ref.read(localStoreProvider), key, {
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'data': data,
      });
    } catch (_) {
      // A cache that can't be written must never break a successful read.
    }
  }

  Future<({DateTime savedAt, Map<String, dynamic> data})?> _readCache(String name) async {
    final key = _cacheKey(name);
    if (key == null) return null;
    try {
      final raw = await readJson(_ref.read(localStoreProvider), key);
      if (raw is! Map<String, dynamic>) return null;
      final data = raw['data'];
      final savedAt = DateTime.tryParse(raw['savedAt'] as String? ?? '');
      if (data is! Map<String, dynamic> || savedAt == null) return null;
      return (savedAt: savedAt.toLocal(), data: data);
    } catch (_) {
      return null;
    }
  }
}

final authedApiProvider = Provider<AuthedApi>((ref) => AuthedApi(ref));
