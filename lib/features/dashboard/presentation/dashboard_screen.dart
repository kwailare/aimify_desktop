import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/section_header.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/dashboard_hero.dart';
import 'widgets/low_stock_watchlist_card.dart';
import 'widgets/metric_bento_grid.dart';
import 'widgets/recent_activity_card.dart';
import 'widgets/setup_checklist_card.dart';

/// Home screen. [DashboardHero] (greeting, organization, subscription) comes
/// straight from `GET /api/v1/me`; everything below it is derived from the
/// live products, warehouses, alerts and stock ledger — see
/// `data/dashboard_metrics.dart`.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            authState.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => const _ErrorBanner(
                message: "Couldn't load your account. Check your connection and try again.",
              ),
              data: (me) {
                if (me == null) {
                  return const _ErrorBanner(
                    message: 'Your session could not be verified. Please sign in again.',
                  );
                }
                return DashboardHero(me: me);
              },
            ),
            const SizedBox(height: 32),
            const SetupChecklistCard(),
            const SectionHeader(
              title: 'Inventory snapshot',
              subtitle: 'Stock value, alerts and warehouses at a glance',
            ),
            const SizedBox(height: 16),
            const MetricBentoGrid(),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 860) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RecentActivityCard(),
                      SizedBox(height: 16),
                      LowStockWatchlistCard(),
                    ],
                  );
                }
                return const IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: RecentActivityCard()),
                      SizedBox(width: 16),
                      Expanded(flex: 5, child: LowStockWatchlistCard()),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.error.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
