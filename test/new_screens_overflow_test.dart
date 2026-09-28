// Overflow regression coverage for every module screen, at the widths that
// have broken layouts before (narrow toolbars that wrap, fixed-height card
// grids). Real layout has to run to catch these — reading the code doesn't.
//
// The screens run against in-memory fake repositories (see
// fakes/fake_repositories.dart), so the real notifiers and the real tables
// are exercised with data on screen, not empty states.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/credits_debts/presentation/credits_debts_screen.dart';
import 'package:aimify_desktop/features/customers/presentation/customers_screen.dart';
import 'package:aimify_desktop/features/expenses/presentation/expenses_screen.dart';
import 'package:aimify_desktop/features/inventory/data/inventory_repository.dart';
import 'package:aimify_desktop/features/inventory/domain/stock_movement.dart';
import 'package:aimify_desktop/features/parties/domain/party.dart';
import 'package:aimify_desktop/features/inventory/presentation/inventory_screen.dart';
import 'package:aimify_desktop/features/products/presentation/products_screen.dart';
import 'package:aimify_desktop/features/purchases/presentation/purchases_screen.dart';
import 'package:aimify_desktop/features/reports/presentation/reports_screen.dart';
import 'package:aimify_desktop/features/suppliers/presentation/suppliers_screen.dart';
import 'package:aimify_desktop/features/warehouses/presentation/warehouses_screen.dart';
import 'package:aimify_desktop/shared/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';

class _OwnerAuthController extends AuthController {
  @override
  Future<MeResponse?> build() async => const MeResponse(
        user: AuthUser(id: 'u1', name: 'Ada Obi', email: 'ada@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
        ),
        role: 'Owner',
        permissions: [
          'products.write',
          'products.archive',
          'catalog.write',
          'warehouses.manage',
          'stock.out',
          'stock.adjust',
          'customers.read',
          'customers.write',
          'suppliers.read',
          'suppliers.write',
          'credit.record',
        ],
        plan: Plan(
          name: 'Full Access',
          limits: PlanLimits(warehouses: 1),
          usage: PlanUsage(users: 1, warehouses: 1, products: 4),
        ),
      );
}

void main() {
  // Tax on: the products table then shows a second "incl. VAT" line under
  // every selling price, so the taller rows are covered by the sweep below.
  setUpAll(() => updateLocaleFormatsFromOrg(taxRate: 7.5, taxName: 'VAT'));
  tearDownAll(() => updateLocaleFormatsFromOrg(taxRate: 0));

  final screens = <String, Widget>{
    'Warehouses': const WarehousesScreen(),
    'Reports': const ReportsScreen(),
    'Credits & Debts': const CreditsDebtsScreen(),
    'Products': const ProductsScreen(),
    'Inventory': const InventoryScreen(),
    'Purchases': const PurchasesScreen(),
    'Suppliers': const SuppliersScreen(),
    'Customers': const CustomersScreen(),
    'Expenses': const ExpensesScreen(),
  };

  final products = FakeProductsRepository([
    fixtureProduct('1', name: 'A product with a rather long name to test ellipsis', stock: 40),
    fixtureProduct('2', name: 'Low stock rice', stock: 3, min: 5, category: 'Grains'),
    fixtureProduct('3', name: 'Out of stock oil', stock: 0, category: 'Oils'),
    fixtureProduct('4', name: 'Plenty of sugar', stock: 500, category: 'Groceries'),
  ]);
  final inventory = FakeInventoryRepository(
    movementRows: [
      StockMovement(
        id: 'm1',
        productId: '1',
        warehouseId: 'w1',
        userId: 'u1',
        type: StockMovementType.stockIn,
        quantity: 40,
        reason: 'Opening stock',
        previousStock: 0,
        newStock: 40,
        createdAt: DateTime.now(),
      ),
      StockMovement(
        id: 'm2',
        productId: '3',
        warehouseId: 'w1',
        userId: 'someone-else',
        type: StockMovementType.stockOut,
        quantity: -12,
        previousStock: 12,
        newStock: 0,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ],
    alertRows: StockAlerts(
      lowStock: [fixtureProduct('2', name: 'Low stock rice', stock: 3, min: 5)],
      outOfStock: [fixtureProduct('3', name: 'Out of stock oil', stock: 0)],
    ),
  );

  final parties = FakePartiesRepository(
    customers: [
      fixtureParty('c1', name: 'Blessing Retail Store and General Merchants Limited', balance: 45000, creditLimit: 50000),
      fixtureParty('c2', name: 'Kingsway Provisions', balance: 0, creditLimit: 500000),
    ],
    suppliers: [
      fixtureParty('s1', type: PartyType.supplier, name: 'Golden Grains Distributors', balance: 145000),
      fixtureParty('s2', type: PartyType.supplier, name: 'Coastal Oils', balance: 0),
    ],
  );

  // 452 is 500 minus the page padding — the width that broke Products and
  // Inventory once their toolbars wrapped onto several lines.
  for (final entry in screens.entries) {
    for (final width in [452.0, 360.0, 600.0, 900.0, 1280.0]) {
      testWidgets('${entry.key} has no overflow at width $width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_OwnerAuthController.new),
              ...fakeDataOverrides(products: products, inventory: inventory, parties: parties),
            ],
            child: MaterialApp(theme: AppTheme.light(), home: entry.value),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(tester.takeException(), isNull);
      });
    }
  }
}
