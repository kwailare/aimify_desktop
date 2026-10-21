// LIVE end-to-end check of the guided setup's data layer against a running
// aimify-web (`npm run dev` on http://localhost:3000): `/me`'s
// setupCompletedAt, the team overview and in-app invitations, opening stock
// as a stock-in with the "Opening stock" reason, and finishing setup. Same
// repositories and notifiers the wizard uses, no fakes.
//
// Skipped unless AIMIFY_LIVE=1, because it writes to the backend's database
// and sends invitation emails (use Resend's delivered@resend.dev address so
// nobody receives them). Use a throwaway trial organization that hasn't
// finished setup, with one warehouse and no products:
//
//   AIMIFY_LIVE=1
//   AIMIFY_PASSWORD=...          shared by both accounts
//   AIMIFY_OWNER_EMAIL=...       Owner, email confirmed
//   AIMIFY_SALES_EMAIL=...       Sales Staff in the same org
//   AIMIFY_INVITE_EMAIL=...      e.g. delivered+wizard@resend.dev
//
//   flutter test test/live/live_setup_wizard_test.dart

import 'dart:io';

import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/setup_wizard/data/setup_wizard_state.dart';
import 'package:aimify_desktop/features/team/data/team_repository.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_token_storage.dart';

final _env = Platform.environment;
final _live = _env['AIMIFY_LIVE'] == '1';
String _need(String name) => _env[name] ?? (throw StateError('Set $name'));

Future<ProviderContainer> _signIn(String email) async {
  final container = ProviderContainer(
    overrides: [
      secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
      localStoreProvider.overrideWithValue(MemoryLocalStore()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authControllerProvider.future);
  await container.read(authControllerProvider.notifier).login(
        email: email,
        password: _need('AIMIFY_PASSWORD'),
      );
  return container;
}

void main() {
  test(
    'guided setup against the real backend',
    () async {
      final owner = await _signIn(_need('AIMIFY_OWNER_EMAIL'));
      final sales = await _signIn(_need('AIMIFY_SALES_EMAIL'));

      final ownerMe = owner.read(authControllerProvider).value!;
      expect(ownerMe.organization!.setupCompletedAt, isNull);
      expect(ownerMe.hasPermission('setup.complete'), isTrue);
      expect(ownerMe.hasPermission('team.manage'), isTrue);
      expect(shouldAutoOpenSetup(ownerMe, dismissed: false), isTrue);

      final salesMe = sales.read(authControllerProvider).value!;
      expect(salesMe.hasPermission('setup.complete'), isFalse);
      expect(shouldAutoOpenSetup(salesMe, dismissed: false), isFalse);

      // Team step.
      final team = await owner.read(teamProvider.future);
      expect(team.members.map((m) => m.role), containsAll(['Owner', 'Sales Staff']));
      expect(team.assignableRoles, hasLength(6));

      final sent = await owner.read(teamProvider.notifier).invite(
            email: _need('AIMIFY_INVITE_EMAIL'),
            role: 'Inventory Staff',
          );
      expect(sent, isTrue);
      final afterInvite = owner.read(teamProvider).value!;
      expect(afterInvite.invitations.map((i) => i.email), contains(_need('AIMIFY_INVITE_EMAIL').toLowerCase()));
      expect(afterInvite.seatsUsed, team.seatsUsed + 1);

      try {
        await owner.read(teamProvider.notifier).invite(email: _need('AIMIFY_SALES_EMAIL'), role: 'Sales Staff');
        fail('inviting an existing member should be refused');
      } on ApiException catch (e) {
        expect(e.code, 'already_in_organization');
        expect(e.statusCode, 409);
      }

      try {
        await sales.read(teamRepositoryProvider).overview();
        fail('Sales Staff should not read the team');
      } on ApiException catch (e) {
        expect(e.isForbiddenRole, isTrue);
      }

      // Products and opening stock steps.
      final warehouse = (await owner.read(warehousesProvider.future)).firstWhere((w) => w.isActive);
      await owner.read(productsProvider.future);
      final created = await owner.read(productsProvider.notifier).add(
            const ProductInput(
              sku: 'WIZ-LIVE-1',
              name: 'Wizard live rice',
              unit: 'bag',
              purchasePrice: 1000,
              sellingPrice: 1200,
              minStock: 2,
            ),
          );
      expect(created.queued, isFalse);
      final product = owner.read(productListProvider).firstWhere((p) => p.sku == 'WIZ-LIVE-1');

      await owner.read(movementsProvider.future);
      final recorded = await owner.read(movementsProvider.notifier).record(
            productId: product.id,
            warehouseId: warehouse.id,
            type: StockMovementType.stockIn,
            quantity: 25,
            reason: openingStockReason,
          );
      expect(recorded.queued, isFalse);
      final ledger = await owner.read(inventoryRepositoryProvider).movementsFresh();
      final opening = ledger.firstWhere((m) => m.productId == product.id);
      expect(opening.type, StockMovementType.stockIn);
      expect(opening.quantity, 25);
      expect(opening.reason, 'Opening stock');
      expect(owner.read(productListProvider).firstWhere((p) => p.id == product.id).currentStock, 25);

      // Finish: Sales Staff can't, the Owner can, and everyone sees it.
      try {
        await sales.read(setupRepositoryProvider).complete();
        fail('Sales Staff should not finish setup');
      } on ApiException catch (e) {
        expect(e.isForbiddenRole, isTrue);
      }

      await owner.read(setupRepositoryProvider).complete();
      await owner.read(authControllerProvider.notifier).refresh();
      final finished = owner.read(authControllerProvider).value!;
      expect(finished.organization!.isSetupComplete, isTrue);
      expect(shouldAutoOpenSetup(finished, dismissed: false), isFalse);

      await sales.read(authControllerProvider.notifier).refresh();
      expect(
        sales.read(authControllerProvider).value!.organization!.setupCompletedAt,
        finished.organization!.setupCompletedAt,
      );
    },
    skip: _live ? false : 'Set AIMIFY_LIVE=1 to run against a real backend',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
