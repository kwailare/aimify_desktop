// Customers, suppliers and the credit ledger: role-driven screens, and the
// hybrid behaviour — a customer or payment recorded offline is saved, shown
// at once, and sent exactly once when the connection is good.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/parties/presentation/parties_screen.dart';
import 'package:aimify_desktop/features/parties/presentation/party_history_dialog.dart';
import 'package:aimify_desktop/features/sync/sync_engine.dart';
import 'package:aimify_desktop/shared/offline/connection.dart';
import 'package:aimify_desktop/shared/offline/outbox.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:aimify_desktop/shared/services/secure_token_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';
import 'fakes/fake_token_storage.dart';

class _RoleAuth extends AuthController {
  _RoleAuth(this.role, this.permissions);

  final String role;
  final List<String> permissions;

  @override
  Future<MeResponse?> build() async => _me();

  MeResponse _me() => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Ada', email: 'ada@company.com'),
        organization: const Organization(
          id: 'o1',
          name: 'Obi Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main',
          subscriptionStatus: 'trial',
        ),
        role: role,
        permissions: permissions,
      );

  @override
  Future<void> refresh() async {}

  /// Re-publishes the same session, as happens after every `/me` refresh.
  void republish() => state = AsyncData(_me());
}

const _all = [
  'customers.read',
  'customers.write',
  'suppliers.read',
  'suppliers.write',
  'credit.record',
];

class _Rig {
  _Rig({List<String> permissions = _all, String role = 'Owner', FakePartiesRepository? repo})
      : parties = repo ??
            FakePartiesRepository(
              customers: [fixtureParty('c1', name: 'Blessing Store', balance: 4000, creditLimit: 5000)],
              suppliers: [fixtureParty('s1', type: PartyType.supplier, name: 'Golden Grains', balance: 900)],
            ) {
    container = ProviderContainer(
      overrides: [
        secureTokenStorageProvider.overrideWithValue(FakeTokenStorage()),
        authControllerProvider.overrideWith(() => _RoleAuth(role, permissions)),
        ...fakeDataOverrides(parties: parties),
      ],
    );
  }

  final FakePartiesRepository parties;
  late final ProviderContainer container;

  ConnectionNotifier get connection => container.read(connectionProvider.notifier);
  SyncEngine get sync => container.read(syncEngineProvider.notifier);
  List<OutboxOp> get ops => container.read(outboxOpsProvider);

  List<Party> customers() => container.read(partyListProvider(PartyType.customer));
  List<Party> suppliers() => container.read(partyListProvider(PartyType.supplier));

  Future<void> ready() async {
    await container.read(authControllerProvider.future);
    await container.read(outboxProvider.future);
    await container.read(partiesProvider(PartyType.customer).future);
    await container.read(partiesProvider(PartyType.supplier).future);
  }

  Future<SubmitResult<({CreditEntry entry, double balanceOwed})>> pay(
    double amount, {
    String partyId = 'c1',
    PartyType type = PartyType.customer,
    CreditKind kind = CreditKind.payment,
  }) =>
      container.read(creditServiceProvider).record(
            partyType: type,
            partyId: partyId,
            kind: kind,
            amount: amount,
            note: 'test',
          );

  void dispose() => container.dispose();
}

void main() {
  group('the credit ledger while online', () {
    test('a payment is sent at once with a clientRef, and lowers the balance', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      final result = await rig.pay(1500);

      expect(result.queued, isFalse);
      expect(result.value!.balanceOwed, 2500);
      expect(rig.parties.recorded.single.amount, 1500);
      expect(rig.parties.recorded.single.clientRef, isNotNull);
      expect(rig.customers().single.balanceOwed, 2500);
      expect(rig.ops, isEmpty);
    });

    test('a server refusal (overpayment) is shown, not queued', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      await expectLater(
        rig.pay(999999),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'overpayment')),
      );
      expect(rig.ops, isEmpty);
      expect(rig.customers().single.balanceOwed, 4000);
    });

    test('a charge raises the balance and an adjustment can lower it', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      await rig.pay(1000, kind: CreditKind.charge);
      expect(rig.customers().single.balanceOwed, 5000);
      expect(rig.customers().single.isAtCreditLimit, isTrue);

      await rig.pay(-300, kind: CreditKind.adjustment);
      expect(rig.customers().single.balanceOwed, 4700);
    });

    test('a write straight after the session is refreshed still works', () async {
      // Regression: after `/me` refreshes (which happens after every plan-limit
      // or permission change) the parties provider is briefly out of date, and
      // reading the role with `ref.watch` inside a method threw.
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      // Hold the notifier first: the session is refreshed while a write is in
      // flight, so the provider is already out of date when the write finishes.
      final notifier = rig.container.read(partiesProvider(PartyType.customer).notifier);
      (rig.container.read(authControllerProvider.notifier) as _RoleAuth).republish();
      final result = await notifier.add(const PartyInput(type: PartyType.customer, name: 'Right after refresh'));

      expect(result.queued, isFalse);
      expect(rig.parties.created.single.name, 'Right after refresh');
    });

    test('suppliers and customers keep separate balances', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      await rig.pay(400, partyId: 's1', type: PartyType.supplier);

      expect(rig.suppliers().single.balanceOwed, 500);
      expect(rig.customers().single.balanceOwed, 4000);
    });
  });

  group('offline', () {
    test('a payment made offline is saved, shown at once, and not sent', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);

      final result = await rig.pay(1500);

      expect(result.queued, isTrue);
      expect(rig.parties.recorded, isEmpty);
      expect(rig.ops.single.kind, OpKind.creditEntry);
      expect(rig.customers().single.balanceOwed, 2500, reason: 'shown at once');
      // Only that customer is affected.
      expect(rig.suppliers().single.balanceOwed, 900);

      final ledger = rig.container.read(creditLedgerProvider((type: PartyType.customer, id: 'c1')));
      expect(ledger.first.isPending, isTrue);
      expect(ledger.first.amount, -1500);
    });

    test('when the connection is good it is sent once, using the op id as clientRef', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      await rig.pay(1500);
      final opId = rig.ops.single.id;

      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.parties.recorded, hasLength(1));
      expect(rig.parties.recorded.single.clientRef, opId);
      expect(rig.ops, isEmpty);
      expect(rig.customers().single.balanceOwed, 2500, reason: 'server balance now includes it');
    });

    test('an entry sent twice (answer lost) is recorded once, thanks to clientRef', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();

      // The send lands but the answer is lost.
      rig.parties.recordError = const NetworkException();
      final result = await rig.pay(1500);
      expect(result.queued, isTrue);
      expect(rig.parties.recorded, hasLength(1));

      // Simulate the server having applied it, then the retry.
      rig.parties.recordError = null;
      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();
      await rig.sync.flush();

      expect(rig.parties.recorded.map((r) => r.clientRef).toSet(), hasLength(1),
          reason: 'every send carries the same clientRef');
      expect(rig.parties.ledger, hasLength(1), reason: 'the server recorded it once');
      expect(rig.customers().single.balanceOwed, 2500);
    });

    test('a payment the server refuses stays visible with the reason', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      // Passes the app's own check offline (balance 4000), but by the time it
      // syncs someone else has already been paid: the server says no.
      await rig.pay(3000);
      rig.parties.customers = [fixtureParty('c1', name: 'Blessing Store', balance: 100)];

      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.ops, hasLength(1));
      expect(rig.ops.single.failed, isTrue);
      expect(rig.ops.single.error, contains('more than the balance'));
      // A refused entry no longer changes the balance shown: once the list is
      // re-read, it is exactly what the server holds.
      await rig.container.read(partiesProvider(PartyType.customer).notifier).refresh();
      expect(rig.customers().single.balanceOwed, 100);
    });

    test('a customer added offline appears at once and syncs; entries follow it to its real id', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);

      final created = await rig.container
          .read(partiesProvider(PartyType.customer).notifier)
          .add(const PartyInput(type: PartyType.customer, name: 'Walk-in Traders', creditLimit: 2000));
      expect(created.queued, isTrue);

      final local = rig.customers().firstWhere((c) => c.name == 'Walk-in Traders');
      expect(local.isPending, isTrue);
      expect(local.id, startsWith('local:'));

      // A credit sale to the customer, still offline.
      await rig.pay(750, partyId: local.id, kind: CreditKind.charge);
      expect(rig.customers().firstWhere((c) => c.id == local.id).balanceOwed, 750);

      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.parties.created.single.name, 'Walk-in Traders');
      expect(rig.parties.recorded.single.partyId, 'srv1', reason: 'the entry was re-pointed at the real id');
      expect(rig.ops, isEmpty);
    });

    test('editing a party that only exists locally folds into its pending create', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      final notifier = rig.container.read(partiesProvider(PartyType.supplier).notifier);

      await notifier.add(const PartyInput(type: PartyType.supplier, name: 'First'));
      final local = rig.suppliers().firstWhere((s) => s.name == 'First');
      await notifier.edit(local.id, const PartyInput(type: PartyType.supplier, name: 'Second'));

      expect(rig.ops, hasLength(1));
      expect(rig.suppliers().any((s) => s.name == 'Second'), isTrue);
    });

    test('archiving a party that never reached the server forgets it and its entries', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      final notifier = rig.container.read(partiesProvider(PartyType.customer).notifier);

      await notifier.add(const PartyInput(type: PartyType.customer, name: 'Temp'));
      final local = rig.customers().firstWhere((c) => c.name == 'Temp');
      await rig.pay(10, partyId: local.id, kind: CreditKind.charge);
      expect(rig.ops, hasLength(2));

      await notifier.archive(local.id);

      expect(rig.ops, isEmpty);
      expect(rig.customers().any((c) => c.name == 'Temp'), isFalse);
    });

    test('an entry on a party whose creation was refused is refused too, not lost silently', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      rig.connection.set(ConnectionQuality.offline);
      final notifier = rig.container.read(partiesProvider(PartyType.customer).notifier);
      await notifier.add(const PartyInput(type: PartyType.customer, name: 'Rejected'));
      final local = rig.customers().firstWhere((c) => c.name == 'Rejected');
      await rig.pay(10, partyId: local.id, kind: CreditKind.charge);

      rig.parties.createError = ApiException(403, 'Not allowed.', code: 'forbidden_role');
      rig.connection.set(ConnectionQuality.good);
      await rig.sync.flush();

      expect(rig.ops, hasLength(2));
      expect(rig.ops.every((o) => o.failed), isTrue);
      expect(rig.ops.last.error, contains('could not be created'));
      expect(rig.parties.recorded, isEmpty);
    });
  });

  group('roles', () {
    test('a role without customers.read never calls the customers API', () async {
      final rig = _Rig(role: 'Warehouse Manager', permissions: ['suppliers.read', 'suppliers.write']);
      addTearDown(rig.dispose);
      await rig.ready();

      expect(rig.customers(), isEmpty);
      expect(rig.suppliers(), hasLength(1));
    });

    testWidgets('Sales Staff see customers but are told suppliers are not for them', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rig = _Rig(role: 'Sales Staff', permissions: ['customers.read', 'customers.write', 'stock.out']);
      addTearDown(rig.dispose);

      Future<void> show(PartyType type) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: rig.container,
            child: MaterialApp(theme: AppTheme.light(), home: PartiesScreen(type: type)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await show(PartyType.customer);
      expect(find.text('Blessing Store'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Add customer')).onPressed,
        isNotNull,
      );

      await show(PartyType.supplier);
      expect(find.textContaining("can't view suppliers"), findsOneWidget);
      expect(find.text('Golden Grains'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Accountant reads but cannot add or edit, yet can record a payment', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rig = _Rig(
        role: 'Accountant / Finance',
        permissions: ['customers.read', 'suppliers.read', 'credit.record'],
      );
      addTearDown(rig.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.container,
          child: MaterialApp(theme: AppTheme.light(), home: const PartiesScreen(type: PartyType.customer)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Add customer')).onPressed,
        isNull,
      );

      // The ledger opens, and the accountant can record a payment from it.
      await tester.tap(find.text('Blessing Store'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PartyHistoryDialog), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Record payment')).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the history dialog', () {
    testWidgets('lists the ledger, marking entries still waiting to sync', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.ready();
      await rig.pay(1000, kind: CreditKind.charge); // recorded on the server
      rig.connection.set(ConnectionQuality.offline);
      await rig.pay(500); // saved offline

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rig.container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => PartyHistoryDialog(party: rig.customers().single),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Pending sync'), findsOneWidget);
      expect(find.textContaining('Charge'), findsOneWidget);
      expect(find.textContaining('Payment'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
