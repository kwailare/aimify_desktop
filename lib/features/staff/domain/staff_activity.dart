enum StaffActivityKind { stockOut, viewedSuppliers, viewedProducts, login }

extension StaffActivityKindLabel on StaffActivityKind {
  String get label => switch (this) {
        StaffActivityKind.stockOut => 'Recorded stock-out',
        StaffActivityKind.viewedSuppliers => 'Viewed Suppliers',
        StaffActivityKind.viewedProducts => 'Viewed Products',
        StaffActivityKind.login => 'Signed in',
      };
}

/// One logged action by a staff member. Feeds the admin-only activity
/// audit trail (see `docs/desktop-api.md` — the admin can see every staff
/// member's activity; a staff member would only ever see their own once
/// staff sign-in exists).
class StaffActivity {
  const StaffActivity({
    required this.id,
    required this.staffId,
    required this.kind,
    required this.detail,
    required this.date,
  });

  final String id;
  final String staffId;
  final StaffActivityKind kind;
  final String detail;
  final DateTime date;
}
