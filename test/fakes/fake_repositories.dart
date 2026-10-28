import 'package:aimify_desktop/features/credits_debts/data/debt_report.dart';
import 'package:aimify_desktop/features/customers/data/customer_types.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/data/supplier_options.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/catalog_repository.dart';
import 'package:aimify_desktop/features/purchases/data/purchases_repository.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/reports/data/valuation_report.dart';
import 'package:aimify_desktop/features/sales/data/sales_repository.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
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
  String? customerTypeId,
  String? customerTypeName,
  double totalSales = 0,
  int salesCount = 0,
  DateTime? lastSaleAt,
  bool isActive = true,
  String? email,
}) =>
    Party(
      id: id,
      type: type,
      name: name ?? '${type.label} $id',
      phone: '0700',
      email: email,
      creditLimit: creditLimit,
      balanceOwed: balance,
      customerTypeId: customerTypeId,
      customerTypeName: customerTypeName,
      totalSales: totalSales,
      salesCount: salesCount,
      lastSaleAt: lastSaleAt,
      isActive: isActive,
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

  /// The method sent with each entry, in order.
  final List<String?> methods = [];

  /// What the next payment says it settled.
  List<CreditAllocation> nextAllocations = const [];
  int _receipts = 0;

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
    final party = input.toLocalParty('srv${created.length}').copyWith(isPending: false);
    _setList(input.type, [..._listFor(input.type), party]);
    return party;
  }

  /// Every edit sent.
  final List<({String id, PartyInput input})> updated = [];

  @override
  Future<Party> update(String id, PartyInput input) async {
    updated.add((id: id, input: input));
    final next = _listFor(input.type).firstWhere((p) => p.id == id).withInput(input);
    _setList(input.type, [for (final p in _listFor(input.type)) p.id == id ? next : p]);
    return next;
  }

  /// Like the server: customers are listed with the archived ones, suppliers
  /// without.
  @override
  Future<Party> archive(PartyType type, String id) async {
    final archived = _listFor(type).firstWhere((p) => p.id == id).copyWith(isActive: false);
    _setList(
      type,
      type == PartyType.customer
          ? [for (final p in _listFor(type)) p.id == id ? archived : p]
          : _listFor(type).where((p) => p.id != id).toList(),
    );
    return archived;
  }

  final List<String> restored = [];

  @override
  Future<Party> restore(PartyType type, String id) async {
    restored.add(id);
    final active = _listFor(type).firstWhere((p) => p.id == id).copyWith(isActive: true);
    _setList(type, [for (final p in _listFor(type)) p.id == id ? active : p]);
    return active;
  }

  @override
  Future<List<CreditEntry>> entries(PartyType type, String partyId) async =>
      ledger.where((e) => e.partyId == partyId).toList().reversed.toList();

  /// Every period asked for, in order.
  final List<({DateTime? from, DateTime to})> statementRequests = [];

  @override
  Future<({List<CreditEntry> entries, double openingBalance})> ledgerForPeriod(
    PartyType type,
    String partyId, {
    DateTime? from,
    required DateTime to,
  }) async {
    statementRequests.add((from: from, to: to));
    final mine = ledger.where((e) => e.partyId == partyId);
    return (
      entries: mine
          .where((e) => (from == null || !e.createdAt.isBefore(from)) && e.createdAt.isBefore(to))
          .toList(),
      openingBalance: from == null
          ? 0.0
          : mine.where((e) => e.createdAt.isBefore(from)).fold(0.0, (sum, e) => sum + e.amount),
    );
  }

  @override
  Future<({CreditEntry entry, double balanceOwed})> recordEntry({
    required PartyType partyType,
    required String partyId,
    required CreditKind kind,
    required double amount,
    String? note,
    String? method,
    String? clientRef,
  }) async {
    recorded.add((partyId: partyId, kind: kind, amount: amount, clientRef: clientRef));
    methods.add(method);
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
      method: kind == CreditKind.payment ? (method ?? 'cash') : null,
      receiptNumber: partyType == PartyType.customer && kind == CreditKind.payment
          ? 'RCPT-${(++_receipts).toString().padLeft(4, '0')}'
          : null,
      allocations: signed < 0 ? nextAllocations : const [],
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

class FakeSalesRepository implements SalesRepository {
  FakeSalesRepository([List<Sale>? sales]) : sales = sales ?? [];

  List<Sale> sales;

  /// Every create sent, with its clientRef.
  final List<({SaleInput input, String? clientRef})> created = [];
  final List<({String id, double amount, SalePaymentMethod method})> paid = [];
  final List<({String id, String reason})> voided = [];

  /// Stock alerts the next create returns.
  List<({String productId, String alert})> alerts = const [];

  /// Thrown by the next write when set (a refusal or a network failure).
  Object? writeError;

  void _maybeFail() {
    final error = writeError;
    if (error != null) throw error;
  }

  Sale _find(String id) => sales.firstWhere((s) => s.id == id);

  Sale _copy(Sale s, {SaleStatus? status, double? amountPaid, String? voidReason, List<SalePayment>? payments}) =>
      Sale(
        id: s.id,
        reference: s.reference,
        customerId: s.customerId,
        customerName: s.customerName,
        warehouseId: s.warehouseId,
        warehouseName: s.warehouseName,
        status: status ?? s.status,
        saleDate: s.saleDate,
        subtotal: s.subtotal,
        discount: s.discount,
        tax: s.tax,
        total: s.total,
        amountPaid: amountPaid ?? s.amountPaid,
        voidReason: voidReason ?? s.voidReason,
        createdByName: s.createdByName,
        lines: s.lines,
        payments: payments ?? s.payments,
      );

  void _replace(Sale sale) => sales = [for (final s in sales) s.id == sale.id ? sale : s];

  @override
  Future<List<Sale>> list() async => List.of(sales);

  @override
  Future<Sale> get(String id) async => _find(id);

  @override
  Future<List<Sale>> listForCustomer(String customerId) async =>
      sales.where((s) => s.customerId == customerId).toList();

  @override
  Future<SaleOutcome> create(SaleInput input, {String? clientRef}) async {
    _maybeFail();
    created.add((input: input, clientRef: clientRef));
    final n = created.length;
    final sale = fixtureSale(
      'srv$n',
      reference: 'INV-${n.toString().padLeft(4, '0')}',
      customerId: input.customerId,
      warehouseId: input.warehouseId,
      lines: [for (final l in input.lines) (productId: l.productId, quantity: l.quantity, unitPrice: l.unitPrice)],
      discount: input.discount,
      tax: input.tax,
      amountPaid: input.amountPaid,
      method: input.paymentMethod,
    );
    sales = [sale, ...sales];
    return SaleOutcome(sale: sale, alerts: alerts);
  }

  @override
  Future<Sale> pay(String id, {required double amount, required SalePaymentMethod method, String? note}) async {
    _maybeFail();
    paid.add((id: id, amount: amount, method: method));
    final s = _find(id);
    final sale = _copy(
      s,
      amountPaid: s.amountPaid + amount,
      payments: [
        ...s.payments,
        SalePayment(
          id: '$id-p${s.payments.length}',
          amount: amount,
          method: method,
          note: note,
          createdAt: DateTime(2026, 10, 26, 12),
        ),
      ],
    );
    _replace(sale);
    return sale;
  }

  @override
  Future<({Sale sale, double refundOwed, double creditedToAccount})> voidSale(String id, {required String reason}) async {
    _maybeFail();
    voided.add((id: id, reason: reason));
    final s = _find(id);
    final sale = _copy(s, status: SaleStatus.voided, voidReason: reason);
    _replace(sale);
    return (sale: sale, refundOwed: s.amountPaid, creditedToAccount: 0.0);
  }
}

/// A sale as the server would return it.
Sale fixtureSale(
  String id, {
  String reference = 'INV-0001',
  String? customerId = 'c1',
  String? customerName,
  String warehouseId = 'w1',
  String warehouseName = 'Main Warehouse',
  SaleStatus status = SaleStatus.completed,
  List<({String productId, int quantity, double unitPrice})>? lines,
  double discount = 0,
  double tax = 0,
  double? amountPaid,
  SalePaymentMethod method = SalePaymentMethod.cash,
  DateTime? saleDate,
  double listPrice = 150,
}) {
  final rows = lines ?? [(productId: '1', quantity: 2, unitPrice: 150.0)];
  final subtotal = rows.fold(0.0, (s, l) => s + l.quantity * l.unitPrice);
  final total = subtotal - discount + tax;
  final paid = amountPaid ?? total;
  final date = saleDate ?? DateTime.now();
  return Sale(
    id: id,
    reference: reference,
    customerId: customerId,
    customerName: customerName ?? (customerId == null ? 'Walk-in customer' : 'Customer $customerId'),
    warehouseId: warehouseId,
    warehouseName: warehouseName,
    status: status,
    saleDate: date,
    subtotal: subtotal,
    discount: discount,
    tax: tax,
    total: total,
    amountPaid: paid,
    voidReason: status == SaleStatus.voided ? 'Entered by mistake' : null,
    createdByName: 'Ada Owner',
    lines: [
      for (var i = 0; i < rows.length; i++)
        SaleLine(
          id: '$id-l$i',
          productId: rows[i].productId,
          productName: 'Product ${rows[i].productId}',
          sku: 'SKU-${rows[i].productId}',
          unit: 'bag',
          quantity: rows[i].quantity,
          unitPrice: rows[i].unitPrice,
          listPrice: listPrice,
        ),
    ],
    payments: [
      if (paid > 0) SalePayment(id: '$id-p0', amount: paid, method: method, createdAt: date, userName: 'Ada Owner'),
    ],
  );
}

class FakeCustomerTypesRepository implements CustomerTypesRepository {
  FakeCustomerTypesRepository([List<CustomerType>? types])
      : types = types ??
            const [
              CustomerType(id: 't-retail', name: 'Retail'),
              CustomerType(id: 't-wholesale', name: 'Wholesale', defaultCreditLimit: 500000),
            ];

  List<CustomerType> types;
  final List<String> deleted = [];

  /// Thrown by the next change when set.
  Object? writeError;

  void _maybeFail() {
    final error = writeError;
    if (error != null) throw error;
  }

  @override
  Future<List<CustomerType>> list() async => List.of(types);

  @override
  Future<CustomerType> create(String name, {double defaultCreditLimit = 0, int defaultPaymentTermsDays = 30}) async {
    _maybeFail();
    final type = CustomerType(
      id: 't${types.length + 1}',
      name: name,
      defaultCreditLimit: defaultCreditLimit,
      defaultPaymentTermsDays: defaultPaymentTermsDays,
    );
    types = [...types, type];
    return type;
  }

  @override
  Future<CustomerType> update(String id, {String? name, double? defaultCreditLimit, int? defaultPaymentTermsDays}) async {
    _maybeFail();
    final old = types.firstWhere((t) => t.id == id);
    final next = CustomerType(
      id: id,
      name: name ?? old.name,
      defaultCreditLimit: defaultCreditLimit ?? old.defaultCreditLimit,
      defaultPaymentTermsDays: defaultPaymentTermsDays ?? old.defaultPaymentTermsDays,
      customerCount: old.customerCount,
    );
    types = [for (final t in types) t.id == id ? next : t];
    return next;
  }

  @override
  Future<void> delete(String id) async {
    _maybeFail();
    deleted.add(id);
    types = types.where((t) => t.id != id).toList();
  }
}

class FakeDebtReportRepository implements DebtReportRepository {
  FakeDebtReportRepository({this.customers, this.suppliers});

  DebtReport? customers;
  DebtReport? suppliers;
  final List<PartyType> requested = [];

  @override
  Future<DebtReport> fetch(PartyType type) async {
    requested.add(type);
    return (type == PartyType.customer ? customers : suppliers) ??
        DebtReport(
          asOf: DateTime(2026, 10, 28, 9),
          type: type,
          balance: 0,
          overdue: 0,
          credit: 0,
          buckets: {for (final b in AgeBucket.values) b: 0},
          parties: const [],
        );
  }
}

List<Override> fakeDataOverrides({
  FakeProductsRepository? products,
  FakeWarehousesRepository? warehouses,
  FakeInventoryRepository? inventory,
  FakePartiesRepository? parties,
  FakeSupplierOptionsRepository? supplierOptions,
  FakeValuationRepository? valuation,
  FakePurchasesRepository? purchases,
  FakeSalesRepository? sales,
  FakeCustomerTypesRepository? customerTypes,
  FakeDebtReportRepository? debts,
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
      salesRepositoryProvider.overrideWithValue(sales ?? FakeSalesRepository()),
      customerTypesRepositoryProvider.overrideWithValue(customerTypes ?? FakeCustomerTypesRepository()),
      debtReportRepositoryProvider.overrideWithValue(debts ?? FakeDebtReportRepository()),
    ];
