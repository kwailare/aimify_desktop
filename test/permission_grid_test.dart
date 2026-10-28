// Per-action permissions from the Owner's Roles & permissions grid: each
// button checks exactly the action it performs (add, edit, archive/restore,
// disable), and a module's data is only fetched by someone who can view it.

import 'package:aimify_desktop/features/auth/domain/auth_models.dart';
import 'package:aimify_desktop/features/auth/presentation/auth_controller.dart';
import 'package:aimify_desktop/features/customers/presentation/customers_screen.dart';
import 'package:aimify_desktop/features/products/data/products_repository.dart';
import 'package:aimify_desktop/features/products/domain/product.dart';
import 'package:aimify_desktop/features/products/presentation/products_screen.dart';
import 'package:aimify_desktop/features/warehouses/presentation/warehouses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_repositories.dart';

class _Auth extends AuthController {
  _Auth(this.permissions);

  List<String> permissions;

  MeResponse _me() => MeResponse(
        user: const AuthUser(id: 'u1', name: 'Tunde', email: 'tunde@company.com'),
        organization: Organization(
          id: 'o1',
          name: 'Obi Distribution Ltd',
          industry: 'Wholesale',
          currency: 'NGN',
          warehouseName: 'Main Warehouse',
          subscriptionStatus: 'trial',
          setupCompletedAt: DateTime(2026, 10, 1),
        ),
        role: 'Sales Staff',
        permissions: permissions,
      );

  @override
  Future<MeResponse?> build() async => _me();

  /// What a `/me` refresh does after the Owner changes the grid.
  void grant(List<String> next) {
    permissions = next;
    state = AsyncData(_me());
  }
}

class _CountingProducts extends FakeProductsRepository {
  _CountingProducts(super.products);

  int listCalls = 0;

  @override
  Future<List<Product>> list() {
    listCalls++;
    return super.list();
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, List<Override> overrides) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: screen)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

VoidCallback? _onPressed(WidgetTester tester, Finder finder) {
  final widget = tester.widget(finder);
  return switch (widget) {
    IconButton(:final onPressed) => onPressed,
    ButtonStyleButton(:final onPressed) => onPressed,
    _ => throw StateError('not a button: $widget'),
  };
}

Finder _icon(IconData icon) => find.widgetWithIcon(IconButton, icon).first;
Finder _labelled(String label) => find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()).first;

void main() {
  group('products', () {
    testWidgets('Add without Edit: can add, can\'t edit or archive', (tester) async {
      await _pump(tester, const ProductsScreen(), [
        authControllerProvider.overrideWith(() => _Auth(['products.view', 'products.create', 'catalog.view'])),
        ...fakeDataOverrides(),
      ]);
      expect(_onPressed(tester, _labelled('Add product')), isNotNull);
      expect(_onPressed(tester, _icon(Icons.edit_outlined)), isNull);
      expect(_onPressed(tester, _icon(Icons.archive_outlined)), isNull);
    });

    testWidgets('Edit without Add: can edit, can\'t add', (tester) async {
      await _pump(tester, const ProductsScreen(), [
        authControllerProvider.overrideWith(() => _Auth(['products.view', 'products.edit', 'catalog.view'])),
        ...fakeDataOverrides(),
      ]);
      expect(_onPressed(tester, _labelled('Add product')), isNull);
      expect(_onPressed(tester, _labelled('Bulk import')), isNull);
      expect(_onPressed(tester, _icon(Icons.edit_outlined)), isNotNull);
      expect(_onPressed(tester, _icon(Icons.archive_outlined)), isNull);
    });

    testWidgets('Archive alone: can archive, nothing else', (tester) async {
      await _pump(tester, const ProductsScreen(), [
        authControllerProvider.overrideWith(() => _Auth(['products.view', 'products.archive'])),
        ...fakeDataOverrides(),
      ]);
      expect(_onPressed(tester, _labelled('Add product')), isNull);
      expect(_onPressed(tester, _icon(Icons.edit_outlined)), isNull);
      expect(_onPressed(tester, _icon(Icons.archive_outlined)), isNotNull);
    });
  });

  group('warehouses', () {
    testWidgets('Edit without Disable or Add', (tester) async {
      await _pump(tester, const WarehousesScreen(), [
        authControllerProvider.overrideWith(() => _Auth(['warehouses.view', 'warehouses.edit'])),
        ...fakeDataOverrides(),
      ]);
      expect(_onPressed(tester, _labelled('Add warehouse')), isNull);
      expect(_onPressed(tester, _labelled('Edit')), isNotNull);
      expect(_onPressed(tester, _labelled('Disable')), isNull);
    });

    testWidgets('Disable without Edit', (tester) async {
      await _pump(tester, const WarehousesScreen(), [
        authControllerProvider.overrideWith(() => _Auth(['warehouses.view', 'warehouses.disable'])),
        ...fakeDataOverrides(),
      ]);
      expect(_onPressed(tester, _labelled('Edit')), isNull);
      expect(_onPressed(tester, _labelled('Disable')), isNotNull);
    });
  });

  group('customers', () {
    testWidgets('Archive without Add or Edit', (tester) async {
      await _pump(tester, const CustomersScreen(), [
        authControllerProvider.overrideWith(() => _Auth(['customers.view', 'customers.archive'])),
        ...fakeDataOverrides(parties: FakePartiesRepository(customers: [fixtureParty('c1')])),
      ]);
      expect(_onPressed(tester, _labelled('Add customer')), isNull);
      expect(_onPressed(tester, _icon(Icons.edit_outlined)), isNull);
      expect(_onPressed(tester, _icon(Icons.archive_outlined)), isNotNull);
    });

    testWidgets('Add and Edit without Archive', (tester) async {
      await _pump(tester, const CustomersScreen(), [
        authControllerProvider.overrideWith(
          () => _Auth(['customers.view', 'customers.create', 'customers.edit']),
        ),
        ...fakeDataOverrides(parties: FakePartiesRepository(customers: [fixtureParty('c1')])),
      ]);
      expect(_onPressed(tester, _labelled('Add customer')), isNotNull);
      expect(_onPressed(tester, _icon(Icons.edit_outlined)), isNotNull);
      expect(_onPressed(tester, _icon(Icons.archive_outlined)), isNull);
    });
  });

  group('data is only fetched by people who can view it', () {
    test('no products.view: the product list is never requested, and appears once granted', () async {
      final products = _CountingProducts([fixtureProduct('1')]);
      final auth = _Auth(['stock.view']);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => auth),
          ...fakeDataOverrides(products: products),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);
      expect(await container.read(productsProvider.future), isEmpty);
      await container.read(productsProvider.notifier).refresh();
      expect(products.listCalls, 0);

      auth.grant(['stock.view', 'products.view']);
      final granted = await container.read(productsProvider.future);
      expect(granted.map((p) => p.id), ['1']);
      expect(products.listCalls, 1);
    });
  });
}
