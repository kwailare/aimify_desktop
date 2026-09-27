import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import 'local_store.dart';

/// A list that lives on this computer and survives restarts, for modules the
/// backend doesn't have yet (customers, suppliers, purchases, expenses).
///
/// Each signed-in user gets their own saved copy (`u_<userId>_<name>`), so
/// nothing leaks between accounts on a shared machine. It is loaded when
/// first needed and saved after every change; a missing or damaged file
/// simply starts empty.
abstract class PersistedListNotifier<T> extends Notifier<List<T>> {
  /// File name stem, e.g. `customers`.
  String get name;

  Map<String, dynamic> encode(T item);
  T decode(Map<String, dynamic> json);

  Future<void> _writes = Future.value();

  String? get _key {
    final userId = ref.read(sessionUserIdProvider);
    return userId == null ? null : 'u_${userId}_$name';
  }

  @override
  List<T> build() {
    final userId = ref.watch(sessionUserIdProvider);
    if (userId != null) _load(userId);
    return const [];
  }

  Future<void> _load(String userId) async {
    final raw = await readJson(ref.read(localStoreProvider), 'u_${userId}_$name');
    if (raw is! List || ref.read(sessionUserIdProvider) != userId) return;
    final loaded = <T>[];
    for (final item in raw) {
      try {
        loaded.add(decode(Map<String, dynamic>.from(item as Map)));
      } catch (_) {
        // Skip one unreadable entry rather than losing the whole list.
      }
    }
    // Anything added while the file was still being read stays.
    state = [...loaded, ...state];
  }

  /// Replaces the list and saves it.
  void setAndSave(List<T> next) {
    state = next;
    final key = _key;
    if (key == null) return;
    final store = ref.read(localStoreProvider);
    _writes = _writes.then((_) async {
      try {
        await writeJson(store, key, [for (final item in state) encode(item)]);
      } catch (_) {
        // The in-memory list is still right; the next change saves again.
      }
    });
  }

  /// Resolves once everything changed so far has been written to disk.
  Future<void> flushWrites() => _writes;
}
