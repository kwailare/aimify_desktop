// Permission lists for fake `/me` responses.
//
// Since the per-organization permission grid, `/me` sends one key per module
// action (`products.create`, `stock.in`...) and every read is permissioned
// (`products.view`...). Tests written before that describe a person with the
// older combined keys; [asGranted] turns such a list into what the server
// would send today for the same person, so the tests keep their meaning.

const _viewsEveryoneHadBefore = [
  'products.view',
  'catalog.view',
  'stock.view',
  'warehouses.view',
];

const _expansions = {
  'products.write': ['products.create', 'products.edit'],
  'catalog.write': ['catalog.create', 'catalog.delete'],
  'warehouses.manage': ['warehouses.create', 'warehouses.edit', 'warehouses.disable'],
  'stock.adjust': ['stock.in', 'stock.adjust'],
  'customers.read': ['customers.view'],
  'customers.write': ['customers.create', 'customers.edit', 'customers.archive'],
  'suppliers.read': ['suppliers.view'],
  'suppliers.write': ['suppliers.create', 'suppliers.edit', 'suppliers.archive'],
};

/// [legacy] described with the older combined keys, as the server sends it
/// now. Keys that didn't change (`stock.out`, `products.archive`,
/// `credit.record`, `team.manage`, `setup.complete`) pass through.
List<String> asGranted(List<String> legacy) => {
      ..._viewsEveryoneHadBefore,
      for (final key in legacy) ...(_expansions[key] ?? [key]),
    }.toList();

const _allPurchases = ['purchases.view', 'purchases.create', 'purchases.receive', 'purchases.cancel'];

const _allSales = ['sales.view', 'sales.create', 'sales.discount', 'sales.override', 'sales.void'];

/// The server's default grid for each role (no customisation), including the
/// fixed `team.manage`/`setup.complete` for Owners and Administrators.
List<String> defaultPermissionsFor(String role) => switch (role) {
      'Owner' || 'Administrator' => asGranted([
          'products.write', 'products.archive', 'catalog.write', 'warehouses.manage',
          'stock.out', 'stock.adjust', 'customers.read', 'customers.write',
          'suppliers.read', 'suppliers.write', 'credit.record', 'team.manage', 'setup.complete', 'customers.types',
          ..._allPurchases, ..._allSales,
        ]),
      'Warehouse Manager' => asGranted([
          'products.write', 'products.archive', 'catalog.write', 'warehouses.manage',
          'stock.out', 'stock.adjust', 'suppliers.read', 'suppliers.write',
          ..._allPurchases,
        ]),
      'Inventory Staff' => asGranted(['products.write', 'catalog.write', 'stock.out', 'stock.adjust']),
      'Sales Staff' => asGranted(['stock.out', 'customers.read', 'customers.write', 'sales.view', 'sales.create']),
      'Accountant / Finance' => asGranted(['customers.read', 'suppliers.read', 'credit.record', 'purchases.view', 'sales.view']),
      _ => const [],
    };
