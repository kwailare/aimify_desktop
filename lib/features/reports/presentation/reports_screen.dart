import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../dashboard/data/dashboard_metrics.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../products/data/products_repository.dart';
import 'widgets/movement_trend_chart.dart';
import 'widgets/stock_health_chart.dart';
import 'widgets/stock_value_chart.dart';
import 'widgets/top_products_card.dart';

/// Inventory reports computed from the live products and stock ledger.
/// Valuation is current stock × price, worked out here — the backend has no
/// valuation or reporting endpoint yet — and per-warehouse breakdowns and
/// report exports aren't offered because stock isn't split by warehouse.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final cost = ref.watch(inventoryValueProvider);
    final retail = ref.watch(retailValueProvider);
    final units = ref.watch(unitsOnHandProvider);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Reports',
              subtitle: 'Inventory value, stock health and movement at a glance',
              actions: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Future.wait([
                      ref.read(productsProvider.notifier).refresh(),
                      ref.read(movementsProvider.notifier).refresh(),
                      ref.read(stockAlertsProvider.notifier).refresh(),
                    ]);
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (products.isLoading && !products.hasValue)
              const LoadingPanel(label: 'Loading reports…')
            else if (products.hasError && !products.hasValue)
              ErrorRetryCard(
                error: products.error!,
                onRetry: () => ref.read(productsProvider.notifier).refresh(),
              )
            else ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 156,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: 3,
                itemBuilder: (context, index) => switch (index) {
                  0 => StatCard(
                      label: 'Stock value at cost',
                      value: currencyFormat.format(cost),
                      caption: 'What the stock on hand cost',
                      icon: Icons.payments_outlined,
                    ),
                  1 => StatCard(
                      label: 'Stock value at selling price',
                      value: currencyFormat.format(retail),
                      caption: 'Potential margin ${currencyFormat.format(retail - cost)}',
                      icon: Icons.sell_outlined,
                      accentColor: const Color(0xFF6C63FF),
                    ),
                  _ => StatCard(
                      label: 'Units on hand',
                      value: '$units',
                      icon: Icons.inventory_2_outlined,
                      accentColor: const Color(0xFF2F8F5B),
                    ),
                },
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  const cards = [
                    StockValueChart(),
                    MovementTrendChart(),
                    StockHealthChart(),
                    TopProductsCard(),
                  ];

                  if (!wide) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final card in cards) ...[card, const SizedBox(height: 16)],
                      ]..removeLast(),
                    );
                  }

                  // A fixed tile height rather than an aspect ratio — aspect-
                  // ratio tiles squeeze shorter as columns are added, which
                  // has clipped chart content at ordinary widths.
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
          ],
        ),
      ),
    );
  }
}
