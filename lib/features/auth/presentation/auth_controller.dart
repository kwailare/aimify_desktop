import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/utils/formatters.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

/// Session state for the whole app. `null` data means "signed out" — either
/// no token was ever stored, or the stored token was rejected (expired /
/// invalid / revoked) and was cleared.
class AuthController extends AsyncNotifier<MeResponse?> {
  @override
  Future<MeResponse?> build() => _restoreSession();

  Future<MeResponse?> _restoreSession() async {
    final repository = ref.read(authRepositoryProvider);
    try {
      final me = await repository.fetchMe();
      _applyLocaleFormats(me);
      return me;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        // Stored token is expired/invalid/revoked — drop it and treat as
        // signed out. Per docs/desktop-api.md, *any* 401 on an authenticated
        // call means the session ended (logout elsewhere, password change,
        // admin reset, removed from the team, ...), not just an expired JWT.
        await repository.logout();
        return null;
      }
      rethrow;
    }
  }

  void _applyLocaleFormats(MeResponse? me) {
    final org = me?.organization;
    if (org == null) return;
    updateLocaleFormatsFromOrg(
      currency: org.currency,
      dateFormatPattern: org.dateFormat,
      timezone: org.timezone,
      taxRate: org.taxRate,
      taxName: org.taxName,
    );
  }

  /// Throws [ApiException] on failure so the login screen can show the
  /// error inline. In particular:
  /// - `e.isTwoFactorRequired`: correct password, but the account has 2FA on
  ///   and no [code] (or the wrong one) was sent — prompt for a 6-digit
  ///   authenticator code (or backup code) and call this again with `code`.
  /// - `e.isInvalidTwoFactorCode`: the code was wrong or already used.
  ///
  /// On success, updates [state] with the freshly-fetched profile — callers
  /// don't need to.
  Future<void> login({
    required String email,
    required String password,
    String? code,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.login(email: email, password: password, code: code);
    final me = await repository.fetchMe();
    _applyLocaleFormats(me);
    state = AsyncData(me);
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  /// Re-fetches `/me` without disturbing the login flow — e.g. after the
  /// user finishes onboarding, confirms their email, or fixes their
  /// subscription on the web app and comes back to the desktop app
  /// expecting it to notice.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_restoreSession);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, MeResponse?>(AuthController.new);

/// Id of whoever is signed in, or `null`. Every data provider watches this
/// so that signing out (or in as someone else) throws away the previous
/// organization's products, warehouses and movements instead of showing
/// them to the next person.
final sessionUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider).valueOrNull?.user.id,
);
