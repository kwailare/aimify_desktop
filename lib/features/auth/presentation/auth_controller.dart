import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_exception.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// Session state for the whole app. `null` data means "signed out" — either
/// no token was ever stored, or the stored token was rejected (expired /
/// invalid) and was cleared.
class AuthController extends AsyncNotifier<MeResponse?> {
  @override
  Future<MeResponse?> build() => _restoreSession();

  Future<MeResponse?> _restoreSession() async {
    final repository = ref.read(authRepositoryProvider);
    try {
      return await repository.fetchMe();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // Stored token is expired/invalid — drop it and treat as signed out.
        await repository.logout();
        return null;
      }
      rethrow;
    }
  }

  /// Throws [ApiException] on failure (bad credentials, network error) so
  /// the login screen can show the error inline. On success, updates
  /// [state] with the freshly-fetched profile — callers don't need to.
  Future<void> login({required String email, required String password}) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.login(email: email, password: password);
    final me = await repository.fetchMe();
    state = AsyncData(me);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  /// Re-fetches `/me` without disturbing the login flow — e.g. after the
  /// user finishes onboarding on the web app and comes back to the desktop
  /// app expecting their organization to now appear.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_restoreSession);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, MeResponse?>(AuthController.new);
