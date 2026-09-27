import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/offline/persisted_list.dart';
import '../domain/supplier.dart';

/// LOCAL ONLY — saved on this computer (per signed-in user) and restored on
/// the next launch. No `/api/v1/suppliers` endpoint exists yet, so nothing
/// here is synced.
class SuppliersNotifier extends PersistedListNotifier<Supplier> {
  @override
  String get name => 'suppliers';

  @override
  Map<String, dynamic> encode(Supplier item) => item.toJson();

  @override
  Supplier decode(Map<String, dynamic> json) => Supplier.fromJson(json);

  void addSupplier(Supplier supplier) => setAndSave([...state, supplier]);

  /// Records a payment made to a supplier — used by the Credits & Debts
  /// screen. Clamped so it can't go negative.
  void recordPayment(String supplierId, double amount) {
    setAndSave([
      for (final supplier in state)
        if (supplier.id == supplierId)
          supplier.copyWith(balanceOwed: (supplier.balanceOwed - amount).clamp(0, double.infinity))
        else
          supplier,
    ]);
  }
}

final suppliersProvider = NotifierProvider<SuppliersNotifier, List<Supplier>>(
  SuppliersNotifier.new,
);
