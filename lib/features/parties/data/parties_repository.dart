import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/outbox.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sync/sync_engine.dart';
import '../domain/party.dart';
import 'party_overlay.dart';

/// REAL `/api/v1/customers`, `/api/v1/suppliers` and `/api/v1/credit-entries`.
///
/// Customers and suppliers are archived, never deleted, so their credit
/// history stays intact. A party's balance is the sum of its credit ledger,
/// which the server keeps; the app only ever adds entries to it.
class PartiesRepository {
  PartiesRepository(this._api);

  final AuthedApi _api;

  String _listUrl(PartyType type) =>
      type == PartyType.customer ? ApiConstants.customers : ApiConstants.suppliers;

  String _itemUrl(PartyType type, String id) =>
      type == PartyType.customer ? ApiConstants.customer(id) : ApiConstants.supplier(id);

  /// Falls back to the last saved copy when the network can't answer.
  Future<List<Party>> list(PartyType type) => _read(type, cacheKey: type.plural);

  /// Straight from the server — never the saved copy. Used to check whether an
  /// interrupted create actually landed.
  Future<List<Party>> listFresh(PartyType type) => _read(type);

  Future<List<Party>> _read(PartyType type, {String? cacheKey}) async {
    final json = await _api.get(_listUrl(type), cacheKey: cacheKey);
    return [
      for (final row in (json[type.plural] as List<dynamic>? ?? const []))
        Party.fromJson(type, row as Map<String, dynamic>),
    ];
  }

  Future<Party> create(PartyInput input) async {
    final json = await _api.post(_listUrl(input.type), input.toJson());
    return Party.fromJson(input.type, json[input.type.apiValue] as Map<String, dynamic>);
  }

  Future<Party> update(String id, PartyInput input) async {
    final json = await _api.patch(_itemUrl(input.type, id), input.toJson());
    return Party.fromJson(input.type, json[input.type.apiValue] as Map<String, dynamic>);
  }

  Future<Party> archive(PartyType type, String id) async {
    final json = await _api.delete(_itemUrl(type, id));
    return Party.fromJson(type, json[type.apiValue] as Map<String, dynamic>);
  }

  /// One party's ledger, newest first. Falls back to the saved copy offline.
  Future<List<CreditEntry>> entries(PartyType type, String partyId) async {
    final json = await _api.get(
      '${ApiConstants.creditEntries}?partyType=${type.apiValue}&partyId=$partyId&limit=200',
      cacheKey: 'credit_$partyId',
    );
    return [
      for (final row in (json['entries'] as List<dynamic>? ?? const []))
        CreditEntry.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// Adds one entry to a party's ledger. [amount] is positive for a charge or
  /// payment (the server applies the sign) and signed for an adjustment.
  ///
  /// [clientRef] makes a retry harmless: sending the same ref again returns the
  /// entry that already exists instead of adding a second — which is how an
  /// entry saved offline can be sent again safely.
  Future<({CreditEntry entry, double balanceOwed})> recordEntry({
    required PartyType partyType,
    required String partyId,
    required CreditKind kind,
    required double amount,
    String? note,
    String? clientRef,
  }) async {
    final json = await _api.post(ApiConstants.creditEntries, {
      'partyType': partyType.apiValue,
      'partyId': partyId,
      'kind': kind.apiValue,
      'amount': amount,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'clientRef': ?clientRef,
    });
    return (
      entry: CreditEntry.fromJson(json['entry'] as Map<String, dynamic>),
      balanceOwed: (json['balanceOwed'] as num?)?.toDouble() ?? 0,
    );
  }
}

final partiesRepositoryProvider = Provider<PartiesRepository>(
  (ref) => PartiesRepository(ref.watch(authedApiProvider)),
);

/// Whether the signed-in role may see this kind of party. Reading customers
/// and suppliers is gated (money records), unlike products.
///
/// A provider of its own (rather than reading the whole session inside the
/// notifier) so the notifier depends on a single true/false: it is rebuilt —
/// and its data re-fetched — only when the answer actually changes, not on
/// every `/me` refresh.
final canReadPartiesProvider = Provider.family<bool, PartyType>((ref, type) {
  final key = type == PartyType.customer ? Permissions.customersRead : Permissions.suppliersRead;
  return ref.watch(
    authControllerProvider.select((state) => state.valueOrNull?.hasPermission(key) ?? false),
  );
});

class PartiesNotifier extends FamilyAsyncNotifier<List<Party>, PartyType> {
  @override
  Future<List<Party>> build(PartyType arg) async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    // A role without read access never calls the API (it would only 403).
    if (!ref.watch(canReadPartiesProvider(arg))) return const [];
    return ref.watch(partiesRepositoryProvider).list(arg);
  }

  Future<void> refresh() async {
    if (!ref.read(canReadPartiesProvider(arg))) return;
    state = await AsyncValue.guard(() => ref.read(partiesRepositoryProvider).list(arg));
  }

  SyncEngine get _sync => ref.read(syncEngineProvider.notifier);

  /// Adds a customer or supplier — now if the connection is good, otherwise
  /// saved on this computer and synced later (it appears at once, marked
  /// pending).
  Future<SubmitResult<Party>> add(PartyInput input) async {
    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.partyCreate,
      payload: {'type': arg.apiValue, 'input': input.toJson()},
      createdAt: DateTime.now(),
    );
    final result = await _sync.submit(op, () => ref.read(partiesRepositoryProvider).create(input));
    if (!result.queued) await refresh();
    return result;
  }

  Future<SubmitResult<Party>> edit(String id, PartyInput input) async {
    final outbox = ref.read(outboxProvider.notifier);

    // A party that only exists locally: fold the edit into its pending create.
    if (id.startsWith('local:')) {
      final create = ref
          .read(outboxOpsProvider)
          .where((o) => o.kind == OpKind.partyCreate && o.localId == id)
          .firstOrNull;
      if (create != null) {
        await outbox.replace(
          OutboxOp(
            id: create.id,
            kind: create.kind,
            payload: {'type': arg.apiValue, 'input': input.toJson()},
            createdAt: create.createdAt,
            attempted: create.attempted,
            error: create.error,
          ),
        );
      }
      return const SubmitResult.queued();
    }

    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.partyUpdate,
      payload: {'type': arg.apiValue, 'id': id, 'input': input.toJson()},
      createdAt: DateTime.now(),
    );
    final result = await _sync.submit(op, () => ref.read(partiesRepositoryProvider).update(id, input));
    if (!result.queued) await refresh();
    return result;
  }

  Future<SubmitResult<Party>> archive(String id) async {
    // Archiving a party that never reached the server just forgets it, with any
    // credit entries that were waiting on it.
    if (id.startsWith('local:')) {
      await ref.read(outboxProvider.notifier).removeWhere(
            (o) => o.localId == id || o.payload['id'] == id || o.payload['partyId'] == id,
          );
      return const SubmitResult.queued();
    }

    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.partyArchive,
      payload: {'type': arg.apiValue, 'id': id},
      createdAt: DateTime.now(),
    );
    final result = await _sync.submit(op, () => ref.read(partiesRepositoryProvider).archive(arg, id));
    if (!result.queued) await refresh();
    return result;
  }
}

final partiesProvider =
    AsyncNotifierProvider.family<PartiesNotifier, List<Party>, PartyType>(PartiesNotifier.new);

/// What screens read: the server's list with every change still waiting to
/// sync applied on top (see `party_overlay.dart`).
final partyListProvider = Provider.family<List<Party>, PartyType>((ref, type) {
  final base = ref.watch(partiesProvider(type)).valueOrNull ?? const <Party>[];
  return overlayParties(base, ref.watch(outboxOpsProvider), type);
});

/// Which party's ledger — `({type, id})` has value equality, so it works as a
/// provider family argument.
typedef PartyKey = ({PartyType type, String id});

class CreditEntriesNotifier extends FamilyAsyncNotifier<List<CreditEntry>, PartyKey> {
  @override
  Future<List<CreditEntry>> build(PartyKey arg) async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    // A party created offline has nothing on the server yet.
    if (arg.id.startsWith('local:')) return const [];
    return ref.watch(partiesRepositoryProvider).entries(arg.type, arg.id);
  }

  Future<void> refresh() async {
    if (arg.id.startsWith('local:')) return;
    state = await AsyncValue.guard(() => ref.read(partiesRepositoryProvider).entries(arg.type, arg.id));
  }
}

final creditEntriesProvider =
    AsyncNotifierProvider.family<CreditEntriesNotifier, List<CreditEntry>, PartyKey>(
  CreditEntriesNotifier.new,
);

/// One party's ledger as screens show it: entries still waiting to sync (marked
/// pending) on top of what the server has.
final creditLedgerProvider = Provider.family<List<CreditEntry>, PartyKey>((ref, key) {
  final saved = ref.watch(creditEntriesProvider(key)).valueOrNull ?? const <CreditEntry>[];
  return [...pendingCreditEntries(ref.watch(outboxOpsProvider), key.id), ...saved];
});

/// Records charges, payments and adjustments on a credit ledger.
class CreditService {
  CreditService(this._ref);

  final Ref _ref;

  /// Sends the entry now if the connection is good, otherwise saves it on this
  /// computer to sync later. [amount] is positive for a charge or payment and
  /// signed for an adjustment.
  Future<SubmitResult<({CreditEntry entry, double balanceOwed})>> record({
    required PartyType partyType,
    required String partyId,
    required CreditKind kind,
    required double amount,
    String? note,
  }) async {
    final op = OutboxOp(
      id: newOpId(),
      kind: OpKind.creditEntry,
      payload: {
        'partyType': partyType.apiValue,
        'partyId': partyId,
        'kind': kind.apiValue,
        'amount': amount,
        'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      },
      createdAt: DateTime.now(),
    );

    // The op id doubles as the request's clientRef, so sending the same
    // entry twice can never record it twice.
    final result = await _ref.read(syncEngineProvider.notifier).submit(
          op,
          () => _ref.read(partiesRepositoryProvider).recordEntry(
                partyType: partyType,
                partyId: partyId,
                kind: kind,
                amount: amount,
                note: note,
                clientRef: op.id,
              ),
        );

    if (!result.queued) {
      await Future.wait([
        _ref.read(partiesProvider(partyType).notifier).refresh(),
        _ref.read(creditEntriesProvider((type: partyType, id: partyId)).notifier).refresh(),
      ]);
    }
    return result;
  }
}

final creditServiceProvider = Provider<CreditService>((ref) => CreditService(ref));
