// The app-wide rules from docs/desktop-api.md, checked against a fake HTTP
// server: any 401 ends the session, 402/403 refreshes /me (so a locked
// subscription reaches the locked screen), a request that gets no answer
// flips the offline banner, and users never see raw JSON or markup.

import 'dart:io';

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/shared/services/api_client.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/authed_api.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:aimify_desktop/shared/utils/friendly_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes/fake_token_storage.dart';

class _RecordingAuth extends AuthController {
  int logouts = 0;
  int refreshes = 0;

  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: null,
        role: null,
      );

  @override
  Future<void> logout() async {
    logouts++;
    state = const AsyncData(null);
  }

  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

ProviderContainer _container(http.Client client, {String? token = 'tok'}) {
  final storage = FakeTokenStorage();
  if (token != null) storage.saveToken(token);
  final container = ProviderContainer(
    overrides: [
      secureTokenStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(ApiClient(client)),
      authControllerProvider.overrideWith(_RecordingAuth.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

http.Response _json(int status, String body) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});

void main() {
  group('ApiClient', () {
    test('parses { error, code } into an ApiException and keeps the extra fields', () async {
      final client = ApiClient(
        MockClient((_) async => _json(
              403,
              '{"error":"Your Full Access plan allows 1 active warehouse.",'
              '"code":"plan_limit","limit":1,"used":1}',
            )),
      );

      await expectLater(
        client.getJson('http://x/warehouses'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isPlanLimit, 'isPlanLimit', isTrue)
              .having((e) => e.limit, 'limit', 1)
              .having((e) => e.used, 'used', 1)
              .having((e) => e.message, 'message', contains('allows 1 active warehouse')),
        ),
      );
    });

    test('a markup error page never leaks into the message', () async {
      final client = ApiClient(
        MockClient((_) async => http.Response('<html><body>Bad gateway</body></html>', 502)),
      );

      try {
        await client.getJson('http://x/products');
        fail('should have thrown');
      } on ApiException catch (e) {
        expect(e.statusCode, 502);
        expect(e.message, isNot(contains('<html')));
        expect(friendlyError(e), isNot(contains('<html')));
        expect(friendlyError(e), contains('problem on its side'));
      }
    });

    test('no connection becomes a NetworkException', () async {
      final client = ApiClient(MockClient((_) async => throw const SocketException('offline')));

      await expectLater(client.getJson('http://x/me'), throwsA(isA<NetworkException>()));
    });

    test('sends the bearer token', () async {
      String? seen;
      final client = ApiClient(MockClient((request) async {
        seen = request.headers['Authorization'];
        return _json(200, '{}');
      }));

      await client.getJson('http://x/me', bearerToken: 'abc');

      expect(seen, 'Bearer abc');
    });
  });

  group('AuthedApi', () {
    test('any 401 ends the session: message set, token path taken through logout', () async {
      final container = _container(MockClient((_) async => _json(401, '{"error":"Unauthorized."}')));
      final auth = container.read(authControllerProvider.notifier) as _RecordingAuth;
      await container.read(authControllerProvider.future);

      await expectLater(
        container.read(authedApiProvider).get('http://x/products'),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );

      expect(auth.logouts, 1);
      expect(container.read(sessionEndedMessageProvider), contains('session ended'));
    });

    test('a missing token is treated as a session that ended, without calling the server', () async {
      var calls = 0;
      final container = _container(
        MockClient((_) async {
          calls++;
          return _json(200, '{}');
        }),
        token: null,
      );
      final auth = container.read(authControllerProvider.notifier) as _RecordingAuth;
      await container.read(authControllerProvider.future);

      await expectLater(
        container.read(authedApiProvider).get('http://x/products'),
        throwsA(isA<ApiException>()),
      );

      expect(calls, 0);
      expect(auth.logouts, 1);
    });

    test('402 subscription_inactive refreshes /me instead of signing out', () async {
      final container = _container(MockClient((_) async => _json(
            402,
            '{"error":"Your free trial has ended.","code":"subscription_inactive",'
            '"subscriptionStatus":"expired"}',
          )));
      final auth = container.read(authControllerProvider.notifier) as _RecordingAuth;
      await container.read(authControllerProvider.future);

      await expectLater(
        container.read(authedApiProvider).get('http://x/products'),
        throwsA(isA<ApiException>().having((e) => e.isSubscriptionInactive, 'inactive', isTrue)),
      );

      expect(auth.refreshes, 1);
      expect(auth.logouts, 0);
    });

    test('403 forbidden_role refreshes /me so changed permissions show up', () async {
      final container = _container(MockClient((_) async => _json(
            403,
            '{"error":"Your role (Sales Staff) isn\'t allowed to do this.",'
            '"code":"forbidden_role","role":"Sales Staff","permission":"products.write"}',
          )));
      final auth = container.read(authControllerProvider.notifier) as _RecordingAuth;
      await container.read(authControllerProvider.future);

      await expectLater(
        container.read(authedApiProvider).post('http://x/products', {}),
        throwsA(isA<ApiException>().having((e) => e.requiredPermission, 'permission', 'products.write')),
      );

      expect(auth.refreshes, 1);
    });

    test('offline flips the banner on, and the next success clears it', () async {
      var online = false;
      final container = _container(MockClient((_) async {
        if (!online) throw const SocketException('offline');
        return _json(200, '{"products":[]}');
      }));
      await container.read(authControllerProvider.future);
      final api = container.read(authedApiProvider);

      await expectLater(api.get('http://x/products'), throwsA(isA<NetworkException>()));
      expect(container.read(offlineProvider), isTrue);

      online = true;
      await api.get('http://x/products');
      expect(container.read(offlineProvider), isFalse);
    });
  });

  group('friendlyError', () {
    test('network problems say so, with a way forward', () {
      expect(friendlyError(const NetworkException()), contains('internet connection'));
    });

    test('rate limiting asks the person to wait', () {
      expect(friendlyError(ApiException(429, 'x')), contains('few minutes'));
    });

    test('plan and role messages from the server pass through unchanged', () {
      expect(
        friendlyError(ApiException(403, 'Your Full Access plan allows 1 active warehouse.',
            code: 'plan_limit')),
        'Your Full Access plan allows 1 active warehouse.',
      );
    });

    test('anything unexpected falls back to a plain sentence', () {
      expect(friendlyError(StateError('boom')), 'Something went wrong. Please try again.');
    });
  });
}
