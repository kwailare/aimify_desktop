import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_provider.dart';
import '../../../features/auth/presentation/auth_controller.dart';
import '../../../features/auth/domain/screen_visibility.dart';
import '../../../features/sync/sync_status_tile.dart';
import '../../offline/outbox.dart';
import '../aimify_wordmark.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon, {this.localOnly = false});

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// True for modules with no backend yet (see `docs/desktop-api.md`) — they
  /// work on this computer only, and the sidebar says so.
  final bool localOnly;
}

// Order here must match the StatefulShellRoute branch order in
// `core/router/app_router.dart` — each index is a branch.
const navItems = [
  _NavItem('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
  _NavItem('Products', Icons.inventory_2_outlined, Icons.inventory_2),
  _NavItem('Inventory', Icons.warehouse_outlined, Icons.warehouse),
  _NavItem('Purchases', Icons.shopping_cart_outlined, Icons.shopping_cart, localOnly: true),
  _NavItem('Suppliers', Icons.local_shipping_outlined, Icons.local_shipping),
  _NavItem('Customers', Icons.people_outline, Icons.people),
  _NavItem('Expenses', Icons.receipt_long_outlined, Icons.receipt_long, localOnly: true),
  _NavItem('Credits & Debts', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
  _NavItem('Warehouses', Icons.store_outlined, Icons.store),
  _NavItem('Reports', Icons.bar_chart_outlined, Icons.bar_chart),
];

const _itemHeight = 46.0;
const _itemGap = 6.0;
const _itemExtent = _itemHeight + _itemGap;

/// The sidebar's actual content — header, nav list with a sliding gold
/// indicator behind the active item, and a footer with the signed-in
/// user/org plus quick actions. Rendered by [AppShell] either docked (wide
/// windows) or as a slide-in overlay panel (narrow windows).
class AppSidebar extends ConsumerWidget {
  const AppSidebar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onClose,
    this.elevated = false,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  /// True when rendered as a floating overlay panel (narrow windows) —
  /// adds a shadow so it visually separates from the content behind it.
  final bool elevated;

  /// Signing out with changes still waiting to sync asks first: they are
  /// kept on this computer and sync after the next sign-in, but the person
  /// should know they haven't reached Aimify yet.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final pending = ref.read(pendingCountProvider);
    if (pending > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sign out with unsynced changes?'),
          content: Text(
            '$pending change(s) are saved on this computer but have not reached Aimify yet. '
            'They are kept, and will sync the next time you sign in with a good connection.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay signed in'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final me = ref.watch(authControllerProvider).valueOrNull;
    final gold = isDark ? const Color(0xFFF2B233) : const Color(0xFFD88B00);

    // Which nav items this role sees at all — a role change (or the org
    // still loading) can hide the branch currently selected, so this is
    // computed fresh on every build rather than cached at sign-in.
    final visibleIndices = [
      for (var i = 0; i < navItems.length; i++)
        if (isScreenVisible(me?.role, AppScreen.values[i])) i,
    ];
    final selectedPosition = visibleIndices.indexOf(currentIndex);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF1C1C1C), const Color(0xFF161616)]
              : [Colors.white, const Color(0xFFFBF6EA)],
        ),
        border: Border(
          right: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
        ),
        boxShadow: elevated
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(8, 0))]
            : null,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 12, 18),
              child: Row(
                children: [
                  const Expanded(child: AimifyWordmark(fontSize: 21)),
                  IconButton(
                    tooltip: 'Hide sidebar',
                    onPressed: onClose,
                    icon: const Icon(Icons.menu_open_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Expanded(
              // Scrollable: at 10 nav items × 52px, the list is ~520px
              // tall before the header/footer even come in — taller than
              // this fits on a lot of ordinary window heights. The
              // sliding indicator's position is computed the same way
              // (index * itemExtent) whether or not this is scrolled,
              // since it lives inside the same Stack as the items and
              // scrolls together with them.
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Stack(
                  children: [
                    // Off the top and invisible when the selected branch
                    // isn't in this role's list at all (a role change just
                    // hid the screen the router is about to redirect away
                    // from) — there is nowhere sensible to point it.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      top: selectedPosition < 0 ? -_itemHeight : selectedPosition * _itemExtent,
                      left: 0,
                      right: 0,
                      height: _itemHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [gold.withValues(alpha: 0.16), gold.withValues(alpha: 0.05)],
                          ),
                          border: Border.all(color: gold.withValues(alpha: 0.28)),
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        for (final i in visibleIndices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: _itemGap),
                            child: _SidebarTile(
                              item: navItems[i],
                              selected: currentIndex == i,
                              accent: gold,
                              onTap: () => onSelect(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (me != null) ...[
                    Row(
                      children: [
                        if (me.organization?.logoUrl case final String logoUrl)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                logoUrl,
                                width: 22,
                                height: 22,
                                fit: BoxFit.cover,
                                // A broken/unreachable logo URL shouldn't
                                // ever break the sidebar — just fall back
                                // to no logo.
                                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                me.user.name,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                me.organization?.name ?? 'No organization yet',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const SyncStatusTile(),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: IconButton(
                          tooltip: 'Toggle dark mode',
                          onPressed: () {
                            final current = ref.read(themeModeProvider);
                            ref.read(themeModeProvider.notifier).state =
                                current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                          },
                          icon: const Icon(Icons.brightness_6_outlined, size: 20),
                        ),
                      ),
                      Expanded(
                        child: IconButton(
                          tooltip: 'Sign out',
                          onPressed: () => _signOut(context, ref),
                          icon: const Icon(Icons.logout, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final color = selected
        ? widget.accent
        : theme.colorScheme.onSurface.withValues(alpha: _hovering ? 0.9 : 0.7);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: SizedBox(
        height: _itemHeight,
        child: Material(
          color: !selected && _hovering
              ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  AnimatedScale(
                    duration: const Duration(milliseconds: 180),
                    scale: selected ? 1.08 : 1.0,
                    child: Icon(selected ? widget.item.selectedIcon : widget.item.icon, size: 20, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ),
                  if (widget.item.localOnly)
                    Tooltip(
                      message: 'No online backend yet — saved on this computer only',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'LOCAL',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
