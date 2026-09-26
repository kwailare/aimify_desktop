import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'secure_token_storage.dart';

/// True while the last request failed for lack of a connection. The app
/// shell shows an offline banner with a retry while this is set, and any
/// later successful request clears it.
final offlineProvider = StateProvider<bool>((ref) => false);

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
/// - a request that never got an answer flips [offlineProvider].
class AuthedApi {
  AuthedApi(this._ref);

  final Ref _ref;

  ApiClient get _client => _ref.read(apiClientProvider);

  Future<Map<String, dynamic>> get(String url) => _run((t) => _client.getJson(url, bearerToken: t));

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

    try {
      final result = await call(token);
      _ref.read(offlineProvider.notifier).state = false;
      return result;
    } on ApiException catch (e) {
      _ref.read(offlineProvider.notifier).state = false;
      if (e.isUnauthorized) {
        await _endSession();
      } else if (e.statusCode == 402 || e.statusCode == 403) {
        unawaited(_ref.read(authControllerProvider.notifier).refresh());
      }
      rethrow;
    } on NetworkException {
      _ref.read(offlineProvider.notifier).state = true;
      rethrow;
    }
  }

  Future<void> _endSession() async {
    _ref.read(sessionEndedMessageProvider.notifier).state =
        'Your session ended. Please sign in again.';
    await _ref.read(authControllerProvider.notifier).logout();
  }
}

final authedApiProvider = Provider<AuthedApi>((ref) => AuthedApi(ref));
