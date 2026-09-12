/// A catalog entry — shared across every warehouse in the organization.
/// SKU, name, category and pricing are the same everywhere; on-hand stock
/// is NOT part of this model because it varies independently per
/// warehouse — see `WarehouseStock` in the inventory feature.
///
/// Placeholder domain model — there is no `/api/v1/products` endpoint yet
/// (see `docs/desktop-api.md`), so this shape is a best guess at what the
/// eventual schema will look like.
class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.barcode,
    required this.name,
    required this.category,
    required this.unitOfMeasure,
    required this.purchasePrice,
    required this.sellingPrice,
  });

  final String id;
  final String sku;
  final String barcode;
  final String name;
  final String category;
  final String unitOfMeasure;
  final double purchasePrice;
  final double sellingPrice;
}
