import 'package:aimify_desktop/shared/services/secure_token_storage.dart';

/// In-memory [TokenStorage] for widget tests — avoids touching the real OS
/// keychain, which isn't available (and can hang) in a headless test run.
class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<void> clearToken() async => _token = null;
}
