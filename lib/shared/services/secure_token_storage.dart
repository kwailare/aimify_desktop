import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the auth JWT is persisted. Abstracted so widget tests can swap in
/// an in-memory fake instead of hitting the real OS keychain (which either
/// isn't available or hangs waiting on a user session in a headless test
/// runner) — see `test/widget_test.dart`.
abstract class TokenStorage {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> clearToken();
}

/// Persists the auth JWT in the OS-native secure store (Windows Credential
/// Locker / macOS Keychain / libsecret on Linux) — never `shared_preferences`
/// or plain files.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'aimify_auth_token';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}

final secureTokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage(const FlutterSecureStorage());
});
