import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/credits/presentation/credits_screen.dart';
import '../../features/credits_debts/presentation/credits_debts_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/purchases/presentation/purchases_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/staff/presentation/staff_screen.dart';
import '../../features/suppliers/presentation/suppliers_screen.dart';
import '../../features/warehouses/presentation/warehouses_screen.dart';
import '../../shared/widgets/app_shell.dart';

/// Public routes reachable regardless of session state — exempt from the
/// "not logged in -> /login" redirect below.
const _publicRoutes = {'/login', '/credits'};

/// Fade + gentle slide-up used for the top-level routes below (splash,
/// login, credits). The nested module screens inside [AppShell] get their
/// own cross-fade from [AnimatedSwitcher] when you switch sidebar sections.
CustomTransitionPage<void> _fadeThroughPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    },
  );
}

/// Bridges Riverpod's [authControllerProvider] to go_router's
/// [Listenable]-based `refreshListenable`, so the router re-evaluates
/// [_redirect] whenever the session state changes (login/logout/restore).
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
}

String? _redirect(BuildContext context, GoRouterState state) {
  final container = ProviderScope.containerOf(context);
  final authState = container.read(authControllerProvider);
  final location = state.matchedLocation;

  // Still checking for a stored token / validating it against /me.
  if (authState.isLoading) {
    return location == '/splash' ? null : '/splash';
  }

  final loggedIn = authState.valueOrNull != null;

  if (!loggedIn) {
    // Resolved with no session (never had a token, or it was rejected) —
    // send everyone, including whoever's still parked on /splash, to login.
    // /credits stays reachable either way — it's just an info page.
    return _publicRoutes.contains(location) ? null : '/login';
  }

  if (location == '/login' || location == '/splash') return '/';
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: _redirect,
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _fadeThroughPage(const SplashScreen(), state),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _fadeThroughPage(const LoginScreen(), state),
      ),
      GoRoute(
        path: '/credits',
        pageBuilder: (context, state) => _fadeThroughPage(const CreditsScreen(), state),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (context, state) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/products', builder: (context, state) => const ProductsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/inventory', builder: (context, state) => const InventoryScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/purchases', builder: (context, state) => const PurchasesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/suppliers', builder: (context, state) => const SuppliersScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/customers', builder: (context, state) => const CustomersScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/expenses', builder: (context, state) => const ExpensesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/credits-debts',
                builder: (context, state) => const CreditsDebtsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/warehouses', builder: (context, state) => const WarehousesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/staff', builder: (context, state) => const StaffScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});
