/// A product exactly as `/api/v1/products` returns it.
///
/// [currentStock] is organization-wide and only ever changes through a
/// stock movement — the API refuses to set it directly, so it is read-only
/// here too. (Per-warehouse balances don't exist on the backend yet.)
class Product {
  const Product({
    required this.id,
    required this.sku,
    this.barcode,
    required this.name,
    this.description,
    this.brand,
    this.imageUrl,
    this.category,
    required this.unit,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.minStock,
    this.maxStock,
    required this.currentStock,
    required this.status,
    this.isPending = false,
  });

  final String id;
  final String sku;
  final String? barcode;
  final String name;
  final String? description;
  final String? brand;

  /// Public image URL, or `null` until one is uploaded.
  final String? imageUrl;
  final String? category;
  final String unit;
  final double purchasePrice;
  final double sellingPrice;

  /// Reorder level: an alert fires when stock crosses down to this.
  final int minStock;

  /// Optional ceiling; `null` means no upper limit.
  final int? maxStock;
  final int currentStock;

  /// `active`, `inactive` or `archived`.
  final String status;

  /// True for a product created while offline that hasn't reached the
  /// server yet — it exists only on this computer for now.
  final bool isPending;

  bool get isArchived => status == 'archived';
  bool get isOutOfStock => currentStock <= 0;

  /// Same rule the server uses for its low-stock alert: above zero, at or
  /// below the reorder level, and only when a reorder level is set.
  bool get isLowStock => minStock > 0 && currentStock > 0 && currentStock <= minStock;

  double get stockValueAtCost => currentStock * purchasePrice;
  double get stockValueAtRetail => currentStock * sellingPrice;

  /// What this product looks like once [input] is applied.
  Product withInput(ProductInput input, {bool? pending}) => Product(
        id: id,
        sku: input.sku,
        barcode: input.barcode,
        name: input.name,
        description: input.description,
        brand: input.brand,
        imageUrl: imageUrl,
        category: input.category,
        unit: input.unit,
        purchasePrice: input.purchasePrice,
        sellingPrice: input.sellingPrice,
        minStock: input.minStock,
        maxStock: input.maxStock,
        currentStock: currentStock,
        status: status,
        isPending: pending ?? isPending,
      );

  Product withStock(int stock) => Product(
        id: id,
        sku: sku,
        barcode: barcode,
        name: name,
        description: description,
        brand: brand,
        imageUrl: imageUrl,
        category: category,
        unit: unit,
        purchasePrice: purchasePrice,
        sellingPrice: sellingPrice,
        minStock: minStock,
        maxStock: maxStock,
        currentStock: stock,
        status: status,
        isPending: isPending,
      );

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        sku: json['sku'] as String,
        barcode: json['barcode'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        brand: json['brand'] as String?,
        imageUrl: json['imageUrl'] as String?,
        category: json['category'] as String?,
        unit: json['unit'] as String? ?? 'piece',
        purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0,
        sellingPrice: (json['sellingPrice'] as num?)?.toDouble() ?? 0,
        minStock: (json['minStock'] as num?)?.toInt() ?? 0,
        maxStock: (json['maxStock'] as num?)?.toInt(),
        currentStock: (json['currentStock'] as num?)?.toInt() ?? 0,
        status: json['status'] as String? ?? 'active',
      );
}

/// The editable fields of a product — what create sends and edit changes.
/// `currentStock` and `imageUrl` are deliberately not here: the first
/// changes only through movements, the second only through the image
/// endpoint.
class ProductInput {
  const ProductInput({
    required this.sku,
    required this.name,
    this.barcode,
    this.description,
    this.brand,
    this.category,
    required this.unit,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.minStock,
    this.maxStock,
  });

  final String sku;
  final String name;
  final String? barcode;
  final String? description;
  final String? brand;
  final String? category;
  final String unit;
  final double purchasePrice;
  final double sellingPrice;
  final int minStock;
  final int? maxStock;

  factory ProductInput.fromJson(Map<String, dynamic> json) => ProductInput(
        sku: json['sku'] as String,
        name: json['name'] as String,
        barcode: json['barcode'] as String?,
        description: json['description'] as String?,
        brand: json['brand'] as String?,
        category: json['category'] as String?,
        unit: json['unit'] as String,
        purchasePrice: (json['purchasePrice'] as num).toDouble(),
        sellingPrice: (json['sellingPrice'] as num).toDouble(),
        minStock: (json['minStock'] as num).toInt(),
        maxStock: (json['maxStock'] as num?)?.toInt(),
      );

  /// A brand-new product as it looks locally before the server has it.
  Product toLocalProduct(String id) => Product(
        id: id,
        sku: sku,
        barcode: barcode,
        name: name,
        description: description,
        brand: brand,
        category: category,
        unit: unit,
        purchasePrice: purchasePrice,
        sellingPrice: sellingPrice,
        minStock: minStock,
        maxStock: maxStock,
        currentStock: 0,
        status: 'active',
        isPending: true,
      );

  /// Full body for create, and for edit (nulls clear optional fields).
  Map<String, dynamic> toJson() => {
        'sku': sku,
        'name': name,
        'barcode': barcode,
        'description': description,
        'brand': brand,
        'category': category,
        'unit': unit,
        'purchasePrice': purchasePrice,
        'sellingPrice': sellingPrice,
        'minStock': minStock,
        'maxStock': maxStock,
      };
}
