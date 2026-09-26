import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

/// True if the signed-in role holds [permission] — see
/// `auth/domain/permissions.dart` for the keys and
/// `docs/desktop-api.md`'s "Roles and permissions" for which roles hold
/// which. Reading is open to every role, so only write actions should ever
/// check this. Defaults to `false` while `/me` is still loading or if it
/// failed, which fails closed (hides/disables controls) rather than
/// flashing them on before the real answer arrives.
bool hasPermission(WidgetRef ref, String permission) {
  final me = ref.watch(authControllerProvider).valueOrNull;
  return me?.hasPermission(permission) ?? false;
}
