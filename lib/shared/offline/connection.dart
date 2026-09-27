import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_exception.dart';

/// How usable the network is right now, judged from real requests.
///
/// - [good]: requests get answers quickly — changes are sent straight away
///   and the waiting queue is synced.
/// - [poor]: answers are slow or requests time out — changes are saved on
///   this computer instead of making the person wait, and synced once the
///   connection is good again.
/// - [offline]: no answer at all — same, saved locally.
enum ConnectionQuality { good, poor, offline }

/// A request slower than this counts as a poor connection even though it
/// succeeded — the next one is likely to time out.
const slowRequestThreshold = Duration(seconds: 4);

class ConnectionNotifier extends Notifier<ConnectionQuality> {
  @override
  ConnectionQuality build() => ConnectionQuality.good;

  void reportSuccess(Duration elapsed) {
    state = elapsed >= slowRequestThreshold ? ConnectionQuality.poor : ConnectionQuality.good;
  }

  /// A request that never got an answer. A timeout means the network is
  /// there but too slow ([ConnectionQuality.poor]); anything else (no route,
  /// DNS, refused) means offline.
  void reportFailure(NetworkException error) {
    state = error.cause is TimeoutException ? ConnectionQuality.poor : ConnectionQuality.offline;
  }

  /// Tests and the sync engine can force a state.
  void set(ConnectionQuality quality) => state = quality;
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionQuality>(ConnectionNotifier.new);

/// When the data on screen was last fresh from the server, if what's shown
/// is a saved copy — `null` when everything shown is current.
final staleSinceProvider = StateProvider<DateTime?>((ref) => null);

/// Kept so existing call sites read naturally: true only when there is no
/// connection at all.
final isOfflineProvider = Provider<bool>(
  (ref) => ref.watch(connectionProvider) == ConnectionQuality.offline,
);
