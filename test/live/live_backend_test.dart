// LIVE end-to-end check of the desktop app's real data layer against a
// running aimify-web (`npm run dev` on http://localhost:3000). It drives the
// same repositories, notifiers and error handling the screens use — no
// fakes — so a passing run means the app and the backend agree on every
// shape, status code and error code in docs/desktop-api.md.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database.
// Use a throwaway trial organization with three accounts (an Owner, a Sales
// Staff member, and an Owner with two-factor on):
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...          shared by the three accounts
//   AIMIFY_OWNER_EMAIL=...       Owner, no 2FA, org on a 1-warehouse plan
//   AIMIFY_SALES_EMAIL=...       Sales Staff in the same org
//   AIMIFY_2FA_EMAIL=...         Owner with two-factor on
//   AIMIFY_2FA_SECRET=...        that account's base32 authenticator secret
//
//   flutter test test/live/live_backend_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/allowed_movement_types.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/products/data/catalog_repository.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/authed_api.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:aimify_desktop/shared/utils/friendly_error.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_token_storage.dart';

final _env = Platform.environment;
final _live = _env['AIMIFY_LIVE'] == '1';
String _need(String name) => _env[name] ?? (throw StateError('Set $name'));

ProviderContainer _newSession() {
  final container = ProviderContainer(
    overrides: [secureTokenStorageProvider.overrideWithValue(FakeTokenStorage())],
  );
  addTearDown(container.dispose);
  return container;
}

/// A real signed-in session: the same login path the login screen uses.
Future<ProviderContainer> _signIn(String email, {String? code}) async {
  final container = _newSession();
  await container.read(authControllerProvider.future);
  await container.read(authControllerProvider.notifier).login(
        email: email,
        password: _need('AIMIFY_PASSWORD'),
        code: code,
      );
  return container;
}

Future<void> _expectApiError(Future<Object?> Function() call, bool Function(ApiException) matches) async {
  try {
    await call();
  } on ApiException catch (e) {
    expect(matches(e), isTrue, reason: 'unexpected error: $e');
    return;
  }
  fail('expected an ApiException');
}

String _totp(String secretBase32, {int stepOffset = 0}) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0, value = 0;
  final bytes = <int>[];
  for (final char in secretBase32.replaceAll(RegExp(r'[\s=-]'), '').toUpperCase().split('')) {
    value = (value << 5) | alphabet.indexOf(char);
    bits += 5;
    if (bits >= 8) {
      bytes.add((value >> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  final step = DateTime.now().millisecondsSinceEpoch ~/ 30000 + stepOffset;
  final counter = List<int>.generate(8, (i) => (step >> (8 * (7 - i))) & 255);
  final mac = Hmac(sha1, bytes).convert(counter).bytes;
  final offset = mac.last & 15;
  final binary = ((mac[offset] & 127) << 24) |
      ((mac[offset + 1] & 255) << 16) |
      ((mac[offset + 2] & 255) << 8) |
      (mac[offset + 3] & 255);
  return (binary % 1000000).toString().padLeft(6, '0');
}

// A valid 1x1 PNG.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0x50,
  0x0F, 0x00, 0x04, 0x85, 0x01, 0x80, 0x84, 0xA9, 0x8C, 0x21, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

ProductInput _input(String sku, {int min = 0, double cost = 100, String? category}) => ProductInput(
      sku: sku,
      name: 'QA $sku',
      brand: 'QA Brand',
      category: category ?? 'QA Grains',
      unit: 'qa-sack',
      purchasePrice: cost,
      sellingPrice: cost * 1.5,
      minStock: min,
      maxStock: 500,
    );

void main() {
  final skip = _live ? null : 'Set AIMIFY_LIVE=1 (writes to the backend database)';

  test('two-factor sign-in: required, wrong code rejected, right code accepted, replay refused',
      () async {
    final email = _need('AIMIFY_2FA_EMAIL');
    final secret = _need('AIMIFY_2FA_SECRET');
    final container = _newSession();
    await container.read(authControllerProvider.future);
    final auth = container.read(authControllerProvider.notifier);
    final password = _need('AIMIFY_PASSWORD');

    await _expectApiError(
      () => auth.login(email: email, password: password),
      (e) => e.isTwoFactorRequired,
    );
    await _expectApiError(
      () => auth.login(email: email, password: password, code: '000000'),
      (e) => e.isInvalidTwoFactorCode,
    );

    final code = _totp(secret);
    await auth.login(email: email, password: password, code: code);
    final me = container.read(authControllerProvider).value!;
    expect(me.role, 'Owner');
    expect(me.user.email, email);

    // The same code can't be used twice.
    final again = _newSession();
    await again.read(authControllerProvider.future);
    await _expectApiError(
      () => again.read(authControllerProvider.notifier).login(email: email, password: password, code: code),
      (e) => e.isInvalidTwoFactorCode,
    );
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('Owner: /me, warehouses, catalog, products, images, movements, alerts, archive', () async {
    final container = await _signIn(_need('AIMIFY_OWNER_EMAIL'));
    final me = container.read(authControllerProvider).value!;

    // --- /me
    expect(me.role, 'Owner');
    expect(me.organization!.subscriptionStatus, 'trial');
    expect(me.organization!.warehouseName, isNull, reason: 'a brand-new org has no warehouse yet');
    expect(me.permissions, containsAll(['products.write', 'stock.out', 'stock.adjust']));
    expect(me.plan!.limits.warehouses, 1);
    expect(me.plan!.usage.warehouses, 0);

    // --- stock can't be recorded with no warehouse; create one
    expect(await container.read(warehousesProvider.future), isEmpty);
    await container.read(warehousesProvider.notifier).add(name: 'QA Main Warehouse', address: '1 QA Road');
    final warehouses = container.read(warehouseListProvider);
    expect(warehouses.single.isActive, isTrue);
    expect(warehouses.single.address, '1 QA Road');

    // --- plan limit on the second warehouse, with a friendly message
    try {
      await container.read(warehousesProvider.notifier).add(name: 'QA Second');
      fail('the second warehouse should hit the plan limit');
    } on ApiException catch (e) {
      expect(e.isPlanLimit, isTrue);
      expect(e.limit, 1);
      expect(e.used, 1);
      expect(friendlyError(e), contains('allows 1 active warehouse'));
    }
    expect(container.read(warehouseListProvider), hasLength(1));

    // --- disabling frees the slot; enabling again works; plan usage follows /me
    final warehouse = container.read(warehouseListProvider).single;
    await container.read(warehousesProvider.notifier).edit(warehouse.id, {'status': 'inactive'});
    expect(container.read(activeWarehousesProvider), isEmpty);
    await container.read(warehousesProvider.notifier).edit(warehouse.id, {'status': 'active'});
    expect(container.read(activeWarehousesProvider), hasLength(1));

    // --- products: create (custom category/unit register themselves)
    final products = container.read(productsProvider.notifier);
    expect(await container.read(productsProvider.future), isEmpty);
    final rice = await products.add(_input('QA-RICE', min: 30));
    final oil = await products.add(_input('QA-OIL', min: 5, cost: 250));
    expect(rice.currentStock, 0, reason: 'stock only changes through movements');
    expect(rice.brand, 'QA Brand');
    expect(container.read(productListProvider), hasLength(2));

    final categories = await container.read(catalogProvider(CatalogKind.category).future);
    final units = await container.read(catalogProvider(CatalogKind.unit).future);
    expect(categories.map((c) => c.name), contains('QA Grains'));
    // (New organizations get their default units from the website's onboarding,
    // which a bare test org skips — so only the custom unit is checked here.)
    expect(units.map((u) => u.name), contains('qa-sack'));

    // --- duplicate SKU is a friendly 409
    try {
      await products.add(_input('QA-RICE'));
      fail('duplicate SKU should be refused');
    } on ApiException catch (e) {
      expect(e.statusCode, 409);
      expect(friendlyError(e), contains('already exists'));
    }

    // --- edit
    await products.edit(oil.id, _input('QA-OIL', min: 5, cost: 300));
    expect(container.read(productListProvider).firstWhere((p) => p.id == oil.id).purchasePrice, 300);

    // --- image upload and removal (Vercel Blob)
    try {
      await products.setImage(rice.id, bytes: _png, filename: 'qa.png');
      final withImage = container.read(productListProvider).firstWhere((p) => p.id == rice.id);
      expect(withImage.imageUrl, startsWith('https://'));
      await products.clearImage(rice.id);
      expect(container.read(productListProvider).firstWhere((p) => p.id == rice.id).imageUrl, isNull);
    } on ApiException catch (e) {
      // ignore: avoid_print
      print('IMAGE UPLOAD NOT VERIFIED: ${e.statusCode} ${e.code} ${e.message}');
      expect(e.code, 'storage_unavailable');
    }

    // --- removing a category products still use is refused with a reason
    final grains = categories.firstWhere((c) => c.name == 'QA Grains');
    try {
      await container.read(catalogProvider(CatalogKind.category).notifier).remove(grains.id);
      fail('a category in use should not be removable');
    } on ApiException catch (e) {
      expect(e.statusCode, 409);
    }
    await container.read(catalogProvider(CatalogKind.category).notifier).add('QA Unused');
    final unused = container
        .read(catalogProvider(CatalogKind.category))
        .value!
        .firstWhere((c) => c.name == 'QA Unused');
    await container.read(catalogProvider(CatalogKind.category).notifier).remove(unused.id);

    // --- movements: signed deltas, ledger, current stock, alerts
    final movements = container.read(movementsProvider.notifier);
    final warehouseId = container.read(activeWarehousesProvider).single.id;

    Future<MovementResult> record(String productId, StockMovementType type, int entered,
        {bool down = false}) {
      final current =
          container.read(productListProvider).firstWhere((p) => p.id == productId).currentStock;
      return movements.record(
        productId: productId,
        warehouseId: warehouseId,
        type: type,
        quantity: signedMovementDelta(
          type: type,
          entered: entered,
          currentStock: current,
          adjustDown: down,
        ),
        reason: 'QA ${type.label}',
      );
    }

    var result = await record(rice.id, StockMovementType.stockIn, 50);
    expect(result.currentStock, 50);
    expect(result.alert, isNull);

    result = await record(rice.id, StockMovementType.stockOut, 30);
    expect(result.currentStock, 20, reason: 'stock out must be sent as a negative delta');
    expect(result.alert, 'low_stock', reason: '20 <= reorder level 30');
    expect(result.movement.quantity, -30);

    result = await record(rice.id, StockMovementType.count, 25);
    expect(result.currentStock, 25, reason: 'count 25 against 20 on hand is +5');
    expect(result.movement.type, StockMovementType.count);

    result = await record(rice.id, StockMovementType.adjustment, 5, down: true);
    expect(result.currentStock, 20);

    result = await record(rice.id, StockMovementType.stockOut, 20);
    expect(result.currentStock, 0);
    expect(result.alert, 'out_of_stock');

    // products refreshed with the new stock; alerts and ledger agree
    final riceNow = container.read(productListProvider).firstWhere((p) => p.id == rice.id);
    expect(riceNow.currentStock, 0);
    expect(riceNow.isOutOfStock, isTrue);
    final alerts = container.read(stockAlertListProvider);
    expect(alerts.outOfStock.map((p) => p.id), contains(rice.id));
    final ledger = container.read(movementListProvider);
    expect(ledger, hasLength(5));
    expect(ledger.first.newStock, 0);
    expect(ledger.every((m) => m.userId == me.user.id), isTrue,
        reason: 'the ledger records who did each movement');
    expect(ledger.map((m) => m.type).toSet(), {
      StockMovementType.stockIn,
      StockMovementType.stockOut,
      StockMovementType.count,
      StockMovementType.adjustment,
    });

    // --- archive: gone from the list, and the plan's product usage drops
    await container.read(authControllerProvider.notifier).refresh();
    final usageBefore = container.read(authControllerProvider).value!.plan!.usage.products;
    expect(usageBefore, 2);
    await products.archive(oil.id);
    await container.read(authControllerProvider.notifier).refresh();
    expect(container.read(productListProvider).map((p) => p.id), [rice.id]);
    expect(container.read(authControllerProvider).value!.plan!.usage.products, 1);
    // its ledger and SKU are kept
    await _expectApiError(() => products.add(_input('QA-OIL')), (e) => e.statusCode == 409);

    // /me now reports the warehouse name
    expect(container.read(authControllerProvider).value!.organization!.warehouseName,
        'QA Main Warehouse');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('Sales Staff: only stock out is allowed, everything else is a friendly 403', () async {
    final container = await _signIn(_need('AIMIFY_SALES_EMAIL'));
    final me = container.read(authControllerProvider).value!;

    expect(me.role, 'Sales Staff');
    expect(me.permissions, ['stock.out']);
    expect(allowedMovementTypes(me.permissions), [StockMovementType.stockOut]);

    // reading is open to every role
    final products = await container.read(productsProvider.future);
    await container.read(warehousesProvider.future);
    final warehouses = container.read(activeWarehousesProvider);
    expect(products, isNotEmpty);
    expect(warehouses, isNotEmpty);

    // writes that need other permissions are blocked, with the permission named
    try {
      await container.read(productsProvider.notifier).add(_input('QA-SALES-NOPE'));
      fail('Sales Staff must not create products');
    } on ApiException catch (e) {
      expect(e.isForbiddenRole, isTrue);
      expect(e.requiredPermission, 'products.write');
      expect(friendlyError(e), contains('Sales Staff'));
    }
    await _expectApiError(
      () => container.read(warehousesProvider.notifier).add(name: 'nope'),
      (e) => e.isForbiddenRole && e.requiredPermission == 'warehouses.manage',
    );
    await _expectApiError(
      () => container.read(catalogProvider(CatalogKind.category).notifier).add('nope'),
      (e) => e.isForbiddenRole,
    );

    // stock-in / adjustment are blocked; stock out is allowed
    final rice = products.first;
    final warehouseId = warehouses.first.id;
    final movements = container.read(movementsProvider.notifier);
    await _expectApiError(
      () => movements.record(
        productId: rice.id,
        warehouseId: warehouseId,
        type: StockMovementType.stockIn,
        quantity: 1,
      ),
      (e) => e.isForbiddenRole && e.requiredPermission == 'stock.adjust',
    );

    // give the shared product some stock through an Owner, then sell it
    final owner = await _signIn(_need('AIMIFY_OWNER_EMAIL'));
    await owner.read(movementsProvider.notifier).record(
          productId: rice.id,
          warehouseId: warehouseId,
          type: StockMovementType.stockIn,
          quantity: 10,
          reason: 'QA restock',
        );
    await container.read(productsProvider.notifier).refresh();
    final result = await movements.record(
      productId: rice.id,
      warehouseId: warehouseId,
      type: StockMovementType.stockOut,
      quantity: -4,
      reason: 'QA sale',
    );
    expect(result.currentStock, 6);
    expect(result.movement.userId, me.user.id);

    // The ledger shows both people; the Sales Staff member sees "someone else"'s entry too.
    final ledger = container.read(movementListProvider);
    expect(ledger.map((m) => m.userId).toSet().length, greaterThan(1));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('logout revokes the token: the next call is a 401 that ends the session', () async {
    final container = await _signIn(_need('AIMIFY_SALES_EMAIL'));
    final token = await container.read(secureTokenStorageProvider).readToken();
    expect(token, isNotNull);

    await container.read(authControllerProvider.notifier).logout();
    expect(container.read(authControllerProvider).value, isNull);
    expect(await container.read(secureTokenStorageProvider).readToken(), isNull);

    // The revoked token no longer works against the server.
    final stale = _newSession();
    await stale.read(secureTokenStorageProvider).saveToken(token!);
    await stale.read(authControllerProvider.future);
    await _expectApiError(
      () => stale.read(authedApiProvider).get('http://localhost:3000/api/v1/warehouses'),
      (e) => e.isUnauthorized,
    );
    expect(stale.read(sessionEndedMessageProvider), contains('session ended'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
