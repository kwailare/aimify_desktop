import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import 'local_store.dart';

/// The changes that can be made while offline and synced later.
///
/// Warehouses, categories/units and product pictures are not queued: they
/// are rare admin actions, and a picture is a large file — those need a
/// connection.
enum OpKind { movement, productCreate, productUpdate, productArchive }

/// A unique id for a queued change (time plus randomness, so two changes
/// made in the same microsecond still differ).
String newOpId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

/// One change waiting to reach the server, saved on disk until it does.
class OutboxOp {
  const OutboxOp({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.attempted = false,
    this.error,
  });

  /// Unique id. For [OpKind.productCreate] this doubles as the local id of
  /// the product (`local:<id>`) until the server assigns a real one.
  final String id;
  final OpKind kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// True once a send was started but its outcome is unknown (the request
  /// may have reached the server before the connection dropped). Such an op
  /// is checked against the server before it is sent again, so it can never
  /// be applied twice.
  final bool attempted;

  /// Set when the server definitively refused the change (a duplicate SKU, a
  /// role or plan block...). The op stays visible so nothing is lost
  /// silently, and the person can fix and retry it or discard it.
  final String? error;

  bool get failed => error != null;

  String get localProductId => 'local:$id';

  OutboxOp copyWith({bool? attempted, String? error, bool clearError = false}) => OutboxOp(
        id: id,
        kind: kind,
        payload: payload,
        createdAt: createdAt,
        attempted: attempted ?? this.attempted,
        error: clearError ? null : (error ?? this.error),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'payload': payload,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'attempted': attempted,
        'error': error,
      };

  factory OutboxOp.fromJson(Map<String, dynamic> json) => OutboxOp(
        id: json['id'] as String,
        kind: OpKind.values.firstWhere((k) => k.name == json['kind']),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        attempted: json['attempted'] as bool? ?? false,
        error: json['error'] as String?,
      );
}

/// The saved queue of changes, per signed-in user. It survives restarts and
/// even signing out, so nothing recorded offline is ever lost; it is synced
/// the next time that user is signed in with a good connection.
class OutboxNotifier extends AsyncNotifier<List<OutboxOp>> {
  Future<void> _writes = Future.value();

  String? get _key {
    final userId = ref.read(sessionUserIdProvider);
    return userId == null ? null : 'u_${userId}_outbox';
  }

  @override
  Future<List<OutboxOp>> build() async {
    final userId = ref.watch(sessionUserIdProvider);
    if (userId == null) return const [];
    final raw = await readJson(ref.read(localStoreProvider), 'u_${userId}_outbox');
    if (raw is! List) return const [];
    final ops = <OutboxOp>[];
    for (final item in raw) {
      try {
        ops.add(OutboxOp.fromJson(Map<String, dynamic>.from(item as Map)));
      } catch (_) {
        // One unreadable entry must not discard the rest of the queue.
      }
    }
    return ops;
  }

  List<OutboxOp> get _ops => state.valueOrNull ?? const [];

  /// Applies [next] immediately and saves it. Saves are chained, so the
  /// file always ends up holding the latest queue even when changes are made
  /// back to back.
  void _set(List<OutboxOp> next) {
    state = AsyncData(next);
    final key = _key;
    if (key == null) return;
    final store = ref.read(localStoreProvider);
    _writes = _writes.then((_) async {
      try {
        await writeJson(store, key, [for (final op in state.valueOrNull ?? const []) op.toJson()]);
      } catch (_) {
        // The in-memory queue is still right; the next change saves again.
      }
    });
  }

  /// Resolves once everything queued so far has been written to disk.
  Future<void> flushWrites() => _writes;

  // Every mutation first waits for the saved queue to finish loading, so a
  // change made right at startup can never overwrite entries still being read.

  Future<void> add(OutboxOp op) async {
    await future;
    _set([..._ops, op]);
  }

  Future<void> remove(String id) async {
    await future;
    _set(_ops.where((o) => o.id != id).toList());
  }

  Future<void> removeWhere(bool Function(OutboxOp) test) async {
    await future;
    _set(_ops.where((o) => !test(o)).toList());
  }

  Future<void> replace(OutboxOp updated) async {
    await future;
    _set([for (final o in _ops) if (o.id == updated.id) updated else o]);
  }
}

final outboxProvider = AsyncNotifierProvider<OutboxNotifier, List<OutboxOp>>(OutboxNotifier.new);

/// The queue as a plain list (empty while loading).
final outboxOpsProvider = Provider<List<OutboxOp>>(
  (ref) => ref.watch(outboxProvider).valueOrNull ?? const [],
);

/// Changes still waiting to sync (not counting ones the server refused).
final pendingCountProvider = Provider<int>(
  (ref) => ref.watch(outboxOpsProvider).where((o) => !o.failed).length,
);

/// Changes the server refused, waiting for the person to fix or discard.
final failedOpsProvider = Provider<List<OutboxOp>>(
  (ref) => ref.watch(outboxOpsProvider).where((o) => o.failed).toList(),
);
