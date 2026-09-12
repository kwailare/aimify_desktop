import 'package:flutter/material.dart';

import '../../../shared/widgets/mock_data_badge.dart';
import '../../../shared/widgets/section_header.dart';
import 'widgets/inventory_value_chart.dart';
import 'widgets/low_stock_by_warehouse_card.dart';
import 'widgets/movement_trend_chart.dart';
import 'widgets/purchase_spend_chart.dart';

/// Admin-only analytics. Every chart here is derived from the same MOCK
/// module data as the rest of the app — see `data/report_metrics.dart`.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Reports',
              subtitle: 'Inventory, stock movement and purchasing at a glance',
              badge: MockDataBadge(),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final cards = const [
                  InventoryValueChart(),
                  MovementTrendChart(),
                  PurchaseSpendChart(),
                  LowStockByWarehouseCard(),
                ];

                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final card in cards) ...[card, const SizedBox(height: 16)],
                    ]..removeLast(),
                  );
                }

                // A fixed tile height rather than an aspect ratio — see the
                // dashboard's bento grid for why aspect-ratio tiles are
                // risky here: they squeeze shorter as columns are added,
                // which has clipped chart content at ordinary widths.
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 560,
                    mainAxisExtent: 400,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (context, index) => cards[index],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
