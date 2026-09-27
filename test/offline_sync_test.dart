// The hybrid online/offline behaviour: changes made with a poor or missing
// connection are saved on this computer, shown at once, and sent — in order,
// exactly once — when the connection is good. Runs the real notifiers, the
// real outbox and the real sync engine against in-memory fakes.

import 'dart:io';

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/data/auth_repository.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/customers/data/customers_repository.dart';
import 'package:aimify_desktop/features/customers/domain/customer.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/sync/sync_engine.dart';
import 'package:aimify_desktop/shared/offline/connection.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/offline/outbox.dart';
import 'package:aimify_desktop/shared/services/api_client.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/authed_api.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes/fake_repositories.dart';
import 'fakes/fake_token_storage.dart';

class _OwnerAuth extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
        ),
        role: 'Owner',
        permissions: ['products.write', 'stock.out', 'stock.adjust'],
      );

  @override
  Future<void> refresh() async {}
}

class _Rig {
  _Rig({MemoryLocalStore? store, List<Product>? products, FakeProductsRepository? repo})
      : store = store ?? MemoryLocalStore(),
        productsRepo =
            repo ?? FakeProductsRepository(products ?? [fixtureProduct('1', name: 'Rice', stock: 50)]),
        inventory = FakeInventoryRepository() {
    container = ProviderContainer(
      overrides: [
        secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        authControllerProvider.overrideWith(_OwnerAuth.new),
        ...fakeDataOverrides(products: productsRepo, inventory: inventory, store: this.store),
      ],
    );
  }

  final MemoryLocalStore store;
  final FakeProductsRepository productsRepo;
  final FakeInventoryRepository inventory;
  late final ProviderContainer container;

  ConnectionNotifier get connection => container.read(connectionProvider.notifier);
  SyncEngine get sync => container.read(syncEngineProvider.notifier);

  Future<void> ready() async {
    await container.read(authControllerProvider.future);
    await container.read(productsProvider.future);
    await container.read(outboxProvider.future);
    await container.read(movementsProvider.future);
  }

  List<OutboxOp> get ops => container.read(outboxOpsProvider);
  Product product(String id) => container.read(productListProvider).firstWhere((p) => p.id == id);

  Future<SubmitResult<MovementResult>> sell(int units, {String productId = '1'}) =>
      container.read(movementsProvider.notifier).record(
            productId: productId,
            warehouseId: 'w1',
            type: StockMovementType.stockOut,
            quantity: -units,
            reason: 'sale',
          );

  void dispose() => container.dispose();
}

void main() {
  group('sending or saving', () {
    test('a good connection sends the change straight away', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      final result = await rig.sell(5);

      expect(result.queued, isFalse);
      expect(rig.inventory.sent, [(productId: '1', quantity: -5)]);
      expect(rig.ops, isEmpty);
    });

    test('offline: the change is saved, shown at once, and not sent', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);

      final result = await rig.sell(5);

      expect(result.queued, isTrue);
      expect(rig.inventory.sent, isEmpty);
      expect(rig.ops, hasLength(1));
      expect(rig.ops.single.kind, OpKind.movement);
      expect(rig.ops.single.payload['quantity'], -5);

      // The stock figure and the ledger reflect it immediately.
      expect(rig.product('1').currentStock, 45);
      final ledger = rig.container.read(movementListProvider);
      expect(ledger.first.isPending, isTrue);
      expect(ledger.first.quantity, -5);
      expect(ledger.first.previousStock, 50);
      expect(ledger.first.newStock, 45);
    });

    test('a poor connection saves instead of making the person wait', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.poor);

      final result = await rig.sell(2);

      expect(result.queued, isTrue);
      expect(rig.inventory.sent, isEmpty);
    });

    test('a server refusal is shown, never queued', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.inventory.recordError = ApiException(403, 'Not allowed.', code: 'forbidden_role');

      await expectLater(rig.sell(1), throwsA(isA<ApiException>()));
      expect(rig.ops, isEmpty);
    });

    test('an offline low-stock movement raises the alert immediately', () async {
      final rig = _Rig(products: [fixtureProduct('1', name: 'Rice', stock: 8, min: 5)]);
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);

      await rig.sell(4);

      final alerts = rig.container.read(stockAlertListProvider);
      expect(alerts.lowStock.map((p) => p.id), ['1']);
    });
  });

  group('syncing', () {
    test('when the connection is good the saved changes are sent once, in order', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      await rig.sell(5);
      await rig.sell(3);

      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.inventory.sent, [
        (productId: '1', quantity: -5),
        (productId: '1', quantity: -3),
      ]);
      expect(rig.ops, isEmpty);
      expect(rig.container.read(syncEngineProvider).lastSyncedAt, isNotNull);
    });

    test('while changes are waiting, a new one queues behind them instead of overtaking', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      await rig.sell(1);

      // The link looks good again, but the first change can't get through
      // yet (the sync attempt fails), so it is still waiting.
      rig.inventory.recordError = const NetworkException();
      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();
      expect(rig.ops, hasLength(1));

      final result = await rig.sell(2);

      expect(result.queued, isTrue);
      expect(rig.ops.map((o) => o.payload['quantity']), [-1, -2], reason: 'first in, first out');
      expect(rig.inventory.sent.where((m) => m.quantity == -2), isEmpty,
          reason: 'the newer change must not overtake the older one');
    });

    test('a movement that may already have landed is not applied twice', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      // The send reaches the server but the answer is lost.
      rig.inventory
        ..recordError = const NetworkException()
        ..applyBeforeFailing = true;
      final result = await rig.sell(5);
      expect(result.queued, isTrue);
      expect(rig.ops.single.attempted, isTrue);
      expect(rig.inventory.sent, hasLength(1));

      // Back online: the engine checks the ledger, finds it, and does not resend.
      rig.inventory.recordError = null;
      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.inventory.sent, hasLength(1), reason: 'the second send would double-count');
      expect(rig.ops, isEmpty);
    });

    test('an interrupted send that did NOT land is sent again', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      rig.inventory.recordError = const NetworkException();
      await rig.sell(5);
      expect(rig.ops.single.attempted, isTrue);

      rig.inventory.recordError = null;
      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.inventory.sent, hasLength(2));
      expect(rig.ops, isEmpty);
    });

    test('a change the server refuses stays visible, and later changes still go through', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      await rig.sell(5);
      await rig.sell(2);

      rig.inventory.recordError = ApiException(403, 'Your role is not allowed.', code: 'forbidden_role');
      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      // Both were refused here, each kept with the reason.
      expect(rig.ops, hasLength(2));
      expect(rig.ops.every((o) => o.failed), isTrue);
      expect(rig.ops.first.error, contains('not allowed'));
      expect(rig.container.read(pendingCountProvider), 0);
      expect(rig.container.read(failedOpsProvider), hasLength(2));

      // Refused changes no longer affect the stock figure.
      expect(rig.product('1').currentStock, 50);

      // Discarding removes them.
      await rig.container.read(outboxProvider.notifier).removeWhere((o) => o.failed);
      expect(rig.ops, isEmpty);
    });

    test('losing the connection mid-sync keeps the rest waiting', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      await rig.sell(5);
      await rig.sell(2);

      rig.inventory.recordError = const NetworkException();
      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.ops, hasLength(2));
      expect(rig.ops.any((o) => o.failed), isFalse);
    });

    test('a product created offline can be sold offline, and both sync in order', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);

      const input = ProductInput(
        sku: 'NEW-1',
        name: 'Offline oil',
        unit: 'litre',
        purchasePrice: 10,
        sellingPrice: 15,
        minStock: 0,
      );
      final created = await rig.container.read(productsProvider.notifier).add(input);
      expect(created.queued, isTrue);

      final local = rig.container.read(productListProvider).firstWhere((p) => p.sku == 'NEW-1');
      expect(local.isPending, isTrue);
      expect(local.id, startsWith('local:'));

      await rig.container.read(movementsProvider.notifier).record(
            productId: local.id,
            warehouseId: 'w1',
            type: StockMovementType.stockIn,
            quantity: 20,
          );
      expect(rig.product(local.id).currentStock, 20);

      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.productsRepo.created.single.sku, 'NEW-1');
      // The movement was re-pointed at the id the server assigned.
      expect(rig.inventory.sent.single.productId, 'srv1');
      expect(rig.inventory.sent.single.quantity, 20);
      expect(rig.ops, isEmpty);
    });

    test('editing a product that only exists locally folds into its pending create', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      final notifier = rig.container.read(productsProvider.notifier);

      const input = ProductInput(
        sku: 'NEW-2', name: 'First name', unit: 'bag', purchasePrice: 1, sellingPrice: 2, minStock: 0,
      );
      await notifier.add(input);
      final local = rig.container.read(productListProvider).firstWhere((p) => p.sku == 'NEW-2');
      await notifier.edit(
        local.id,
        const ProductInput(
          sku: 'NEW-2', name: 'Second name', unit: 'bag', purchasePrice: 1, sellingPrice: 2, minStock: 0,
        ),
      );

      expect(rig.ops, hasLength(1));
      expect(rig.container.read(productListProvider).firstWhere((p) => p.sku == 'NEW-2').name, 'Second name');
    });

    test('archiving a product that never reached the server forgets it and its movements', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      final notifier = rig.container.read(productsProvider.notifier);

      await notifier.add(const ProductInput(
        sku: 'NEW-3', name: 'Temp', unit: 'bag', purchasePrice: 1, sellingPrice: 2, minStock: 0,
      ));
      final local = rig.container.read(productListProvider).firstWhere((p) => p.sku == 'NEW-3');
      await rig.container.read(movementsProvider.notifier).record(
            productId: local.id,
            warehouseId: 'w1',
            type: StockMovementType.stockIn,
            quantity: 3,
          );
      expect(rig.ops, hasLength(2));

      await notifier.archive(local.id);

      expect(rig.ops, isEmpty);
      expect(rig.container.read(productListProvider).any((p) => p.sku == 'NEW-3'), isFalse);
    });

    test('a movement on a product whose creation was refused is refused too, not lost silently', () async {
      // The server rejects the create (SKU already exists).
      final rig = _Rig(repo: _FailingCreates([fixtureProduct('1', name: 'Rice', stock: 50)]));
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      await rig.container.read(productsProvider.notifier).add(const ProductInput(
            sku: 'DUP', name: 'Dup', unit: 'bag', purchasePrice: 1, sellingPrice: 2, minStock: 0,
          ));
      final local = rig.container.read(productListProvider).firstWhere((p) => p.sku == 'DUP');
      await rig.container.read(movementsProvider.notifier).record(
            productId: local.id,
            warehouseId: 'w1',
            type: StockMovementType.stockIn,
            quantity: 3,
          );

      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.ops, hasLength(2));
      expect(rig.ops.every((o) => o.failed), isTrue);
      expect(rig.ops.last.error, contains('could not be created'));
      expect(rig.inventory.sent, isEmpty);
    });
  });

  group('surviving a restart', () {
    test('changes saved offline are still there — and still sync — after the app is reopened', () async {
      final store = MemoryLocalStore();
      final first = _Rig(store: store);
      await first.ready();
      first.connection.set(ConnectionQuality.offline);
      await first.sell(7);
      await first.container.read(outboxProvider.notifier).flushWrites();
      first.dispose();

      final second = _Rig(store: store);
      addTearDown(second.dispose);
      await second.ready();

      expect(second.ops, hasLength(1));
      expect(second.product('1').currentStock, 43);

      second.connection.set(ConnectionQuality.good);
      await second.sync.flush();
      expect(second.inventory.sent, [(productId: '1', quantity: -7)]);
      expect(second.ops, isEmpty);
    });

    test("one person's queue is never shown to another", () async {
      final store = MemoryLocalStore();
      await writeJson(store, 'u_someone-else_outbox', [
        OutboxOp(
          id: 'x',
          kind: OpKind.movement,
          payload: {'productId': '1', 'warehouseId': 'w1', 'type': 'stock_out', 'quantity': -9},
          createdAt: DateTime.now(),
        ).toJson(),
      ]);
      final rig = _Rig(store: store);
      addTearDown(rig.dispose);
      await rig.ready();

      expect(rig.ops, isEmpty);
    });

    test('a damaged queue file starts empty instead of crashing the app', () async {
      final store = MemoryLocalStore();
      await store.write('u_u1_outbox', '{ this is not json');
      final rig = _Rig(store: store);
      addTearDown(rig.dispose);
      await rig.ready();

      expect(rig.ops, isEmpty);
    });

    test('local-only modules are saved and restored', () async {
      final store = MemoryLocalStore();
      final first = _Rig(store: store);
      await first.ready();
      first.container.read(customersProvider);
      await Future<void>.delayed(Duration.zero);
      first.container.read(customersProvider.notifier).addCustomer(
            const Customer(
              id: 'c1',
              name: 'Blessing Store',
              phone: '0700',
              creditLimit: 1000,
              balanceOwed: 250,
              transactionHistory: [],
            ),
          );
      await first.container.read(customersProvider.notifier).flushWrites();
      first.dispose();

      final second = _Rig(store: store);
      addTearDown(second.dispose);
      await second.ready();
      second.container.read(customersProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final customers = second.container.read(customersProvider);
      expect(customers.single.name, 'Blessing Store');
      expect(customers.single.balanceOwed, 250);
    });
  });

  group('cached reads and the offline session', () {
    test('a read that cannot reach the server serves the saved copy and says so', () async {
      var online = true;
      final store = MemoryLocalStore();
      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()..saveToken('tok')),
          localStoreProvider.overrideWithValue(store),
          authControllerProvider.overrideWith(_OwnerAuth.new),
          apiClientProvider.overrideWithValue(
            ApiClient(MockClient((_) async {
              if (!online) throw const SocketException('offline');
              return http.Response('{"products":[{"id":"p"}]}', 200);
            })),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final api = container.read(authedApiProvider);

      expect(await api.get('http://x/products', cacheKey: 'products'), {'products': [{'id': 'p'}]});
      expect(container.read(staleSinceProvider), isNull);

      online = false;
      final offline = await api.get('http://x/products', cacheKey: 'products');
      expect(offline, {'products': [{'id': 'p'}]});
      expect(container.read(staleSinceProvider), isNotNull);
      expect(container.read(connectionProvider), ConnectionQuality.offline);

      online = true;
      await api.get('http://x/products', cacheKey: 'products');
      expect(container.read(staleSinceProvider), isNull, reason: 'fresh data clears the notice');
      expect(container.read(connectionProvider), ConnectionQuality.good);
    });

    test('with no saved copy, an offline read is still an error', () async {
      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()..saveToken('tok')),
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
          authControllerProvider.overrideWith(_OwnerAuth.new),
          apiClientProvider.overrideWithValue(
            ApiClient(MockClient((_) async => throw const SocketException('offline'))),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await expectLater(
        container.read(authedApiProvider).get('http://x/products', cacheKey: 'products'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a slow answer counts as a poor connection', () async {
      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()..saveToken('tok')),
          localStoreProvider.overrideWithValue(MemoryLocalStore()),
          authControllerProvider.overrideWith(_OwnerAuth.new),
        ],
      );
      addTearDown(container.dispose);

      container.read(connectionProvider.notifier).reportSuccess(const Duration(seconds: 6));
      expect(container.read(connectionProvider), ConnectionQuality.poor);
      container.read(connectionProvider.notifier).reportSuccess(const Duration(milliseconds: 300));
      expect(container.read(connectionProvider), ConnectionQuality.good);
    });

    test('the app reopens signed in with no network, from the saved session', () async {
      const meJson = '{"user":{"id":"u1","name":"Ada","email":"a@b.c","emailVerified":true},'
          '"organization":{"id":"o1","name":"Obi Ltd","industry":"Wholesale","currency":"NGN",'
          '"warehouseName":null,"subscriptionStatus":"trial"},"role":"Owner",'
          '"permissions":["stock.out"],"plan":null}';
      var online = true;
      final store = MemoryLocalStore();
      final tokens = FakeTokenStorage()..saveToken('tok');
      final client = MockClient((_) async {
        if (!online) throw const SocketException('offline');
        return http.Response(meJson, 200, headers: {'content-type': 'application/json'});
      });

      AuthRepository repo() => AuthRepository(ApiClient(client), tokens, store);

      // Online launch: works, and saves the session.
      final first = await repo().fetchMe();
      expect(first!.user.name, 'Ada');

      // Offline launch: same person, same permissions, no error.
      online = false;
      final second = await repo().fetchMe();
      expect(second!.user.name, 'Ada');
      expect(second.role, 'Owner');
      expect(second.permissions, ['stock.out']);

      // Signing out forgets the saved session, so the next launch asks for sign-in.
      await repo().logout();
      await expectLater(repo().fetchMe(), completion(isNull));
      expect(await store.read('session_me'), isNull);
    });

    test('an offline launch with no saved session cannot pretend to be signed in', () async {
      final repo = AuthRepository(
        ApiClient(MockClient((_) async => throw const SocketException('offline'))),
        FakeTokenStorage()..saveToken('tok'),
        MemoryLocalStore(),
      );

      await expectLater(repo.fetchMe(), throwsA(isA<NetworkException>()));
    });

    test('a revoked token is still a sign-out, even though a saved session exists', () async {
      final store = MemoryLocalStore();
      await store.write('session_me', '{"user":{"id":"u1","name":"Ada","email":"a@b.c"}}');
      final repo = AuthRepository(
        ApiClient(MockClient((_) async => http.Response('{"error":"Unauthorized."}', 401))),
        FakeTokenStorage()..saveToken('tok'),
        store,
      );

      await expectLater(
        repo.fetchMe(),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });
  });

  group('the banner', () {
    Future<ProviderContainer> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
          authControllerProvider.overrideWith(_OwnerAuth.new),
          ...fakeDataOverrides(),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const AimifyApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return container;
    }

    testWidgets('offline, poor and back-online each say the right thing', (tester) async {
      final container = await pump(tester);
      expect(find.textContaining("You're offline"), findsNothing);
      expect(find.text('Online · synced'), findsOneWidget);

      container.read(connectionProvider.notifier).set(ConnectionQuality.offline);
      await tester.pump();
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);

      container.read(connectionProvider.notifier).set(ConnectionQuality.poor);
      await tester.pump();
      expect(find.textContaining('Poor connection.'), findsOneWidget);

      container.read(connectionProvider.notifier).set(ConnectionQuality.good);
      await tester.pump();
      expect(find.textContaining("You're offline"), findsNothing);
      expect(find.textContaining('Poor connection.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('waiting changes are counted, and can be reviewed', (tester) async {
      final container = await pump(tester);
      await container.read(outboxProvider.future);
      container.read(connectionProvider.notifier).set(ConnectionQuality.offline);
      await container.read(outboxProvider.notifier).add(
            OutboxOp(
              id: 'a',
              kind: OpKind.movement,
              payload: {'productId': '1', 'warehouseId': 'w1', 'type': 'stock_out', 'quantity': -3},
              createdAt: DateTime.now(),
            ),
          );
      await tester.pump();

      expect(find.textContaining('1 change(s) waiting'), findsWidgets);

      await tester.tap(find.textContaining('Offline · 1 waiting'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Changes waiting to sync'), findsOneWidget);
      expect(find.textContaining('Stock out -3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// A products repository whose creates are refused, like a duplicate SKU.
class _FailingCreates extends FakeProductsRepository {
  _FailingCreates(super.products);

  @override
  Future<Product> create(ProductInput input) async =>
      throw ApiException(409, 'A product with this SKU already exists.');
}
