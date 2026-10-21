import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../dashboard/data/dashboard_metrics.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../products/data/products_repository.dart';
import '../data/valuation_report.dart';
import 'valuation_tab.dart';
import 'widgets/movement_trend_chart.dart';
import 'widgets/stock_health_chart.dart';
import 'widgets/stock_value_chart.dart';
import 'widgets/top_products_card.dart';

enum _ReportTab { overview, valuation }

/// Inventory reports. Overview charts are worked out from the live products
/// and stock ledger; the Valuation tab is the server's valuation report, by
/// product, category or warehouse. Excel/PDF export comes later.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _ReportTab _tab = _ReportTab.overview;

  @override
  Widget build(BuildContext context) {
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
                    ref.invalidate(valuationReportProvider);
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_ReportTab>(
                key: const Key('reports-tabs'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _ReportTab.overview, label: Text('Overview')),
                  ButtonSegment(value: _ReportTab.valuation, label: Text('Valuation')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 20),
            if (_tab == _ReportTab.valuation)
              const ValuationTab()
            else if (products.isLoading && !products.hasValue)
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
