import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/offline/persisted_list.dart';
import '../domain/purchase.dart';

/// LOCAL ONLY — saved on this computer (per signed-in user) and restored on
/// the next launch. No `/api/v1/purchases` endpoint exists yet, so nothing
/// here is synced.
class PurchasesNotifier extends PersistedListNotifier<Purchase> {
  @override
  String get name => 'purchases';

  @override
  Map<String, dynamic> encode(Purchase item) => item.toJson();

  @override
  Purchase decode(Map<String, dynamic> json) => Purchase.fromJson(json);

  void addPurchase(Purchase purchase) => setAndSave([purchase, ...state]);
}

final purchasesProvider = NotifierProvider<PurchasesNotifier, List<Purchase>>(
  PurchasesNotifier.new,
);
