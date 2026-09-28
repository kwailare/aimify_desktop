import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/async_state.dart';
import '../../../shared/widgets/manage_billing_link.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../data/warehouses_repository.dart';
import '../domain/warehouse.dart';
import 'warehouse_form_dialog.dart';

/// Warehouses, live from `/api/v1/warehouses`. Creating, editing and
/// disabling need `warehouses.manage`. There is no delete — a warehouse is
/// disabled instead, because past stock movements point at it — and the
/// plan caps how many can be active at once (the default plan allows one).
class WarehousesScreen extends ConsumerWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(warehousesProvider);
    final warehouses = ref.watch(warehouseListProvider);
    final canManage = hasPermission(ref, Permissions.warehousesManage);
    final me = ref.watch(authControllerProvider).valueOrNull;
    final plan = me?.plan;
    final atWarehouseCap = plan?.warehousesAtCap ?? false;
    final isOwner = me?.role == 'Owner';
    final activeCount = warehouses.where((w) => w.isActive).length;

    var subtitle = '$activeCount active warehouse(s)';
    if (plan?.limits.warehouses != null) {
      subtitle += ' · plan: ${plan!.usage.warehouses}/${plan.limits.warehouses} warehouses used';
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Warehouses',
              subtitle: subtitle,
              actions: [
                if (atWarehouseCap && isOwner) const ManageBillingLink(),
                Tooltip(
                  message: !canManage
                      ? "Your role can't manage warehouses"
                      : atWarehouseCap
                          ? 'Your plan has reached its warehouse limit — disable one to free a slot'
                          : '',
                  child: ElevatedButton.icon(
                    onPressed: (!canManage || atWarehouseCap)
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (_) => const WarehouseFormDialog(),
                            ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add warehouse'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (state.isLoading && !state.hasValue)
              const LoadingPanel(label: 'Loading warehouses…')
            else if (state.hasError && !state.hasValue)
              ErrorRetryCard(
                error: state.error!,
                onRetry: () => ref.read(warehousesProvider.notifier).refresh(),
              )
            else if (warehouses.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      canManage
                          ? 'No warehouses yet. Add one to start recording stock.'
                          : 'No warehouses yet. Ask an owner or administrator to add one.',
                    ),
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 420,
                  mainAxisExtent: 244,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: warehouses.length,
                itemBuilder: (context, index) => _WarehouseCard(
                  warehouse: warehouses[index],
                  canManage: canManage,
                  atCap: atWarehouseCap,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseCard extends ConsumerWidget {
  const _WarehouseCard({required this.warehouse, required this.canManage, required this.atCap});

  final Warehouse warehouse;
  final bool canManage;
  final bool atCap;

  Future<void> _setActive(BuildContext context, WidgetRef ref, bool active) async {
    try {
      await ref.read(warehousesProvider.notifier).edit(
        warehouse.id,
        {'status': active ? 'active' : 'inactive'},
      );
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _confirmDisable(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disable warehouse?'),
        content: Text(
          '${warehouse.name} will no longer be available for new stock movements. Its history is '
          'kept, and disabling it frees one warehouse slot on your plan. You can enable it again '
          'later if your plan has room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) await _setActive(context, ref, false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    Widget detail(IconData icon, String? text, String fallback) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(icon, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text ?? fallback,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: text == null ? muted : null),
                ),
              ),
            ],
          ),
        );

    return Opacity(
      opacity: warehouse.isActive ? 1 : 0.6,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      warehouse.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusPill(
                    label: warehouse.isActive ? 'Active' : 'Disabled',
                    tone: warehouse.isActive ? StatusTone.positive : StatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              detail(Icons.place_outlined, warehouse.address, 'No address'),
              detail(Icons.person_outline, warehouse.managerName, 'No manager'),
              detail(Icons.phone_outlined, warehouse.phone, 'No phone'),
              const Spacer(),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: !canManage
                        ? null
                        : () => showDialog(
                              context: context,
                              builder: (_) => WarehouseFormDialog(warehouse: warehouse),
                            ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                  if (warehouse.isActive)
                    TextButton.icon(
                      onPressed: !canManage ? null : () => _confirmDisable(context, ref),
                      icon: const Icon(Icons.pause_circle_outline, size: 16),
                      label: const Text('Disable'),
                    )
                  else
                    Tooltip(
                      message: atCap ? 'Your plan has no free warehouse slot' : '',
                      child: TextButton.icon(
                        onPressed: (!canManage || atCap) ? null : () => _setActive(context, ref, true),
                        icon: const Icon(Icons.play_circle_outline, size: 16),
                        label: const Text('Enable'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
