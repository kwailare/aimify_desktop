import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../../products/data/products_repository.dart';
import '../../../warehouses/data/warehouses_repository.dart';

/// The desktop half of the setup wizard. The website covers the company
/// profile, organization, trial and download; the products, opening
/// inventory and team steps belong here. Each step ticks itself off from
/// real data, and the whole card disappears once setup is complete.
class SetupChecklistCard extends ConsumerWidget {
  const SetupChecklistCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehousesProvider);
    final products = ref.watch(productsProvider);
    final movements = ref.watch(movementsProvider);

    // Don't flash an all-unchecked list while the first loads are running.
    if (!warehouses.hasValue || !products.hasValue || !movements.hasValue) {
      return const SizedBox.shrink();
    }

    final hasWarehouse = warehouses.value!.any((w) => w.isActive);
    final hasProduct = products.value!.isNotEmpty;
    final hasStock = movements.value!.isNotEmpty || products.value!.any((p) => p.currentStock > 0);
    final teamSize = ref.watch(authControllerProvider).valueOrNull?.plan?.usage.users ?? 1;
    final hasTeam = teamSize > 1;

    final steps = [
      _Step(
        title: 'Create a warehouse',
        detail: 'Stock is recorded against a warehouse.',
        done: hasWarehouse,
        actionLabel: 'Open warehouses',
        onAction: () => context.go('/warehouses'),
      ),
      _Step(
        title: 'Add your first product',
        detail: 'SKU, name, unit, prices and a reorder level.',
        done: hasProduct,
        actionLabel: 'Open products',
        onAction: () => context.go('/products'),
      ),
      _Step(
        title: 'Record your opening stock',
        detail: 'A stock-in movement sets what is on the shelves today.',
        done: hasStock,
        actionLabel: 'Open inventory',
        onAction: () => context.go('/inventory'),
      ),
      _Step(
        title: 'Invite your team',
        detail: 'Owners and administrators invite people on the Aimify website.',
        done: hasTeam,
        actionLabel: 'Open Team page',
        onAction: () => launchUrl(Uri.parse(ApiConstants.teamUrl)),
      ),
    ];

    if (steps.every((s) => s.done)) return const SizedBox.shrink();

    final doneCount = steps.where((s) => s.done).length;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Finish setting up',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text('$doneCount of ${steps.length} done', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: doneCount / steps.length,
              minHeight: 6,
              backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 14),
          for (final step in steps) _StepRow(step: step),
        ],
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.title,
    required this.detail,
    required this.done,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String detail;
  final bool done;
  final String actionLabel;
  final VoidCallback onAction;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF2F8F5B);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            step.done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: step.done ? green : theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: step.done ? TextDecoration.lineThrough : null,
                    color: step.done ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null,
                  ),
                ),
                Text(
                  step.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                if (!step.done)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: step.onAction,
                    child: Text(step.actionLabel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
