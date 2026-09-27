import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../shared/offline/connection.dart';
import '../../shared/offline/outbox.dart';
import '../../shared/services/api_exception.dart';
import '../../shared/services/authed_api.dart';
import '../../shared/utils/friendly_error.dart';
import '../auth/presentation/auth_controller.dart';
import '../inventory/data/inventory_repository.dart';
import '../inventory/domain/stock_movement.dart';
import '../products/data/products_repository.dart';
import '../products/domain/product.dart';

/// The outcome of [SyncEngine.submit]: either the server took the change
/// right away ([value] is its answer) or it was saved on this computer to
/// sync later ([queued]).
class SubmitResult<T> {
  const SubmitResult.sent(this.value) : queued = false;
  const SubmitResult.queued()
      : value = null,
        queued = true;

  final T? value;
  final bool queued;
}

class SyncState {
  const SyncState({this.syncing = false, this.lastSyncedAt});

  final bool syncing;

  /// When the last queued change reached the server.
  final DateTime? lastSyncedAt;
}

/// Decides, for every change a person makes, between "send it now" and
/// "save it here and send it later", and later sends what was saved.
///
/// - **Good connection and nothing waiting:** the change is sent at once
///   (with a short timeout, so a slow network never leaves someone staring
///   at a spinner) and the person sees the server's answer.
/// - **Poor or no connection, or changes already waiting:** the change is
///   saved to the outbox on disk and shown immediately; order is preserved
///   so a stock movement never overtakes the product it refers to.
/// - **Later:** a timer checks the connection; once it is good the outbox is
///   sent in order. Anything the server refuses stays visible for the
///   person to fix or discard. Anything that *might* have been applied
///   before the connection dropped is checked against the server before it
///   is sent again, so it can never be applied twice.
class SyncEngine extends Notifier<SyncState> {
  static const _immediateTimeout = Duration(seconds: 8);
  static const _tick = Duration(seconds: 10);
  static const _idleProbeEvery = 3; // ticks: probe an idle, healthy link every 30 s

  Timer? _timer;
  Future<void>? _inFlight;
  int _ticks = 0;

  @override
  SyncState build() {
    ref.onDispose(stop);
    // The moment the connection turns good, send whatever is waiting.
    ref.listen(connectionProvider, (previous, next) {
      if (next == ConnectionQuality.good && ref.read(pendingCountProvider) > 0) {
        unawaited(flush());
      }
    });
    return const SyncState();
  }

  void start() {
    _timer ??= Timer.periodic(_tick, (_) => unawaited(tick()));
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One heartbeat: check the connection when it matters, and sync if it is
  /// good and something is waiting.
  Future<void> tick() async {
    if (ref.read(sessionUserIdProvider) == null) return;
    _ticks++;
    final quality = ref.read(connectionProvider);
    final pending = ref.read(pendingCountProvider) > 0;
    final needsProbe = quality != ConnectionQuality.good || pending || _ticks % _idleProbeEvery == 0;
    if (needsProbe) await probe();
    if (ref.read(connectionProvider) == ConnectionQuality.good && ref.read(pendingCountProvider) > 0) {
      await flush();
    }
  }

  /// A cheap authenticated request whose only job is to measure the link
  /// (every request feeds [connectionProvider]; failures are not errors).
  Future<void> probe() async {
    try {
      await ref.read(authedApiProvider).get(ApiConstants.me);
    } on NetworkException {
      // Already reflected in connectionProvider.
    } on ApiException {
      // The server answered (e.g. 401 handled elsewhere) — the link is fine.
    }
  }

  /// The "Sync now" button: check the link, then sync if it's good.
  /// Returns the connection quality it found.
  Future<ConnectionQuality> syncNow() async {
    await probe();
    final quality = ref.read(connectionProvider);
    if (quality == ConnectionQuality.good) await flush();
    return quality;
  }

  /// Sends [send] now if the connection is good and nothing is waiting,
  /// otherwise saves [op] to the outbox. A server refusal (an [ApiException])
  /// is never queued — it is thrown so the person sees why.
  Future<SubmitResult<T>> submit<T>(OutboxOp op, Future<T> Function() send) async {
    final outbox = ref.read(outboxProvider.notifier);
    await ref.read(outboxProvider.future);

    var attempted = false;
    final canSendNow = ref.read(connectionProvider) == ConnectionQuality.good &&
        ref.read(pendingCountProvider) == 0;
    if (canSendNow) {
      try {
        return SubmitResult.sent(await send().timeout(_immediateTimeout));
      } on NetworkException {
        attempted = true;
      } on TimeoutException {
        attempted = true;
        ref.read(connectionProvider.notifier).set(ConnectionQuality.poor);
      }
    }

    await outbox.add(op.copyWith(attempted: attempted));
    return const SubmitResult.queued();
  }

  /// Sends the outbox in order while the connection stays good. Callers that
  /// arrive while a sync is already running wait for that one to finish
  /// rather than starting a second.
  Future<void> flush() => _inFlight ??= _flush().whenComplete(() => _inFlight = null);

  Future<void> _flush() async {
    state = SyncState(syncing: true, lastSyncedAt: state.lastSyncedAt);
    var synced = 0;

    try {
      final outbox = ref.read(outboxProvider.notifier);
      await ref.read(outboxProvider.future);
      final idMap = <String, String>{};

      while (true) {
        if (ref.read(connectionProvider) != ConnectionQuality.good) break;
        final next = ref.read(outboxOpsProvider).where((o) => !o.failed).firstOrNull;
        if (next == null) break;

        final wasAttempted = next.attempted;
        if (!wasAttempted) await outbox.replace(next.copyWith(attempted: true));

        try {
          await _apply(next, wasAttempted, idMap);
          await outbox.remove(next.id);
          synced++;
        } on _Unresolvable catch (e) {
          await outbox.replace(next.copyWith(error: e.message));
        } on ApiException catch (e) {
          if (e.isUnauthorized || e.isSubscriptionInactive) break;
          await outbox.replace(next.copyWith(error: friendlyError(e), attempted: false));
        } on NetworkException {
          break;
        }
      }

      if (synced > 0) {
        await Future.wait([
          ref.read(productsProvider.notifier).refresh(),
          ref.read(movementsProvider.notifier).refresh(),
          ref.read(stockAlertsProvider.notifier).refresh(),
          ref.read(authControllerProvider.notifier).refresh(),
        ]);
      }
    } finally {
      state = SyncState(
        syncing: false,
        lastSyncedAt: synced > 0 ? DateTime.now() : state.lastSyncedAt,
      );
    }
  }

  String _resolve(String id, Map<String, String> idMap) {
    if (!id.startsWith('local:')) return id;
    return idMap[id] ??
        (throw const _Unresolvable(
          'The product this change belongs to could not be created, so it was not sent.',
        ));
  }

  Future<void> _apply(OutboxOp op, bool wasAttempted, Map<String, String> idMap) async {
    final products = ref.read(productsRepositoryProvider);
    final inventory = ref.read(inventoryRepositoryProvider);

    switch (op.kind) {
      case OpKind.productCreate:
        final input = ProductInput.fromJson(Map<String, dynamic>.from(op.payload['input'] as Map));
        // A send that may already have landed: adopt the product the server
        // has instead of creating it (and hitting "SKU already exists").
        Product? existing;
        if (wasAttempted) {
          existing = (await products.listFresh())
              .where((p) => p.sku == input.sku && p.name == input.name)
              .firstOrNull;
        }
        final product = existing ?? await products.create(input);
        idMap[op.localProductId] = product.id;

      case OpKind.productUpdate:
        final id = _resolve(op.payload['id'] as String, idMap);
        final input = ProductInput.fromJson(Map<String, dynamic>.from(op.payload['input'] as Map));
        await products.update(id, input);

      case OpKind.productArchive:
        final id = _resolve(op.payload['id'] as String, idMap);
        try {
          await products.archive(id);
        } on ApiException catch (e) {
          // Already gone: the archive is done.
          if (e.statusCode != 404) rethrow;
        }

      case OpKind.movement:
        final productId = _resolve(op.payload['productId'] as String, idMap);
        final warehouseId = op.payload['warehouseId'] as String;
        final type = StockMovementTypeX.fromApi(op.payload['type'] as String);
        final quantity = (op.payload['quantity'] as num).toInt();

        if (wasAttempted) {
          final myId = ref.read(sessionUserIdProvider);
          final since = op.createdAt.subtract(const Duration(minutes: 5));
          final landed = (await inventory.movementsFresh()).any((m) =>
              m.productId == productId &&
              m.warehouseId == warehouseId &&
              m.type == type &&
              m.quantity == quantity &&
              m.userId == myId &&
              m.createdAt.isAfter(since));
          if (landed) return;
        }

        await inventory.record(
          productId: productId,
          warehouseId: warehouseId,
          type: type,
          quantity: quantity,
          reason: op.payload['reason'] as String?,
        );
    }
  }
}

class _Unresolvable implements Exception {
  const _Unresolvable(this.message);

  final String message;
}

final syncEngineProvider = NotifierProvider<SyncEngine, SyncState>(SyncEngine.new);
