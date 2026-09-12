/// A single, independent stock location. Products are a shared catalog
/// across the organization, but every warehouse tracks its own on-hand
/// quantities against that catalog — see `WarehouseStock` in the inventory
/// feature. Placeholder domain model — no `/api/v1/warehouses` endpoint
/// exists yet.
class Warehouse {
  const Warehouse({
    required this.id,
    required this.name,
    required this.location,
  });

  final String id;
  final String name;
  final String location;
}
