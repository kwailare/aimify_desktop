import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/data/supplier_options.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/catalog_repository.dart';
import 'package:aimify_desktop/features/purchases/data/purchases_repository.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/reports/data/valuation_report.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/warehouses/data/warehouses_repository.dart';
import 'package:aimify_desktop/features/warehouses/domain/warehouse.dart';
import 'package:aimify_desktop/shared/offline/local_store.dart';
import 'package:aimify_desktop/shared/services/api_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory stand-ins for the network repositories, so widget tests run the
/// real screens and real notifiers without touching `localhost:3000`.

Product fixtureProduct(
  String id, {
  String? name,
  int stock = 10,
  int min = 5,
  String category = 'Grains',
  double cost = 100,
  double price = 150,
  String warehouseId = 'w1',
}) =>
    Product(
      id: id,
      sku: 'SKU-$id',
      name: name ?? 'Product $id',
      category: category,
      unit: 'bag',
      purchasePrice: cost,
      sellingPrice: price,
      minStock: min,
      currentStock: stock,
      // Like the server: the stock sits in a warehouse (the default fixture
      // warehouse unless told otherwise).
      stockByWarehouse: stock == 0 ? const {} : {warehouseId: stock},
      status: 'active',
    );

Warehouse fixtureWarehouse(String id, {String? name, bool active = true}) => Warehouse(
      id: id,
      name: name ?? 'Warehouse $id',
      isActive: active,
      createdAt: DateTime(2026, 9, 1),
    );

class FakeProductsRepository implements ProductsRepository {
  FakeProductsRepository(this.products, {List<Product>? archivedProducts})
      : archivedProducts = archivedProducts ?? [];

  List<Product> products;
  List<Product> archivedProducts;

  /// Every product created through this fake, in order (for asserting what
  /// the sync engine sent).
  final List<ProductInput> created = [];

  /// Thrown by [create] when set — a duplicate SKU or a plan-limit refusal.
  Object? createError;

  @override
  Future<List<Product>> list() async => List.of(products);

  @override
  Future<List<Product>> listFresh() async => List.of(products);

  @override
  Future<List<Product>> listArchived() async => List.of(archivedProducts);

  @override
  Future<Product> create(ProductInput input) async {
    final error = createError;
    if (error != null) throw error;
    this.created.add(input);
    final created =
        fixtureProduct('srv${this.created.length}', name: input.name, stock: 0).withInput(input);
    products = [...products, created];
    return created;
  }

  @override
  Future<Product> update(String id, ProductInput input) async => products.firstWhere((p) => p.id == id);

  @override
  Future<Product> archive(String id) async {
    final archived = products.firstWhere((p) => p.id == id);
    products = products.where((p) => p.id != id).toList();
    archivedProducts = [...archivedProducts, archived];
    return archived;
  }

  @override
  Future<Product> restore(String id) async {
    final restored = archivedProducts.firstWhere((p) => p.id == id);
    archivedProducts = archivedProducts.where((p) => p.id != id).toList();
    products = [...products, restored];
    return restored;
  }

  @override
  Future<Product> uploadImage(String id, {required List<int> bytes, required String filename}) async =>
      products.firstWhere((p) => p.id == id);

  @override
  Future<Product> removeImage(String id) async => products.firstWhere((p) => p.id == id);
}

class FakeWarehousesRepository implements WarehousesRepository {
  FakeWarehousesRepository(this.warehouses);

  List<Warehouse> warehouses;

  @override
  Future<List<Warehouse>> list() async => List.of(warehouses);

  @override
  Future<Warehouse> create({
    required String name,
    String? address,
    String? managerName,
    String? phone,
  }) async {
    final created = fixtureWarehouse('w${warehouses.length + 1}', name: name);
    warehouses = [...warehouses, created];
    return created;
  }

  @override
  Future<Warehouse> update(String id, Map<String, dynamic> changes) async =>
      warehouses.firstWhere((w) => w.id == id);
}

class FakeInventoryRepository implements InventoryRepository {
  FakeInventoryRepository({this.movementRows = const [], this.alertRows = const StockAlerts()});

  List<StockMovement> movementRows;
  StockAlerts alertRows;

  /// Thrown by [record] when set — a network failure or a server refusal.
  Object? recordError;

  /// When true, a failing [record] first applies the movement (as if the
  /// server processed it but the answer never arrived).
  bool applyBeforeFailing = false;

  /// Every movement sent through [record].
  final List<({String productId, int quantity})> sent = [];

  /// The last call to [record], so tests can assert the exact signed delta
  /// that would have been sent to the server.
  ({String productId, StockMovementType type, int quantity})? lastRecorded;

  @override
  Future<List<StockMovement>> movements() async => List.of(movementRows);

  @override
  Future<List<StockMovement>> movementsFresh() async => List.of(movementRows);

  @override
  Future<StockAlerts> alerts() async => alertRows;

  @override
  Future<MovementResult> record({
    required String productId,
    required String warehouseId,
    required StockMovementType type,
    required int quantity,
    String? reason,
  }) async {
    lastRecorded = (productId: productId, type: type, quantity: quantity);
    sent.add((productId: productId, quantity: quantity));
    final error = recordError;
    if (error != null) {
      if (applyBeforeFailing) {
        movementRows = [
          StockMovement(
            id: 'landed-${sent.length}',
            productId: productId,
            warehouseId: warehouseId,
            userId: 'u1',
            type: type,
            quantity: quantity,
            previousStock: 0,
            newStock: quantity,
            createdAt: DateTime.now(),
          ),
          ...movementRows,
        ];
      }
      throw error;
    }
    return MovementResult(
      movement: StockMovement(
        id: 'm-new',
        productId: productId,
        warehouseId: warehouseId,
        type: type,
        quantity: quantity,
        previousStock: 0,
        newStock: quantity,
        createdAt: DateTime(2026, 9, 26),
      ),
      currentStock: quantity,
    );
  }
}

class FakeCatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogOption>> list(CatalogKind kind) async => [
        CatalogOption(id: '${kind.name}1', name: kind == CatalogKind.category ? 'Grains' : 'bag'),
      ];

  @override
  Future<void> add(CatalogKind kind, String name) async {}

  @override
  Future<void> remove(CatalogKind kind, String id) async {}
}

Party fixtureParty(
  String id, {
  PartyType type = PartyType.customer,
  String? name,
  double balance = 0,
  double creditLimit = 0,
}) =>
    Party(
      id: id,
      type: type,
      name: name ?? '${type.label} $id',
      phone: '0700',
      creditLimit: creditLimit,
      balanceOwed: balance,
    );

/// In-memory customers, suppliers and credit ledger. Mirrors the server's
/// rules that matter to the app: a `clientRef` sent twice records once, and a
/// payment above the balance is refused.
class FakePartiesRepository implements PartiesRepository {
  FakePartiesRepository({List<Party>? customers, List<Party>? suppliers})
      : customers = customers ?? [],
        suppliers = suppliers ?? [];

  List<Party> customers;
  List<Party> suppliers;

  /// Every entry recorded, in order (what the sync engine sent).
  final List<({String partyId, CreditKind kind, double amount, String? clientRef})> recorded = [];

  /// Every party created.
  final List<PartyInput> created = [];

  /// Thrown by [recordEntry] / [create] when set.
  Object? recordError;
  Object? createError;

  final Map<String, CreditEntry> _byRef = {};
  final List<CreditEntry> ledger = [];

  List<Party> _listFor(PartyType type) => type == PartyType.customer ? customers : suppliers;

  void _setList(PartyType type, List<Party> next) {
    if (type == PartyType.customer) {
      customers = next;
    } else {
      suppliers = next;
    }
  }

  @override
  Future<List<Party>> list(PartyType type) async => List.of(_listFor(type));

  @override
  Future<List<Party>> listFresh(PartyType type) async => List.of(_listFor(type));

  @override
  Future<Party> create(PartyInput input) async {
    final error = createError;
    if (error != null) throw error;
    created.add(input);
    final party = fixtureParty('srv${created.length}', type: input.type, name: input.name);
    _setList(input.type, [..._listFor(input.type), party]);
    return party;
  }

  @override
  Future<Party> update(String id, PartyInput input) async =>
      _listFor(input.type).firstWhere((p) => p.id == id);

  @override
  Future<Party> archive(PartyType type, String id) async {
    final archived = _listFor(type).firstWhere((p) => p.id == id);
    _setList(type, _listFor(type).where((p) => p.id != id).toList());
    return archived;
  }

  @override
  Future<List<CreditEntry>> entries(PartyType type, String partyId) async =>
      ledger.where((e) => e.partyId == partyId).toList().reversed.toList();

  @override
  Future<({CreditEntry entry, double balanceOwed})> recordEntry({
    required PartyType partyType,
    required String partyId,
    required CreditKind kind,
    required double amount,
    String? note,
    String? clientRef,
  }) async {
    recorded.add((partyId: partyId, kind: kind, amount: amount, clientRef: clientRef));
    final error = recordError;
    if (error != null) throw error;

    final list = _listFor(partyType);
    final index = list.indexWhere((p) => p.id == partyId);
    if (index < 0) throw ApiException(404, 'Not found.');

    // The same clientRef is recorded once.
    if (clientRef != null && _byRef.containsKey(clientRef)) {
      return (entry: _byRef[clientRef]!, balanceOwed: list[index].balanceOwed);
    }

    final signed = signedCreditAmount(kind, amount);
    if (kind == CreditKind.payment && -signed > list[index].balanceOwed) {
      throw ApiException(400, 'This payment is more than the balance owed.', code: 'overpayment');
    }

    final entry = CreditEntry(
      id: 'e${ledger.length + 1}',
      partyType: partyType,
      partyId: partyId,
      kind: kind,
      amount: signed,
      note: note,
      userId: 'u1',
      createdAt: DateTime.now(),
    );
    ledger.add(entry);
    if (clientRef != null) _byRef[clientRef] = entry;
    final updated = list[index].copyWith(balanceOwed: list[index].balanceOwed + signed);
    _setList(partyType, [...list]..[index] = updated);
    return (entry: entry, balanceOwed: updated.balanceOwed);
  }
}

/// The overrides that swap every network repository for an in-memory one.
class FakeSupplierOptionsRepository implements SupplierOptionsRepository {
  FakeSupplierOptionsRepository([this.options = const []]);

  List<SupplierOption> options;
  int listCalls = 0;

  @override
  Future<List<SupplierOption>> list() async {
    listCalls++;
    return List.of(options);
  }
}

class FakeValuationRepository implements ValuationRepository {
  FakeValuationRepository([this.report]);

  ValuationReport? report;

  /// Every filter asked for, in order.
  final List<ValuationFilter> requested = [];

  @override
  Future<ValuationReport> fetch(ValuationFilter filter) async {
    requested.add(filter);
    return report ??
        ValuationReport(
          asOf: DateTime(2026, 10, 21, 10),
          totals: ValuationTotals.zero,
          byProduct: const [],
          byCategory: const [],
          byWarehouse: const [],
          negativeStockCount: 0,
          noCostCount: 0,
        );
  }
}

class FakePurchasesRepository implements PurchasesRepository {
  FakePurchasesRepository([List<Purchase>? purchases]) : purchases = purchases ?? [];

  List<Purchase> purchases;

  /// Every create sent, with its clientRef.
  final List<({PurchaseInput input, String? clientRef})> created = [];
  final List<({String id, Map<String, int>? lines})> received = [];
  final List<({String id, double amount})> paid = [];
  final List<String> cancelled = [];
  final List<({String id, Map<String, dynamic> changes})> updated = [];

  /// Thrown by the next write when set (a refusal or a network failure).
  Object? writeError;

  void _maybeFail() {
    final error = writeError;
    if (error != null) throw error;
  }

  Purchase _find(String id) => purchases.firstWhere((p) => p.id == id);

  @override
  Future<List<Purchase>> list() async => List.of(purchases);

  @override
  Future<Purchase> get(String id) async => _find(id);

  @override
  Future<Purchase> create(PurchaseInput input, {String? clientRef}) async {
    _maybeFail();
    created.add((input: input, clientRef: clientRef));
    final purchase = fixturePurchase(
      'srv${created.length}',
      supplierId: input.supplierId,
      warehouseId: input.warehouseId,
      status: input.receive
          ? PurchaseStatus.received
          : (input.placeOrder ? PurchaseStatus.pending : PurchaseStatus.draft),
      lines: [
        for (var i = 0; i < input.lines.length; i++)
          (
            productId: input.lines[i].productId,
            quantity: input.lines[i].quantity,
            unitCost: input.lines[i].unitCost,
            received: input.receive ? input.lines[i].quantity : 0,
          ),
      ],
      amountPaid: input.amountPaid,
    );
    purchases = [purchase, ...purchases];
    return purchase;
  }

  @override
  Future<Purchase> update(String id, Map<String, dynamic> changes) async {
    _maybeFail();
    updated.add((id: id, changes: changes));
    return _find(id);
  }

  @override
  Future<ReceiveOutcome> receive(String id, {Map<String, int>? lines}) async {
    _maybeFail();
    received.add((id: id, lines: lines));
    return ReceiveOutcome(purchase: _find(id), priceChanges: const []);
  }

  @override
  Future<Purchase> pay(String id, {required double amount, String? note}) async {
    _maybeFail();
    paid.add((id: id, amount: amount));
    return _find(id);
  }

  @override
  Future<({Purchase purchase, double refundOwed})> cancel(String id) async {
    _maybeFail();
    cancelled.add(id);
    return (purchase: _find(id), refundOwed: _find(id).amountPaid);
  }
}

/// A purchase as the server would return it.
Purchase fixturePurchase(
  String id, {
  String reference = 'PO-0001',
  String supplierId = 's1',
  String supplierName = 'Dangote Foods',
  String warehouseId = 'w1',
  String warehouseName = 'Main Warehouse',
  PurchaseStatus status = PurchaseStatus.pending,
  List<({String productId, int quantity, double unitCost, int received})>? lines,
  double amountPaid = 0,
  DateTime? postedAt,
}) {
  final rows = lines ?? [(productId: '1', quantity: 10, unitCost: 100.0, received: 0)];
  final total = rows.fold(0.0, (s, l) => s + l.quantity * l.unitCost);
  return Purchase(
    id: id,
    reference: reference,
    supplierId: supplierId,
    supplierName: supplierName,
    warehouseId: warehouseId,
    warehouseName: warehouseName,
    status: status,
    orderDate: DateTime(2026, 10, 20),
    subtotal: total,
    discount: 0,
    tax: 0,
    total: total,
    amountPaid: amountPaid,
    postedAt: postedAt ?? (rows.any((l) => l.received > 0) ? DateTime(2026, 10, 21) : null),
    lines: [
      for (var i = 0; i < rows.length; i++)
        PurchaseLine(
          id: '$id-l$i',
          productId: rows[i].productId,
          productName: 'Product ${rows[i].productId}',
          sku: 'SKU-${rows[i].productId}',
          unit: 'bag',
          quantity: rows[i].quantity,
          unitCost: rows[i].unitCost,
          receivedQuantity: rows[i].received,
        ),
    ],
  );
}

List<Override> fakeDataOverrides({
  FakeProductsRepository? products,
  FakeWarehousesRepository? warehouses,
  FakeInventoryRepository? inventory,
  FakePartiesRepository? parties,
  FakeSupplierOptionsRepository? supplierOptions,
  FakeValuationRepository? valuation,
  FakePurchasesRepository? purchases,
  LocalStore? store,
}) =>
    [
      localStoreProvider.overrideWithValue(store ?? MemoryLocalStore()),
      productsRepositoryProvider.overrideWithValue(
        products ?? FakeProductsRepository([fixtureProduct('1'), fixtureProduct('2', stock: 2)]),
      ),
      warehousesRepositoryProvider.overrideWithValue(
        warehouses ?? FakeWarehousesRepository([fixtureWarehouse('w1', name: 'Main Warehouse')]),
      ),
      inventoryRepositoryProvider.overrideWithValue(inventory ?? FakeInventoryRepository()),
      partiesRepositoryProvider.overrideWithValue(parties ?? FakePartiesRepository()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      supplierOptionsRepositoryProvider.overrideWithValue(supplierOptions ?? FakeSupplierOptionsRepository()),
      valuationRepositoryProvider.overrideWithValue(valuation ?? FakeValuationRepository()),
      purchasesRepositoryProvider.overrideWithValue(purchases ?? FakePurchasesRepository()),
    ];
