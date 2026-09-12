// Overflow regression coverage for the screens added in the multi-
// warehouse pivot (Warehouses, Staff, Reports). The same class of bug hit
// twice already this session (dashboard bento grid, then the warehouse
// card grid) — both were narrow-width Row/Column overflows that only
// showed up once real layout ran, not from reading the code. Cheap
// insurance to catch the next one the same way.

import 'package:aimify_desktop/core/theme/app_theme.dart';
import 'package:aimify_desktop/features/credits_debts/presentation/credits_debts_screen.dart';
import 'package:aimify_desktop/features/inventory/presentation/inventory_screen.dart';
import 'package:aimify_desktop/features/products/presentation/products_screen.dart';
import 'package:aimify_desktop/features/reports/presentation/reports_screen.dart';
import 'package:aimify_desktop/features/staff/presentation/staff_screen.dart';
import 'package:aimify_desktop/features/warehouses/presentation/warehouses_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final screens = {
    'Warehouses': const WarehousesScreen(),
    'Staff': const StaffScreen(),
    'Reports': const ReportsScreen(),
    'Credits & Debts': const CreditsDebtsScreen(),
    'Products': const ProductsScreen(),
    'Inventory': const InventoryScreen(),
  };

  // Narrower than the other screens' sweep: this is exactly the width
  // (452 = 500 - Scaffold padding) that broke both Products and Inventory
  // once their toolbars grew enough filter chips to wrap onto several
  // lines — worth keeping as an explicit checkpoint, not just the general
  // sweep below.
  for (final width in [452.0, 360.0, 600.0, 900.0, 1280.0]) {
    testWidgets('Products has no overflow at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: AppTheme.light(), home: const ProductsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      expect(tester.takeException(), isNull);
    });
  }

  for (final entry in screens.entries) {
    for (final width in [360.0, 600.0, 900.0, 1280.0]) {
      testWidgets('${entry.key} has no overflow at width $width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: entry.value,
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(tester.takeException(), isNull);
      });
    }
  }
}
