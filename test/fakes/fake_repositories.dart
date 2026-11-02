import 'package:aimify_desktop/features/credits_debts/data/debt_report.dart';
import 'package:aimify_desktop/features/customers/data/customer_types.dart';
import 'package:aimify_desktop/features/dashboard/data/business_summary.dart';
import 'package:aimify_desktop/features/expenses/data/expenses_repository.dart';
import 'package:aimify_desktop/features/expenses/domain/expense.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/parties/data/parties_repository.dart';
import 'package:aimify_desktop/features/parties/data/supplier_options.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/products/data/catalog_repository.dart';
import 'package:aimify_desktop/features/purchases/data/purchases_repository.dart';
import 'package:aimify_desktop/features/purchases/domain/purchase.dart';
import 'package:aimify_desktop/features/reports/data/period_reports.dart';
import 'package:aimify_desktop/features/reports/data/valuation_report.dart';
import 'package:aimify_desktop/features/sales/data/sales_repository.dart';
import 'package:aimify_desktop/features/sales/domain/sale.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/suppliers/data/supplier_prices.dart';
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

  /// Like the server (read with includeArchived): an archived party stays
  /// listed, marked.
  @override
  Future<Party> archive(PartyType type, String id) async {
    final archived = _listFor(type).firstWhere((p) => p.id == id).copyWith(isActive: false);
    _setList(type, [for (final p in _listFor(type)) p.id == id ? archived : p]);
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
  Future<List<Purchase>> listForSupplier(String supplierId) async =>
      purchases.where((p) => p.supplierId == supplierId).toList();

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

class FakeSupplierPricesRepository implements SupplierPricesRepository {
  FakeSupplierPricesRepository([Map<String, List<SupplierProductPrice>>? bySupplier]) : bySupplier = bySupplier ?? {};

  final Map<String, List<SupplierProductPrice>> bySupplier;

  @override
  Future<List<SupplierProductPrice>> fetch(String supplierId) async => bySupplier[supplierId] ?? const [];
}

/// An expense as the server would return it.
Expense fixtureExpense(
  String id, {
  String reference = 'EXP-0001',
  String categoryId = 'cat-fuel',
  String categoryName = 'Fuel & generator',
  double amount = 45000,
  DateTime? date,
  bool voided = false,
  String? description = 'Diesel',
  String? warehouseId,
  String? warehouseName,
  String? attachmentUrl,
  String? attachmentType,
  String? createdById = 'u1',
}) =>
    Expense(
      id: id,
      reference: reference,
      categoryId: categoryId,
      categoryName: categoryName,
      description: description,
      amount: amount,
      expenseDate: date ?? DateTime.now(),
      warehouseId: warehouseId,
      warehouseName: warehouseName,
      attachmentUrl: attachmentUrl,
      attachmentName: attachmentUrl == null ? null : 'receipt',
      attachmentType: attachmentType,
      status: voided ? ExpenseStatus.voided : ExpenseStatus.recorded,
      voidReason: voided ? 'Recorded twice' : null,
      createdById: createdById,
      createdByName: 'Ada',
      createdAt: date ?? DateTime.now(),
    );

class FakeExpensesRepository implements ExpensesRepository {
  FakeExpensesRepository({List<Expense>? expenses, List<ExpenseCategory>? categories, List<RecurringExpense>? recurring})
      : expenses = expenses ?? [],
        cats = categories ??
            [
              const ExpenseCategory(id: 'cat-rent', name: 'Rent', monthlyBudget: 300000),
              const ExpenseCategory(id: 'cat-fuel', name: 'Fuel & generator', monthlyBudget: 50000),
              const ExpenseCategory(id: 'cat-other', name: 'Other'),
            ],
        recurringList = recurring ?? [];

  List<Expense> expenses;
  List<ExpenseCategory> cats;
  List<RecurringExpense> recurringList;
  final List<({ExpenseInput input, String? clientRef})> created = [];
  final List<({String id, ExpenseInput input})> updated = [];
  final List<({String id, String reason})> voided = [];
  final List<({String id, String filename, int size})> attached = [];
  final List<({String id, DateTime dueDate, double? amount})> recorded = [];
  final List<({String? id, Map<String, dynamic> fields})> savedRecurring = [];

  /// Thrown by the next write when set.
  Object? writeError;

  void _maybeFail() {
    final error = writeError;
    if (error != null) throw error;
  }

  Expense _find(String id) => expenses.firstWhere((e) => e.id == id);

  Expense _with(Expense e, {ExpenseInput? input, bool? voided, String? reason, String? url, String? type}) {
    final i = input;
    final category = i == null ? null : cats.where((c) => c.id == i.categoryId).firstOrNull;
    return Expense(
      id: e.id,
      reference: e.reference,
      categoryId: i?.categoryId ?? e.categoryId,
      categoryName: category?.name ?? e.categoryName,
      description: i == null ? e.description : i.description,
      amount: i?.amount ?? e.amount,
      expenseDate: i?.expenseDate ?? e.expenseDate,
      paymentMethod: i?.paymentMethod ?? e.paymentMethod,
      warehouseId: i == null ? e.warehouseId : i.warehouseId,
      warehouseName: e.warehouseName,
      payee: i == null ? e.payee : i.payee,
      receiptNumber: i == null ? e.receiptNumber : i.receiptNumber,
      attachmentUrl: url ?? e.attachmentUrl,
      attachmentName: url == null ? e.attachmentName : 'receipt',
      attachmentType: type ?? e.attachmentType,
      status: voided == true ? ExpenseStatus.voided : e.status,
      voidReason: reason ?? e.voidReason,
      createdById: e.createdById,
      createdByName: e.createdByName,
      createdAt: e.createdAt,
      updatedByName: i == null ? e.updatedByName : 'Ada',
      updatedAt: i == null ? e.updatedAt : DateTime(2026, 10, 29),
    );
  }

  void _replace(Expense next) => expenses = [for (final e in expenses) e.id == next.id ? next : e];

  @override
  Future<List<Expense>> list() async => List.of(expenses);

  @override
  Future<Expense> get(String id) async => _find(id);

  @override
  Future<Expense> create(ExpenseInput input, {String? clientRef}) async {
    _maybeFail();
    created.add((input: input, clientRef: clientRef));
    final n = created.length;
    final e = _with(
      fixtureExpense('srv$n', reference: 'EXP-${n.toString().padLeft(4, '0')}', description: null),
      input: input,
    );
    expenses = [e, ...expenses];
    return e;
  }

  @override
  Future<Expense> update(String id, ExpenseInput input) async {
    _maybeFail();
    updated.add((id: id, input: input));
    final e = _with(_find(id), input: input);
    _replace(e);
    return e;
  }

  @override
  Future<Expense> voidExpense(String id, {required String reason}) async {
    _maybeFail();
    voided.add((id: id, reason: reason));
    final e = _with(_find(id), voided: true, reason: reason);
    _replace(e);
    return e;
  }

  @override
  Future<Expense> attach(String id, {required List<int> bytes, required String filename}) async {
    _maybeFail();
    attached.add((id: id, filename: filename, size: bytes.length));
    final pdf = filename.toLowerCase().endsWith('.pdf');
    final e = _with(_find(id), url: 'https://example.test/$filename', type: pdf ? 'application/pdf' : 'image/png');
    _replace(e);
    return e;
  }

  @override
  Future<Expense> removeAttachment(String id) async {
    final e = _find(id);
    final next = Expense(
      id: e.id,
      reference: e.reference,
      categoryId: e.categoryId,
      categoryName: e.categoryName,
      amount: e.amount,
      expenseDate: e.expenseDate,
      createdById: e.createdById,
    );
    _replace(next);
    return next;
  }

  @override
  Future<List<ExpenseCategory>> categories() async => List.of(cats);

  @override
  Future<ExpenseCategory> createCategory(String name, {double monthlyBudget = 0}) async {
    _maybeFail();
    final c = ExpenseCategory(id: 'cat${cats.length + 1}', name: name, monthlyBudget: monthlyBudget);
    cats = [...cats, c];
    return c;
  }

  @override
  Future<ExpenseCategory> updateCategory(String id, {String? name, double? monthlyBudget}) async {
    _maybeFail();
    final old = cats.firstWhere((c) => c.id == id);
    final c = ExpenseCategory(id: id, name: name ?? old.name, monthlyBudget: monthlyBudget ?? old.monthlyBudget, expenseCount: old.expenseCount);
    cats = [for (final x in cats) x.id == id ? c : x];
    return c;
  }

  @override
  Future<void> deleteCategory(String id) async {
    _maybeFail();
    cats = cats.where((c) => c.id != id).toList();
  }

  @override
  Future<List<RecurringExpense>> recurring() async => List.of(recurringList);

  @override
  Future<RecurringExpense> saveRecurring(String? id, Map<String, dynamic> fields) async {
    _maybeFail();
    savedRecurring.add((id: id, fields: fields));
    if (id != null) {
      final old = recurringList.firstWhere((r) => r.id == id);
      final next = RecurringExpense(
        id: id,
        categoryId: old.categoryId,
        categoryName: old.categoryName,
        description: old.description,
        amount: old.amount,
        frequency: old.frequency,
        nextDueDate: old.nextDueDate,
        active: fields['active'] as bool? ?? old.active,
        due: (fields['active'] as bool? ?? old.active) && old.due,
      );
      recurringList = [for (final r in recurringList) r.id == id ? next : r];
      return next;
    }
    final r = RecurringExpense(
      id: 'rec${recurringList.length + 1}',
      categoryId: fields['categoryId'] as String,
      categoryName: cats.firstWhere((c) => c.id == fields['categoryId']).name,
      description: fields['description'] as String,
      amount: (fields['amount'] as num).toDouble(),
      frequency: FrequencyX.fromApi(fields['frequency'] as String?),
      nextDueDate: DateTime.parse(fields['nextDueDate'] as String),
    );
    recurringList = [...recurringList, r];
    return r;
  }

  @override
  Future<void> deleteRecurring(String id) async => recurringList = recurringList.where((r) => r.id != id).toList();

  @override
  Future<Expense> recordRecurring(String id, {required DateTime dueDate, double? amount}) async {
    _maybeFail();
    recorded.add((id: id, dueDate: dueDate, amount: amount));
    final r = recurringList.firstWhere((x) => x.id == id);
    final e = await create(ExpenseInput(
      categoryId: r.categoryId,
      amount: amount ?? r.amount,
      expenseDate: DateTime.now(),
      description: r.description,
    ));
    recurringList = [
      for (final x in recurringList)
        x.id == id
            ? RecurringExpense(
                id: x.id,
                categoryId: x.categoryId,
                categoryName: x.categoryName,
                description: x.description,
                amount: x.amount,
                frequency: x.frequency,
                nextDueDate: DateTime.utc(x.nextDueDate.year, x.nextDueDate.month + 1, x.nextDueDate.day),
              )
            : x,
    ];
    return e;
  }
}

/// A month of business, as `GET /api/v1/dashboard` sends it to an Owner.
Map<String, dynamic> fixtureSummaryJson({DateTime? now}) {
  final n = now ?? DateTime.now();
  String day(int d) => '${n.year}-${n.month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  return {
    'bucket': 'day',
    'sales': {
      'total': 210000,
      'count': 3,
      'revenue': 200000,
      'cogs': 150000,
      'grossProfit': 50000,
      'margin': 25,
      'previous': {'total': 150000, 'count': 2, 'grossProfit': 40000},
      'change': 40,
      'grossProfitChange': 25,
      'trend': [
        {'bucket': day(1), 'sales': 70000, 'grossProfit': 20000},
        {'bucket': day(n.day), 'sales': 140000, 'grossProfit': 30000},
      ],
      'topProducts': [
        {'productId': 'p1', 'name': 'Golden Penny Rice 50kg', 'sku': 'R', 'unit': 'bag', 'units': 2, 'revenue': 140000, 'grossProfit': 30000},
        {'productId': 'p2', 'name': 'Peak Milk', 'sku': 'M', 'unit': 'carton', 'units': 4, 'revenue': 60000, 'grossProfit': 20000},
      ],
      'topCustomers': [
        {'customerId': 'c1', 'name': 'Ada Stores', 'total': 140000, 'count': 2},
      ],
      'byWarehouse': [
        {'warehouseId': 'w1', 'name': 'Main Warehouse', 'total': 210000, 'count': 3},
      ],
    },
    'purchases': {
      'total': 300000,
      'count': 1,
      'previous': {'total': 0},
      'change': null,
      'trend': [
        {'bucket': day(1), 'total': 300000},
      ],
    },
    'expenses': {
      'total': 20000,
      'count': 2,
      'previous': {'total': 10000},
      'change': 100,
      'trend': [
        {'bucket': day(n.day), 'total': 20000},
      ],
      'byCategory': [
        {'name': 'Rent', 'total': 20000},
      ],
    },
    'netProfit': {'value': 30000, 'previous': 30000, 'change': 0},
    'receivables': {'owed': 70000, 'overdue': 25000, 'parties': 1},
    'payables': {'owed': 100000, 'overdue': 0, 'parties': 1},
    'stock': {
      'valueAtCost': 900000,
      'valueAtRetail': 1200000,
      'lowStock': 1,
      'outOfStock': 0,
      'byWarehouse': [
        {'warehouseId': 'w1', 'name': 'Main Warehouse', 'units': 15, 'valueAtCost': 900000},
      ],
    },
  };
}

class FakeBusinessSummaryRepository implements BusinessSummaryRepository {
  FakeBusinessSummaryRepository([this.json]);

  /// What the server sends; [fixtureSummaryJson] when not given.
  Map<String, dynamic>? json;
  Object? error;
  final asked = <DashboardPeriod>[];

  @override
  Future<BusinessSummary> fetch(DashboardPeriod period, {DateTime? now}) async {
    asked.add(period);
    if (error != null) throw error!;
    return BusinessSummary.fromJson(period, json ?? fixtureSummaryJson(now: now));
  }
}

/// What `GET /api/v1/reports/<kind>` sends for October: three sales (one on
/// credit to Ada, a walk-in, one in Kano), two purchases, rent and fuel.
Map<String, dynamic> fixtureReportJson(ReportKind kind) => switch (kind) {
      ReportKind.sales => {
          'bucket': 'day',
          'totals': {
            'count': 3, 'units': 12, 'subtotal': 1380, 'discount': 30, 'tax': 35, 'total': 1385, 'paid': 1150,
            'outstanding': 235, 'revenue': 1350, 'cogs': 900, 'grossProfit': 450, 'margin': 33.33, 'averageSale': 461.67,
          },
          'voided': {'count': 1, 'total': 150},
          'byPeriod': [
            {'bucket': '2026-10-05', 'count': 1, 'units': 3, 'total': 385, 'paid': 150, 'outstanding': 235, 'revenue': 350, 'cogs': 250, 'grossProfit': 100, 'margin': 28.57},
            {'bucket': '2026-10-20', 'count': 1, 'units': 4, 'total': 600, 'paid': 600, 'outstanding': 0, 'revenue': 600, 'cogs': 400, 'grossProfit': 200, 'margin': 33.33},
            {'bucket': '2026-10-25', 'count': 1, 'units': 5, 'total': 400, 'paid': 400, 'outstanding': 0, 'revenue': 400, 'cogs': 250, 'grossProfit': 150, 'margin': 37.5},
          ],
          'byProduct': [
            {'productId': 'p1', 'name': 'Rice 50kg', 'sku': 'RICE', 'unit': 'bag', 'sales': 2, 'units': 6, 'revenue': 900, 'cogs': 600, 'grossProfit': 300, 'margin': 33.33},
            {'productId': 'p2', 'name': 'Semovita', 'sku': 'SEMO', 'unit': 'bag', 'sales': 2, 'units': 6, 'revenue': 480, 'cogs': 300, 'grossProfit': 180, 'margin': 37.5},
          ],
          'byCustomer': [
            {'customerId': null, 'name': 'Walk-in', 'count': 2, 'units': 9, 'total': 1000, 'paid': 1000, 'outstanding': 0, 'revenue': 1000, 'cogs': 650, 'grossProfit': 350, 'margin': 35},
            {'customerId': 'c1', 'name': 'Ada Stores', 'count': 1, 'units': 3, 'total': 385, 'paid': 150, 'outstanding': 235, 'revenue': 350, 'cogs': 250, 'grossProfit': 100, 'margin': 28.57},
          ],
          'byStaff': [
            {'userId': 'u1', 'name': 'Ada Obi', 'count': 2, 'units': 8, 'total': 785, 'paid': 550, 'outstanding': 235, 'revenue': 750, 'cogs': 500, 'grossProfit': 250, 'margin': 33.33},
            {'userId': 'u2', 'name': 'Sade Sales', 'count': 1, 'units': 4, 'total': 600, 'paid': 600, 'outstanding': 0, 'revenue': 600, 'cogs': 400, 'grossProfit': 200, 'margin': 33.33},
          ],
          'byWarehouse': [
            {'warehouseId': 'w1', 'name': 'Main Warehouse', 'count': 2, 'units': 7, 'total': 985, 'paid': 750, 'outstanding': 235, 'revenue': 950, 'cogs': 650, 'grossProfit': 300, 'margin': 31.58},
          ],
          'sales': [
            {'id': 's3', 'reference': 'INV-0005', 'saleDate': '2026-10-25T10:00:00.000Z', 'customerId': null, 'customer': 'Walk-in', 'warehouse': 'Kano', 'staff': 'Ada Obi', 'subtotal': 400, 'discount': 0, 'tax': 0, 'total': 400, 'paid': 400, 'outstanding': 0},
            {'id': 's2', 'reference': 'INV-0002', 'saleDate': '2026-10-19T23:30:00.000Z', 'customerId': null, 'customer': 'Walk-in', 'warehouse': 'Main Warehouse', 'staff': 'Sade Sales', 'subtotal': 600, 'discount': 0, 'tax': 0, 'total': 600, 'paid': 600, 'outstanding': 0},
            {'id': 's1', 'reference': 'INV-0001', 'saleDate': '2026-10-05T10:00:00.000Z', 'customerId': 'c1', 'customer': 'Ada Stores', 'warehouse': 'Main Warehouse', 'staff': 'Ada Obi', 'subtotal': 380, 'discount': 30, 'tax': 35, 'total': 385, 'paid': 150, 'outstanding': 235},
          ],
          'truncated': false,
          'people': [
            {'id': 'u1', 'name': 'Ada Obi'},
            {'id': 'u2', 'name': 'Sade Sales'},
          ],
        },
      ReportKind.purchases => {
          'bucket': 'day',
          'totals': {
            'count': 2, 'subtotal': 6350, 'discount': 0, 'tax': 0, 'total': 6350, 'paid': 1300, 'unpaid': 5050,
            'unitsOrdered': 80, 'unitsReceived': 50, 'orderedValue': 6350, 'receivedValue': 5000,
          },
          'byStatus': [
            {'status': 'pending', 'count': 1, 'total': 1350},
            {'status': 'received', 'count': 1, 'total': 5000},
          ],
          'byPeriod': [
            {'bucket': '2026-10-03', 'count': 1, 'total': 5000, 'paid': 1000, 'unpaid': 4000, 'unitsOrdered': 50, 'unitsReceived': 50, 'receivedValue': 5000},
            {'bucket': '2026-10-12', 'count': 1, 'total': 1350, 'paid': 300, 'unpaid': 1050, 'unitsOrdered': 30, 'unitsReceived': 0, 'receivedValue': 0},
          ],
          'bySupplier': [
            {'supplierId': 'sp1', 'name': 'Dangote Foods', 'count': 2, 'total': 6350, 'paid': 1300, 'unpaid': 5050, 'unitsOrdered': 80, 'unitsReceived': 50, 'receivedValue': 5000},
          ],
          'byWarehouse': [
            {'warehouseId': 'w1', 'name': 'Main Warehouse', 'count': 1, 'total': 5000, 'paid': 1000, 'unpaid': 4000, 'unitsOrdered': 50, 'unitsReceived': 50, 'receivedValue': 5000},
          ],
          'byProduct': [
            {'productId': 'p1', 'name': 'Rice 50kg', 'sku': 'RICE', 'unit': 'bag', 'purchases': 1, 'unitsOrdered': 50, 'unitsReceived': 50, 'orderedValue': 5000, 'averageCost': 100, 'minCost': 100, 'maxCost': 100},
          ],
          'purchases': [
            {'id': 'pu2', 'reference': 'PO-0004', 'orderDate': '2026-10-12T00:00:00.000Z', 'supplierId': 'sp1', 'supplier': 'Dangote Foods', 'warehouse': 'Kano', 'status': 'pending', 'total': 1350, 'paid': 300, 'unpaid': 1050},
            {'id': 'pu1', 'reference': 'PO-0001', 'orderDate': '2026-10-03T00:00:00.000Z', 'supplierId': 'sp1', 'supplier': 'Dangote Foods', 'warehouse': 'Main Warehouse', 'status': 'received', 'total': 5000, 'paid': 1000, 'unpaid': 4000},
          ],
          'truncated': false,
        },
      ReportKind.profitLoss => {
          'bucket': 'day',
          'profit': {
            'salesCount': 3, 'grossSales': 1380, 'discounts': 30, 'netSales': 1350, 'cogs': 900, 'grossProfit': 450,
            'grossMargin': 33.33, 'expenses': 250,
            'expensesByCategory': [
              {'categoryId': 'k1', 'name': 'Rent', 'total': 200, 'count': 1},
              {'categoryId': 'k2', 'name': 'Fuel', 'total': 50, 'count': 1},
            ],
            'netProfit': 200, 'netMargin': 14.81, 'taxCollected': 35,
          },
          'cash': {
            'in': {
              'sales': 1200, 'customerAccounts': 100, 'total': 1300,
              'byMethod': [
                {'method': 'cash', 'total': 1200},
                {'method': 'transfer', 'total': 100},
              ],
            },
            'out': {'purchases': 300, 'supplierAccounts': 1000, 'expenses': 250, 'total': 1550},
            'net': -250,
          },
          'byPeriod': [
            {'bucket': '2026-10-05', 'netSales': 350, 'cogs': 250, 'grossProfit': 100, 'expenses': 0, 'netProfit': 100, 'moneyIn': 0, 'moneyOut': 0},
            {'bucket': '2026-10-07', 'netSales': 0, 'cogs': 0, 'grossProfit': 0, 'expenses': 200, 'netProfit': -200, 'moneyIn': 0, 'moneyOut': 200},
          ],
        },
      ReportKind.stockMovements => {
          'totals': {'count': 3, 'unitsIn': 100, 'unitsOut': 7, 'net': 93},
          'byType': [
            {'type': 'adjustment', 'count': 1, 'unitsIn': 0, 'unitsOut': 3, 'net': -3},
            {'type': 'stock_in', 'count': 1, 'unitsIn': 100, 'unitsOut': 0, 'net': 100},
            {'type': 'stock_out', 'count': 1, 'unitsIn': 0, 'unitsOut': 4, 'net': -4},
          ],
          'byProduct': [
            {'productId': 'p1', 'name': 'Rice 50kg', 'sku': 'RICE', 'unit': 'bag', 'count': 3, 'unitsIn': 100, 'unitsOut': 7, 'net': 93, 'netValue': 9300},
          ],
          'byUser': [
            {'userId': 'u1', 'name': 'Ada Obi', 'count': 2, 'unitsIn': 100, 'unitsOut': 3, 'net': 97},
            {'userId': 'u2', 'name': 'Sade Sales', 'count': 1, 'unitsIn': 0, 'unitsOut': 4, 'net': -4},
          ],
          'movements': [
            {'id': 'm3', 'createdAt': '2026-10-20T09:00:00.000Z', 'type': 'stock_out', 'quantity': -4, 'previousStock': 97, 'newStock': 93, 'reason': 'Sold on INV-0002', 'productId': 'p1', 'product': 'Rice 50kg', 'sku': 'RICE', 'unit': 'bag', 'warehouseId': 'w1', 'warehouse': 'Main Warehouse', 'userId': 'u2', 'user': 'Sade Sales', 'source': 'sale', 'saleId': 's2', 'purchaseId': null, 'reference': 'INV-0002'},
            {'id': 'm2', 'createdAt': '2026-10-02T09:00:00.000Z', 'type': 'adjustment', 'quantity': -3, 'previousStock': 100, 'newStock': 97, 'reason': 'Damaged', 'productId': 'p1', 'product': 'Rice 50kg', 'sku': 'RICE', 'unit': 'bag', 'warehouseId': 'w1', 'warehouse': 'Main Warehouse', 'userId': 'u1', 'user': 'Ada Obi', 'source': 'manual', 'saleId': null, 'purchaseId': null, 'reference': null},
            {'id': 'm1', 'createdAt': '2026-10-01T09:00:00.000Z', 'type': 'stock_in', 'quantity': 100, 'previousStock': 0, 'newStock': 100, 'reason': null, 'productId': 'p1', 'product': 'Rice 50kg', 'sku': 'RICE', 'unit': 'bag', 'warehouseId': 'w1', 'warehouse': 'Main Warehouse', 'userId': 'u1', 'user': 'Ada Obi', 'source': 'manual', 'saleId': null, 'purchaseId': null, 'reference': null},
          ],
          'truncated': false,
          'people': [
            {'id': 'u1', 'name': 'Ada Obi'},
            {'id': 'u2', 'name': 'Sade Sales'},
          ],
        },
    };

class FakePeriodReportsRepository implements PeriodReportsRepository {
  FakePeriodReportsRepository([Map<ReportKind, Map<String, dynamic>>? json]) : json = json ?? {};

  /// What the server sends per report; [fixtureReportJson] when not given.
  final Map<ReportKind, Map<String, dynamic>> json;
  Object? error;
  final asked = <ReportQuery>[];

  @override
  Future<Map<String, dynamic>> fetch(ReportQuery q) async {
    asked.add(q);
    if (error != null) throw error!;
    return json[q.kind] ?? fixtureReportJson(q.kind);
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
  FakeSupplierPricesRepository? supplierPrices,
  FakeExpensesRepository? expenses,
  FakeBusinessSummaryRepository? summary,
  FakePeriodReportsRepository? reports,
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
      supplierPricesRepositoryProvider.overrideWithValue(supplierPrices ?? FakeSupplierPricesRepository()),
      expensesRepositoryProvider.overrideWithValue(expenses ?? FakeExpensesRepository()),
      businessSummaryRepositoryProvider.overrideWithValue(summary ?? FakeBusinessSummaryRepository()),
      periodReportsRepositoryProvider.overrideWithValue(reports ?? FakePeriodReportsRepository()),
    ];
