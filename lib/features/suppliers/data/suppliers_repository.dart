import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/supplier.dart';

/// LOCAL ONLY — in-memory for the current session. No `/api/v1/suppliers`
/// endpoint exists yet, so nothing here is saved or synced.
class SuppliersNotifier extends Notifier<List<Supplier>> {
  @override
  List<Supplier> build() => const [];

  void addSupplier(Supplier supplier) => state = [...state, supplier];

  /// Records a payment made to a supplier — used by the Credits & Debts
  /// screen. Clamped so it can't go negative.
  void recordPayment(String supplierId, double amount) {
    state = [
      for (final supplier in state)
        if (supplier.id == supplierId)
          supplier.copyWith(balanceOwed: (supplier.balanceOwed - amount).clamp(0, double.infinity))
        else
          supplier,
    ];
  }
}

final suppliersProvider = NotifierProvider<SuppliersNotifier, List<Supplier>>(
  SuppliersNotifier.new,
);
