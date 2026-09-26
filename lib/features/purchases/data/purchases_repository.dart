import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/purchase.dart';

/// LOCAL ONLY — in-memory for the current session. No `/api/v1/purchases`
/// endpoint exists yet, so nothing here is saved or synced.
class PurchasesNotifier extends Notifier<List<Purchase>> {
  @override
  List<Purchase> build() => const [];

  void addPurchase(Purchase purchase) => state = [purchase, ...state];
}

final purchasesProvider = NotifierProvider<PurchasesNotifier, List<Purchase>>(
  PurchasesNotifier.new,
);
