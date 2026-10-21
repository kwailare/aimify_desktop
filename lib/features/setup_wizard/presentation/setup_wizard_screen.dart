import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_exception.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../../shared/widgets/aimify_wordmark.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/stock_movement.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_form_dialog.dart';
import '../../products/presentation/widgets/bulk_import_dialog.dart';
import '../../team/data/team_repository.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../../warehouses/domain/warehouse.dart';
import '../../warehouses/presentation/warehouse_form_dialog.dart';
import '../data/setup_wizard_state.dart';

const _green = Color(0xFF2F8F5B);

/// The guided setup: warehouse, products, opening stock, team and
/// subscription, one screen at a time. The website already covered the
/// company profile, first warehouse and trial; this finishes the rest of the
/// proposal's flow. Every step can be skipped, and "Finish later" closes the
/// wizard until the app is next started.
class SetupWizardScreen extends ConsumerWidget {
  const SetupWizardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepState = ref.watch(setupWizardStepProvider);
    final me = ref.watch(authControllerProvider).valueOrNull;
    final theme = Theme.of(context);

    if (!stepState.hasValue || me?.organization == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final step = stepState.value!;
    final done = _stepsDone(ref);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 20, 8),
              child: Row(
                children: [
                  const AimifyWordmark(fontSize: 20),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Set up ${me!.organization!.name}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('setup-finish-later'),
                    onPressed: () {
                      ref.read(setupWizardDismissedProvider.notifier).state = true;
                      context.go('/');
                    },
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('Finish later'),
                  ),
                ],
              ),
            ),
            _StepRail(current: step, done: done),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: switch (step) {
                      SetupStep.warehouse => const _WarehouseStep(),
                      SetupStep.products => const _ProductsStep(),
                      SetupStep.openingStock => const _OpeningStockStep(),
                      SetupStep.team => const _TeamStep(),
                      SetupStep.subscription => const _SubscriptionStep(),
                    },
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            _Footer(step: step),
          ],
        ),
      ),
    );
  }

  /// Which steps already have real data behind them, the same rules the
  /// dashboard's setup card uses.
  static Set<SetupStep> _stepsDone(WidgetRef ref) {
    final warehouses = ref.watch(warehouseListProvider);
    final products = ref.watch(productListProvider);
    final movements = ref.watch(movementsProvider).valueOrNull ?? const [];
    final team = ref.watch(teamProvider).valueOrNull;
    final usersOnPlan = ref.watch(authControllerProvider).valueOrNull?.plan?.usage.users ?? 1;

    return {
      if (warehouses.any((w) => w.isActive)) SetupStep.warehouse,
      if (products.isNotEmpty) SetupStep.products,
      if (movements.isNotEmpty || products.any((p) => p.currentStock > 0)) SetupStep.openingStock,
      if (usersOnPlan > 1 || (team?.invitations.isNotEmpty ?? false)) SetupStep.team,
    };
  }
}

class _StepRail extends ConsumerWidget {
  const _StepRail({required this.current, required this.done});

  final SetupStep current;
  final Set<SetupStep> done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      child: Row(
        children: [
          for (final step in SetupStep.values) ...[
            if (step.index > 0)
              Container(
                width: 28,
                height: 1,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
              ),
            InkWell(
              key: Key('setup-rail-${step.name}'),
              borderRadius: BorderRadius.circular(999),
              onTap: () => ref.read(setupWizardStepProvider.notifier).go(step),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    _StepBadge(index: step.index, isCurrent: step == current, isDone: done.contains(step)),
                    const SizedBox(width: 8),
                    Text(
                      step.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: step == current ? FontWeight.w700 : FontWeight.w500,
                        color: step == current
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.index, required this.isCurrent, required this.isDone});

  final int index;
  final bool isCurrent;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isDone) {
      return const Icon(Icons.check_circle, size: 24, color: _green);
    }
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent ? theme.colorScheme.primary : Colors.transparent,
        border: Border.all(
          color: isCurrent ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        '${index + 1}',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: isCurrent ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _Footer extends ConsumerStatefulWidget {
  const _Footer({required this.step});

  final SetupStep step;

  @override
  ConsumerState<_Footer> createState() => _FooterState();
}

class _FooterState extends ConsumerState<_Footer> {
  bool _finishing = false;

  bool get _isLast => widget.step == SetupStep.values.last;

  void _goTo(int index) => ref.read(setupWizardStepProvider.notifier).go(SetupStep.values[index]);

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      await completeSetup(ref);
      if (mounted) context.go('/');
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      final message = e is NetworkException
          ? "You're offline. Finish setup once you're connected again."
          : friendlyError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.step.index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      child: Row(
        children: [
          if (index > 0)
            OutlinedButton.icon(
              key: const Key('setup-back'),
              onPressed: _finishing ? null : () => _goTo(index - 1),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
          const Spacer(),
          Text('Step ${index + 1} of ${SetupStep.values.length}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 16),
          if (_isLast)
            ElevatedButton.icon(
              key: const Key('setup-finish'),
              onPressed: _finishing ? null : _finish,
              icon: _finishing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Finish setup'),
            )
          else
            ElevatedButton.icon(
              key: const Key('setup-next'),
              onPressed: () => _goTo(index + 1),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Next'),
            ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.65)),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = value == null || value!.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
          Expanded(
            child: Text(
              missing ? 'Not set' : value!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: missing ? theme.colorScheme.onSurface.withValues(alpha: 0.4) : null,
                fontStyle: missing ? FontStyle.italic : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : _green;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color))),
        ],
      ),
    );
  }
}

class _WarehouseStep extends ConsumerWidget {
  const _WarehouseStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(authControllerProvider).valueOrNull!.organization!;
    final warehouses = ref.watch(warehousesProvider);
    final tax = org.taxName == null || org.taxRate == 0 ? null : '${org.taxName} ${org.taxRate}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Company & warehouse',
          subtitle: 'Check the details you entered on the website and make sure your warehouse is right.',
        ),
        _Panel(
          title: 'Company',
          action: TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(ApiConstants.organizationUrl)),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Edit on the website'),
          ),
          child: Column(
            children: [
              _Field('Name', org.name),
              _Field('Industry', org.industry),
              _Field('Currency', org.currency),
              _Field('Registration number', org.registrationNumber),
              _Field('Address', org.address),
              _Field('Phone', org.phone),
              _Field('Email', org.email),
              _Field('Tax', tax),
            ],
          ),
        ),
        _Panel(
          title: 'Warehouse',
          child: warehouses.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _Message(friendlyError(e), isError: true),
            data: (all) {
              final active = all.where((w) => w.isActive).toList();
              if (active.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('You have no active warehouse yet. Stock is always recorded in a warehouse.'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      key: const Key('setup-add-warehouse'),
                      onPressed: () => showDialog(context: context, builder: (_) => const WarehouseFormDialog()),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add your warehouse'),
                    ),
                  ],
                );
              }
              return Column(
                children: [for (final w in active) _WarehouseTile(warehouse: w)],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WarehouseTile extends StatelessWidget {
  const _WarehouseTile({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _Field('Name', warehouse.name),
              _Field('Address', warehouse.address),
              _Field('Manager', warehouse.managerName),
              _Field('Phone', warehouse.phone),
            ],
          ),
        ),
        OutlinedButton.icon(
          key: Key('setup-edit-warehouse-${warehouse.id}'),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => WarehouseFormDialog(warehouse: warehouse),
          ),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Edit'),
        ),
      ],
    );
  }
}

class _ProductsStep extends ConsumerWidget {
  const _ProductsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final atCap = ref.watch(productSlotsFullProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Products',
          subtitle: 'Add the products you stock, one at a time or all at once from an Excel sheet.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              key: const Key('setup-add-product'),
              onPressed: atCap ? null : () => showDialog(context: context, builder: (_) => const ProductFormDialog()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add product'),
            ),
            OutlinedButton.icon(
              key: const Key('setup-import-products'),
              onPressed: atCap
                  ? null
                  : () async {
                      final imported = await showDialog<bool>(
                        context: context,
                        builder: (_) => const BulkImportDialog(),
                      );
                      if (imported == true) ref.invalidate(archivedProductsProvider);
                    },
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Import from Excel'),
            ),
          ],
        ),
        if (atCap) const _Message('Your plan has reached its product limit.', isError: true),
        const SizedBox(height: 16),
        _Panel(
          title: 'Your products',
          child: products.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Message(friendlyError(e), isError: true),
            data: (all) {
              if (all.isEmpty) {
                return Text(
                  'No products yet. Add one above, or import a list.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                );
              }
              return Column(
                children: [
                  for (final p in all)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined, size: 20),
                      title: Text(p.name),
                      subtitle: Text('${p.sku} · ${p.unit}${p.isPending ? ' · waiting to sync' : ''}'),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OpeningStockStep extends ConsumerStatefulWidget {
  const _OpeningStockStep();

  @override
  ConsumerState<_OpeningStockStep> createState() => _OpeningStockStepState();
}

class _OpeningStockStepState extends ConsumerState<_OpeningStockStep> {
  final Map<String, TextEditingController> _quantities = {};
  String? _warehouseId;
  bool _saving = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    for (final c in _quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String productId) =>
      _quantities.putIfAbsent(productId, TextEditingController.new);

  Future<void> _save(List<Product> products, String warehouseId) async {
    final entries = [
      for (final p in products)
        if ((int.tryParse(_controllerFor(p.id).text.trim()) ?? 0) > 0)
          (product: p, quantity: int.parse(_controllerFor(p.id).text.trim())),
    ];
    if (entries.isEmpty) {
      setState(() {
        _error = 'Enter a quantity for at least one product.';
        _result = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });

    final movements = ref.read(movementsProvider.notifier);
    var sent = 0;
    var queued = 0;
    final failed = <String>[];
    for (final entry in entries) {
      try {
        final result = await movements.record(
          productId: entry.product.id,
          warehouseId: warehouseId,
          type: StockMovementType.stockIn,
          quantity: entry.quantity,
          reason: openingStockReason,
        );
        if (result.queued) {
          queued++;
        } else {
          sent++;
        }
        _controllerFor(entry.product.id).clear();
      } catch (e) {
        failed.add('${entry.product.name}: ${friendlyError(e)}');
      }
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      final recorded = sent + queued;
      _result = recorded == 0
          ? null
          : 'Opening stock recorded for $recorded product${recorded == 1 ? '' : 's'}'
              '${queued > 0 ? ' ($queued saved on this computer, will sync when you are back online)' : ''}.';
      _error = failed.isEmpty ? null : failed.join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productListProvider);
    final warehouses = ref.watch(activeWarehousesProvider);
    final theme = Theme.of(context);

    const header = _StepHeader(
      title: 'Opening stock',
      subtitle: 'Enter how many of each product you have today. Each one is recorded as stock in, '
          'with the reason "$openingStockReason", so your stock history starts from the right numbers.',
    );

    if (products.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const Text('Add your products first, then come back to record what you have in stock.'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.read(setupWizardStepProvider.notifier).go(SetupStep.products),
            child: const Text('Go to Products'),
          ),
        ],
      );
    }
    if (warehouses.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const Text('Add a warehouse first: opening stock is recorded in a warehouse.'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.read(setupWizardStepProvider.notifier).go(SetupStep.warehouse),
            child: const Text('Go to Company & warehouse'),
          ),
        ],
      );
    }

    final warehouseId = warehouses.any((w) => w.id == _warehouseId) ? _warehouseId! : warehouses.first.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        if (warehouses.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                initialValue: warehouseId,
                decoration: const InputDecoration(labelText: 'Warehouse'),
                items: [
                  for (final w in warehouses) DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
            ),
          ),
        _Panel(
          title: 'Quantities on hand',
          child: Column(
            children: [
              for (final p in products)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            Text(
                              '${p.sku} · currently ${p.currentStock} ${p.unit}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          key: Key('setup-qty-${p.id}'),
                          controller: _controllerFor(p.id),
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(hintText: '0', suffixText: p.unit, isDense: true),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            key: const Key('setup-save-opening-stock'),
            onPressed: _saving ? null : () => _save(products, warehouseId),
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save opening stock'),
          ),
        ),
        if (_result != null) _Message(_result!),
        if (_error != null) _Message(_error!, isError: true),
      ],
    );
  }
}

class _TeamStep extends ConsumerStatefulWidget {
  const _TeamStep();

  @override
  ConsumerState<_TeamStep> createState() => _TeamStepState();
}

class _TeamStepState extends ConsumerState<_TeamStep> {
  final _email = TextEditingController();
  String? _role;
  bool _sending = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite(String role) async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter an email address.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _result = null;
    });
    try {
      final sent = await ref.read(teamProvider.notifier).invite(email: email, role: role);
      if (!mounted) return;
      _email.clear();
      setState(() {
        _sending = false;
        _result = sent
            ? 'Invitation sent to $email as $role. The link works for 7 days.'
            : 'The invitation to $email was saved, but the email could not be sent. Resend it from the Team page on the website.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Team',
          subtitle: 'Invite the people who will use Aimify with you. Each person gets an email with a link to join.',
        ),
        team.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Message(
                e is NetworkException ? "You're offline. Inviting people needs a connection." : friendlyError(e),
                isError: true,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(teamProvider.notifier).refresh(),
                child: const Text('Try again'),
              ),
            ],
          ),
          data: (overview) {
            final roles = overview.assignableRoles;
            final role = roles.contains(_role)
                ? _role!
                : roles.contains('Sales Staff')
                    ? 'Sales Staff'
                    : (roles.isEmpty ? null : roles.first);
            final seats = overview.seatLimit == null
                ? '${overview.seatsUsed} people (no limit on your plan)'
                : '${overview.seatsUsed} of ${overview.seatLimit} seats used';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Panel(
                  title: 'Invite someone',
                  action: Text(seats, style: theme.textTheme.bodySmall),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 300,
                            child: TextField(
                              key: const Key('setup-invite-email'),
                              controller: _email,
                              enabled: !_sending && !overview.isFull,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(labelText: 'Email address'),
                            ),
                          ),
                          if (role != null)
                            SizedBox(
                              width: 260,
                              child: DropdownButtonFormField<String>(
                                key: const Key('setup-invite-role'),
                                initialValue: role,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Role'),
                                items: [
                                  for (final r in roles)
                                    DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
                                ],
                                onChanged: _sending ? null : (v) => setState(() => _role = v),
                              ),
                            ),
                          ElevatedButton.icon(
                            key: const Key('setup-send-invite'),
                            onPressed: (_sending || overview.isFull || role == null) ? null : () => _invite(role),
                            icon: _sending
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send_outlined, size: 18),
                            label: const Text('Send invitation'),
                          ),
                        ],
                      ),
                      if (overview.isFull)
                        const _Message(
                          'Your plan has no free seats. Remove someone or revoke an invitation on the website.',
                          isError: true,
                        ),
                      if (_result != null) _Message(_result!),
                      if (_error != null) _Message(_error!, isError: true),
                    ],
                  ),
                ),
                _Panel(
                  title: 'People',
                  action: TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(ApiConstants.teamUrl)),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Manage on the website'),
                  ),
                  child: Column(
                    children: [
                      for (final m in overview.members)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_outline, size: 20),
                          title: Text(m.name),
                          subtitle: Text(m.email),
                          trailing: Text(m.role, style: theme.textTheme.bodySmall),
                        ),
                      for (final i in overview.invitations)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.mail_outline, size: 20),
                          title: Text(i.email),
                          subtitle: const Text('Invitation pending'),
                          trailing: Text(i.role, style: theme.textTheme.bodySmall),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SubscriptionStep extends ConsumerWidget {
  const _SubscriptionStep();

  static String _statusLabel(Organization org) => switch (org.subscriptionStatus) {
        'trial' => 'Free trial',
        'active' => 'Active',
        'past_due' => 'Past due',
        _ => org.subscriptionStatus,
      };

  static String _usage(int used, int? limit) => limit == null ? '$used (no limit)' : '$used of $limit';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).valueOrNull!;
    final org = me.organization!;
    final plan = me.plan;

    String? period;
    if (org.isTrial && org.trialEndsAt != null) {
      final days = org.trialEndsAt!.difference(DateTime.now()).inDays;
      period = days > 0
          ? '$days day${days == 1 ? '' : 's'} left, ends ${dateFormat.format(org.trialEndsAt!)}'
          : 'Ends today';
    } else if (org.currentPeriodEnd != null) {
      period = '${org.cancelAtPeriodEnd ? 'Ends' : 'Renews'} ${dateFormat.format(org.currentPeriodEnd!)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Subscription',
          subtitle: 'Your plan and what it allows. Payments are made on the website.',
        ),
        _Panel(
          title: 'Your plan',
          action: TextButton.icon(
            key: const Key('setup-open-billing'),
            onPressed: () => launchUrl(Uri.parse(ApiConstants.billingUrl)),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open billing page'),
          ),
          child: Column(
            children: [
              _Field('Plan', plan?.name),
              _Field('Status', _statusLabel(org)),
              if (period != null) _Field(org.isTrial ? 'Trial' : 'Paid period', period),
              if (plan != null) ...[
                _Field('Team members', _usage(plan.usage.users, plan.limits.users)),
                _Field('Active warehouses', _usage(plan.usage.warehouses, plan.limits.warehouses)),
                _Field('Active products', _usage(plan.usage.products, plan.limits.products)),
              ],
            ],
          ),
        ),
        const _Message('That\'s everything. Choose "Finish setup" to go to your dashboard. '
            'You can change any of this later from the app or the website.'),
      ],
    );
  }
}
