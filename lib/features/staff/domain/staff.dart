/// A staff member added by the org's admin (the real, subscribed
/// aimify-web user — always the superuser) and assigned to exactly one
/// warehouse. Placeholder domain model: there is no staff/user-management
/// backend yet. Staff members can't actually sign in independently in this
/// build — see `docs/desktop-api.md` and the note on the staff screen —
/// this only covers the admin-side management UI and the data-layer
/// scoping (by `warehouseId`) that a real staff session would use.
class Staff {
  const Staff({
    required this.id,
    required this.name,
    required this.email,
    required this.warehouseId,
  });

  final String id;
  final String name;
  final String email;
  final String warehouseId;
}
