import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../dashboard/data/dashboard_metrics.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../products/data/products_repository.dart';
import '../data/period_reports.dart';
import '../data/valuation_report.dart';
import 'period_report_tab.dart';
import 'valuation_tab.dart';
import 'widgets/movement_trend_chart.dart';
import 'widgets/stock_health_chart.dart';
import 'widgets/stock_value_chart.dart';
import 'widgets/top_products_card.dart';

enum _ReportTab { overview, valuation, sales, purchases, profitLoss, stockHistory }

extension on _ReportTab {
  String get label => switch (this) {
        _ReportTab.overview => 'Overview',
        _ReportTab.valuation => 'Valuation',
        _ReportTab.sales => 'Sales',
        _ReportTab.purchases => 'Purchases',
        _ReportTab.profitLoss => 'Profit & loss',
        _ReportTab.stockHistory => 'Stock history',
      };

  ReportKind? get kind => switch (this) {
        _ReportTab.sales => ReportKind.sales,
        _ReportTab.purchases => ReportKind.purchases,
        _ReportTab.profitLoss => ReportKind.profitLoss,
        _ReportTab.stockHistory => ReportKind.stockMovements,
        _ => null,
      };
}

/// Reports. Overview charts are worked out from the live products and stock
/// ledger; the Valuation tab is the server's valuation report, by product,
/// category or warehouse; Sales, Purchases, Profit & loss and Stock history
/// are the server's period reports, with filters, Print / PDF and Excel.
/// Each tab shows only for someone who may see its module.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _ReportTab? _tab;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      for (final t in _ReportTab.values)
        if (t.kind == null ? ref.watch(canSeeValuationProvider) : ref.watch(canSeeReportProvider(t.kind!))) t,
    ];
    final tab = tabs.contains(_tab) ? _tab! : tabs.firstOrNull;
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
              subtitle: 'Sales, purchases, profit, spending and stock for any period',
              actions: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Future.wait([
                      ref.read(productsProvider.notifier).refresh(),
                      ref.read(movementsProvider.notifier).refresh(),
                      ref.read(stockAlertsProvider.notifier).refresh(),
                    ]);
                    ref.invalidate(valuationReportProvider);
                    ref.invalidate(reportJsonProvider);
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (tab == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('There are no reports you have permission to see.')),
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_ReportTab>(
                    key: const Key('reports-tabs'),
                    showSelectedIcon: false,
                    segments: [for (final t in tabs) ButtonSegment(value: t, label: Text(t.label))],
                    selected: {tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (tab.kind != null)
                PeriodReportTab(key: ValueKey(tab), kind: tab.kind!)
              else if (tab == _ReportTab.valuation)
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
          ],
        ),
      ),
    );
  }
}
