// Guided setup wizard (feature checklist step 2): auto-opening for Owners and
// Administrators of an organization that hasn't finished setup, "Finish
// later", step navigation and memory, opening stock as stock-in movements
// with the "Opening stock" reason, in-app team invitations, and finishing.
// Buttons that launch a browser (billing, website links) are never tapped:
// that needs a platform channel the test environment doesn't have.

import 'package:aimify_desktop/app.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/setup_wizard/data/setup_wizard_state.dart';
import 'package:aimify_desktop/features/setup_wizard/presentation/setup_wizard_screen.dart';
import 'package:aimify_desktop/features/team/data/team_repository.dart';
import 'package:aimify_desktop/features/team/domain/team.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_permissions.dart';
import 'fakes/fake_repositories.dart';
import 'fakes/fake_token_storage.dart';

const _adminPermissions = [
  'products.write', 'products.archive', 'catalog.write', 'warehouses.manage',
  'stock.out', 'stock.adjust', 'customers.read', 'customers.write',
  'suppliers.read', 'suppliers.write', 'credit.record', 'team.manage', 'setup.complete',
];

MeResponse _me({
  String role = 'Owner',
  List<String> permissions = _adminPermissions,
  String status = 'trial',
  DateTime? setupCompletedAt,
}) =>
    MeResponse(
      user: const AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
      organization: Organization(
        id: 'o1',
        name: 'Obi Distribution Ltd',
        industry: 'Wholesale',
        currency: 'NGN',
        warehouseName: 'Main Warehouse',
        subscriptionStatus: status,
        trialEndsAt: DateTime.now().add(const Duration(days: 10)),
        setupCompletedAt: setupCompletedAt,
      ),
      role: role,
      permissions: asGranted(permissions),
      plan: const Plan(
        name: 'Starter',
        limits: PlanLimits(users: 5, warehouses: 1),
        usage: PlanUsage(users: 1, warehouses: 1, products: 2),
      ),
    );

/// Signed-in session whose `/me` can change: [complete] flips
/// `setupCompletedAt`, the way the server does after `POST /organization/setup`.
class _Auth extends AuthController {
  _Auth(this.current);

  MeResponse current;

  @override
  Future<MeResponse?> build() async => current;

  @override
  Future<void> refresh() async => state = AsyncData(current);
}

class _FakeSetupRepository implements SetupRepository {
  _FakeSetupRepository(this.auth);

  final _Auth Function() auth;
  int calls = 0;
  Object? error;

  @override
  Future<void> complete() async {
    calls++;
    if (error != null) throw error!;
    final me = auth().current;
    auth().current = _me(
      role: me.role!,
      permissions: asGranted(me.permissions),
      setupCompletedAt: DateTime(2026, 10, 21),
    );
  }
}

class _FakeTeamRepository implements TeamRepository {
  _FakeTeamRepository({this.seatLimit = 5});

  final int? seatLimit;
  final List<PendingInvitation> invitations = [];
  Object? inviteError;
  bool emailSent = true;

  @override
  Future<TeamOverview> overview() async => TeamOverview(
        members: const [TeamMember(id: 'u1', name: 'Ada Obi', email: 'ada@company.com', role: 'Owner')],
        invitations: List.of(invitations),
        assignableRoles: const [
          'Owner', 'Administrator', 'Warehouse Manager', 'Sales Staff', 'Inventory Staff', 'Accountant / Finance',
        ],
        seatsUsed: 1 + invitations.length,
        seatLimit: seatLimit,
      );

  @override
  Future<bool> invite({required String email, required String role}) async {
    if (inviteError != null) throw inviteError!;
    invitations.add(PendingInvitation(id: 'i${invitations.length}', email: email, role: role));
    return emailSent;
  }
}

/// Records the warehouse and reason too, which the shared fake drops.
class _RecordingInventory extends FakeInventoryRepository {
  final List<({String productId, String warehouseId, int quantity, String? reason, StockMovementType type})>
      calls = [];

  @override
  Future<MovementResult> record({
    required String productId,
    required String warehouseId,
    required StockMovementType type,
    required int quantity,
    String? reason,
  }) {
    calls.add((productId: productId, warehouseId: warehouseId, quantity: quantity, reason: reason, type: type));
    return super.record(
      productId: productId,
      warehouseId: warehouseId,
      type: type,
      quantity: quantity,
      reason: reason,
    );
  }
}

class _Harness {
  _Harness({MeResponse? me, int? seatLimit = 5})
      : auth = _Auth(me ?? _me()),
        team = _FakeTeamRepository(seatLimit: seatLimit) {
    setup = _FakeSetupRepository(() => auth);
  }

  final _Auth auth;
  final _FakeTeamRepository team;
  late final _FakeSetupRepository setup;
  final inventory = _RecordingInventory();
  final store = MemoryLocalStore();

  List<Override> get overrides => [
        secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        authControllerProvider.overrideWith(() => auth),
        teamRepositoryProvider.overrideWithValue(team),
        setupRepositoryProvider.overrideWithValue(setup),
        ...fakeDataOverrides(inventory: inventory, store: store),
      ];
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _bootApp(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const AimifyApp()));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  group('parsing and rules', () {
    test('setupCompletedAt parses from /me, null when missing', () {
      final base = {
        'id': 'o1', 'name': 'X', 'industry': 'Y', 'currency': 'NGN', 'subscriptionStatus': 'trial',
      };
      expect(Organization.fromJson(base).setupCompletedAt, isNull);
      expect(Organization.fromJson(base).isSetupComplete, isFalse);
      final done = Organization.fromJson({...base, 'setupCompletedAt': '2026-10-21T09:12:44.120Z'});
      expect(done.setupCompletedAt, DateTime.utc(2026, 10, 21, 9, 12, 44, 120));
      expect(done.isSetupComplete, isTrue);
    });

    test('auto-opens only for setup.complete holders of an unlocked, unfinished org', () {
      expect(shouldAutoOpenSetup(_me(), dismissed: false), isTrue);
      expect(shouldAutoOpenSetup(_me(role: 'Administrator'), dismissed: false), isTrue);
      expect(shouldAutoOpenSetup(_me(), dismissed: true), isFalse, reason: 'Finish later');
      expect(shouldAutoOpenSetup(_me(setupCompletedAt: DateTime(2026)), dismissed: false), isFalse);
      expect(
        shouldAutoOpenSetup(_me(role: 'Sales Staff', permissions: asGranted(['stock.out'])), dismissed: false),
        isFalse,
      );
      expect(shouldAutoOpenSetup(_me(status: 'expired'), dismissed: false), isFalse);
      expect(shouldAutoOpenSetup(null, dismissed: false), isFalse);
    });
  });

  group('auto-open', () {
    testWidgets('an Owner of an unfinished org lands in the wizard', (tester) async {
      await _bootApp(tester, _Harness());
      expect(find.byType(SetupWizardScreen), findsOneWidget);
      expect(find.text('Set up Obi Distribution Ltd'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a finished org goes straight to the dashboard', (tester) async {
      await _bootApp(tester, _Harness(me: _me(setupCompletedAt: DateTime(2026, 10, 1))));
      expect(find.byType(SetupWizardScreen), findsNothing);
      expect(find.byKey(const Key('open-guided-setup')), findsNothing);
    });

    testWidgets('Sales Staff never sees it, even on an unfinished org', (tester) async {
      await _bootApp(
        tester,
        _Harness(me: _me(role: 'Sales Staff', permissions: asGranted(['stock.out', 'customers.read']))),
      );
      expect(find.byType(SetupWizardScreen), findsNothing);
      expect(find.byKey(const Key('open-guided-setup')), findsNothing);
    });

    testWidgets('Finish later goes to the dashboard, and the card reopens it', (tester) async {
      await _bootApp(tester, _Harness());
      await _tap(tester, find.byKey(const Key('setup-finish-later')));
      expect(find.byType(SetupWizardScreen), findsNothing);

      final reopen = find.byKey(const Key('open-guided-setup'));
      expect(reopen, findsOneWidget);
      await _tap(tester, reopen);
      expect(find.byType(SetupWizardScreen), findsOneWidget);
    });
  });

  group('steps', () {
    testWidgets('Next and Back walk the steps, and the step is remembered', (tester) async {
      final h = _Harness();
      await _bootApp(tester, h);
      expect(find.text('Step 1 of 5'), findsOneWidget);
      expect(find.text('Main Warehouse'), findsWidgets);

      await _tap(tester, find.byKey(const Key('setup-next')));
      expect(find.text('Step 2 of 5'), findsOneWidget);
      expect(find.byKey(const Key('setup-add-product')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('setup-next')));
      expect(find.text('Step 3 of 5'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('setup-back')));
      expect(find.text('Step 2 of 5'), findsOneWidget);

      final saved = await h.store.read('u_u1_setup_wizard_o1');
      expect(saved, contains('"step":1'));
    });

    testWidgets('reopening continues from the remembered step', (tester) async {
      final h = _Harness();
      await h.store.write('u_u1_setup_wizard_o1', '{"step":3}');
      await _bootApp(tester, h);
      expect(find.text('Step 4 of 5'), findsOneWidget);
      expect(find.byKey(const Key('setup-invite-email')), findsOneWidget);
    });

    testWidgets('the step rail jumps straight to a step', (tester) async {
      await _bootApp(tester, _Harness());
      await _tap(tester, find.byKey(const Key('setup-rail-subscription')));
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('Starter'), findsOneWidget);
      expect(find.text('Free trial'), findsOneWidget);
      expect(find.text('1 of 5'), findsOneWidget, reason: 'team members against the plan');
    });
  });

  group('opening stock', () {
    testWidgets('records a stock-in with the Opening stock reason for each filled-in product', (tester) async {
      final h = _Harness();
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-openingStock')));

      await tester.enterText(find.byKey(const Key('setup-qty-1')), '40');
      await tester.enterText(find.byKey(const Key('setup-qty-2')), '');
      await _tap(tester, find.byKey(const Key('setup-save-opening-stock')));

      expect(h.inventory.calls, hasLength(1));
      final call = h.inventory.calls.single;
      expect(call.productId, '1');
      expect(call.warehouseId, 'w1');
      expect(call.quantity, 40);
      expect(call.type, StockMovementType.stockIn);
      expect(call.reason, 'Opening stock');
      expect(find.text('Opening stock recorded for 1 product.'), findsOneWidget);
    });

    testWidgets('saving with nothing filled in asks for a quantity and sends nothing', (tester) async {
      final h = _Harness();
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-openingStock')));
      await _tap(tester, find.byKey(const Key('setup-save-opening-stock')));
      expect(h.inventory.calls, isEmpty);
      expect(find.text('Enter a quantity for at least one product.'), findsOneWidget);
    });

    testWidgets('a refused movement is reported with the product name', (tester) async {
      final h = _Harness();
      h.inventory.recordError = ApiException(403, "Your role isn't allowed to do this.", code: 'forbidden_role');
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-openingStock')));
      await tester.enterText(find.byKey(const Key('setup-qty-1')), '5');
      await _tap(tester, find.byKey(const Key('setup-save-opening-stock')));
      expect(find.textContaining('Product 1:'), findsOneWidget);
    });
  });

  group('team', () {
    testWidgets('invites someone and lists the pending invitation', (tester) async {
      final h = _Harness();
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-team')));

      await tester.enterText(find.byKey(const Key('setup-invite-email')), 'tunde@obi.example');
      await _tap(tester, find.byKey(const Key('setup-send-invite')));

      expect(h.team.invitations.single.email, 'tunde@obi.example');
      expect(h.team.invitations.single.role, 'Sales Staff', reason: 'default role');
      expect(find.textContaining('Invitation sent to tunde@obi.example'), findsOneWidget);
      expect(find.text('Invitation pending'), findsOneWidget);
      expect(find.text('2 of 5 seats used'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown and nothing is added', (tester) async {
      final h = _Harness();
      h.team.inviteError = ApiException(
        409,
        "That person already belongs to an organization on Aimify, so they can't be invited.",
        code: 'already_in_organization',
      );
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-team')));
      await tester.enterText(find.byKey(const Key('setup-invite-email')), 'taken@obi.example');
      await _tap(tester, find.byKey(const Key('setup-send-invite')));
      expect(h.team.invitations, isEmpty);
      expect(find.textContaining('already belongs to an organization'), findsOneWidget);
    });

    testWidgets('an email that could not be sent says to resend from the website', (tester) async {
      final h = _Harness()..team.emailSent = false;
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-team')));
      await tester.enterText(find.byKey(const Key('setup-invite-email')), 'tunde@obi.example');
      await _tap(tester, find.byKey(const Key('setup-send-invite')));
      expect(find.textContaining('could not be sent'), findsOneWidget);
    });

    testWidgets('a full plan disables inviting', (tester) async {
      final h = _Harness(seatLimit: 1);
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-team')));
      final button = tester.widget<ButtonStyleButton>(find.byKey(const Key('setup-send-invite')));
      expect(button.onPressed, isNull);
      expect(find.textContaining('no free seats'), findsOneWidget);
    });
  });

  testWidgets('every step lays out without overflow in a small window', (tester) async {
    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: _Harness().overrides, child: const AimifyApp()));
    await _settle(tester);

    for (final step in SetupStep.values) {
      await _tap(tester, find.byKey(Key('setup-rail-${step.name}')));
      expect(find.text('Step ${step.index + 1} of 5'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: step.name);
    }
  });

  group('finish', () {
    testWidgets('Finish setup marks the org complete and opens the dashboard', (tester) async {
      final h = _Harness();
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-subscription')));
      await _tap(tester, find.byKey(const Key('setup-finish')));

      expect(h.setup.calls, 1);
      expect(find.byType(SetupWizardScreen), findsNothing);
      expect(find.byKey(const Key('open-guided-setup')), findsNothing);
    });

    testWidgets('offline: Finish setup explains and stays in the wizard', (tester) async {
      final h = _Harness();
      h.setup.error = NetworkException('no network');
      await _bootApp(tester, h);
      await _tap(tester, find.byKey(const Key('setup-rail-subscription')));
      await _tap(tester, find.byKey(const Key('setup-finish')));

      expect(find.byType(SetupWizardScreen), findsOneWidget);
      expect(find.textContaining("You're offline"), findsOneWidget);
    });
  });
}
