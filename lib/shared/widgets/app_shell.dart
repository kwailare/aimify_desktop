import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/inventory/data/inventory_repository.dart';
import '../../features/products/data/products_repository.dart';
import '../../features/warehouses/data/warehouses_repository.dart';
import '../services/authed_api.dart';
import 'sidebar/app_sidebar.dart';
import 'sidebar/sidebar_controller.dart';

/// How often the authenticated shell re-fetches `/me` in the background.
/// Per docs/desktop-api.md: subscription status, plan usage/limits and email
/// verification can all change on the website while the desktop app stays
/// open, so periodic refresh (in addition to the explicit refreshes after
/// login and after a 402/403) is how the app notices without a restart.
const _meRefreshInterval = Duration(minutes: 5);

/// Width above which the sidebar docks (pushing content aside, toggle
/// shrinks it to nothing) rather than overlaying (sliding over content
/// with a dismissible scrim, like a mobile drawer) — see [AppShell].
const _wideBreakpoint = 900.0;
const _sidebarWidth = 260.0;
const _overlaySidebarWidth = 280.0;

/// Persistent-on-wide / drawer-on-narrow sidebar shell wrapping every
/// authenticated screen. Built on go_router's [StatefulNavigationShell] so
/// each branch (module) keeps its own navigation stack and scroll position
/// when you switch away and back.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      _meRefreshInterval,
      (_) => ref.read(authControllerProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Re-reads everything the screens show. The first request that gets an
  /// answer clears the offline banner (see `AuthedApi`).
  Future<void> _retryAll() async {
    await Future.wait([
      ref.read(authControllerProvider.notifier).refresh(),
      ref.read(productsProvider.notifier).refresh(),
      ref.read(warehousesProvider.notifier).refresh(),
      ref.read(movementsProvider.notifier).refresh(),
      ref.read(stockAlertsProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final sidebarOpen = ref.watch(sidebarOpenProvider);
    void setOpen(bool value) => ref.read(sidebarOpenProvider.notifier).state = value;

    final offline = ref.watch(offlineProvider);

    final content = Column(
      children: [
        if (offline) _OfflineBanner(onRetry: _retryAll),
        Expanded(
          child: _BranchFadeIn(
            branchIndex: navigationShell.currentIndex,
            child: navigationShell,
          ),
        ),
      ],
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;

          void selectBranch(int index, {required bool closeAfter}) {
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
            if (closeAfter) setOpen(false);
          }

          if (isWide) {
            return Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  width: sidebarOpen ? _sidebarWidth : 0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: SizedBox(
                    width: _sidebarWidth,
                    child: AppSidebar(
                      currentIndex: navigationShell.currentIndex,
                      onSelect: (i) => selectBranch(i, closeAfter: false),
                      onClose: () => setOpen(false),
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: content),
                      _MenuFab(visible: !sidebarOpen, onTap: () => setOpen(true)),
                    ],
                  ),
                ),
              ],
            );
          }

          // Narrow window: sidebar becomes an overlay drawer over the
          // content, with a scrim to dismiss it — both stay permanently in
          // the tree (never conditionally inserted/removed) purely so their
          // AnimatedOpacity/AnimatedPositioned actually have a "from" value
          // to animate between; conditionally building them would just pop
          // in/out at their final position with no transition.
          return Stack(
            children: [
              Positioned.fill(child: content),
              _MenuFab(visible: !sidebarOpen, onTap: () => setOpen(true)),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !sidebarOpen,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: sidebarOpen ? 1 : 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setOpen(false),
                      child: Container(color: Colors.black.withValues(alpha: 0.45)),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                left: sidebarOpen ? 0 : -_overlaySidebarWidth,
                width: _overlaySidebarWidth,
                child: AppSidebar(
                  currentIndex: navigationShell.currentIndex,
                  onSelect: (i) => selectBranch(i, closeAfter: true),
                  onClose: () => setOpen(false),
                  elevated: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Shown across the top of every screen while the last request found no
/// connection — the data on screen is still what was loaded before, so it
/// says so and offers a retry instead of failing silently.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.error.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 18, color: scheme.error),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "You're offline. What you see may be out of date, and changes can't be saved.",
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Small floating button that reopens the sidebar once it's been hidden —
/// docked-collapsed on a wide window, or fully off-screen on a narrow one.
/// Always present (never conditionally built) so [AnimatedOpacity] has
/// something to fade rather than popping in abruptly.
class _MenuFab extends StatelessWidget {
  const _MenuFab({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 16,
      left: 16,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1 : 0,
          child: Material(
            color: theme.colorScheme.surface,
            elevation: 4,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.menu_rounded, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades/slides in the active sidebar section on each switch — without
/// ever giving [navigationShell] a new [Key].
///
/// An earlier version wrapped `navigationShell` in a `KeyedSubtree` keyed
/// on the branch index inside an `AnimatedSwitcher`, so the crossfade
/// briefly held both the outgoing and incoming subtrees in the tree at
/// once. Each of those subtrees is backed by the *same* stable, go_router
/// -owned `GlobalKey`s (one per branch Navigator), so Flutter had two
/// widgets claiming the same GlobalKey simultaneously — an immediate,
/// reliably reproducible crash the instant you clicked a nav item.
///
/// This version never duplicates the shell: it's a single child whose
/// opacity/position is animated in place, so there's exactly one Element
/// (and one set of GlobalKeys) in the tree at all times. The trade-off is a
/// fade-*in* rather than a true dissolve between old and new content.
class _BranchFadeIn extends StatefulWidget {
  const _BranchFadeIn({required this.branchIndex, required this.child});

  final int branchIndex;
  final Widget child;

  @override
  State<_BranchFadeIn> createState() => _BranchFadeInState();
}

class _BranchFadeInState extends State<_BranchFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..value = 1;

  @override
  void didUpdateWidget(_BranchFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchIndex != widget.branchIndex) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
