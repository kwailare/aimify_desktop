import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/offline/local_store.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';

/// The guided setup's steps, in order.
enum SetupStep { warehouse, products, openingStock, team, subscription }

extension SetupStepX on SetupStep {
  String get title => switch (this) {
        SetupStep.warehouse => 'Company & warehouse',
        SetupStep.products => 'Products',
        SetupStep.openingStock => 'Opening stock',
        SetupStep.team => 'Team',
        SetupStep.subscription => 'Subscription',
      };
}

/// The reason recorded on every movement the Opening stock step creates, so
/// they're recognisable in the stock ledger.
const openingStockReason = 'Opening stock';

/// True when the guided setup should open by itself: an Owner or
/// Administrator of an unlocked organization nobody has finished setting up,
/// who hasn't chosen "Finish later" since the app started.
bool shouldAutoOpenSetup(MeResponse? me, {required bool dismissed}) {
  final org = me?.organization;
  if (me == null || org == null || dismissed) return false;
  return !org.isLocked && !org.isSetupComplete && me.hasPermission(Permissions.setupComplete);
}

/// "Finish later" — closes the wizard until the app is next started. The
/// dashboard's setup card can reopen it at any time.
final setupWizardDismissedProvider = StateProvider<bool>((ref) => false);

/// The step the wizard is on, remembered on this computer per user and
/// organization, so reopening it continues where it was left.
class SetupWizardStepNotifier extends AsyncNotifier<SetupStep> {
  String? get _key {
    final me = ref.read(authControllerProvider).valueOrNull;
    final org = me?.organization;
    return me == null || org == null ? null : 'u_${me.user.id}_setup_wizard_${org.id}';
  }

  @override
  Future<SetupStep> build() async {
    ref.watch(sessionUserIdProvider);
    final key = _key;
    if (key == null) return SetupStep.values.first;
    try {
      final raw = await ref.read(localStoreProvider).read(key);
      if (raw == null) return SetupStep.values.first;
      final index = (jsonDecode(raw) as Map<String, dynamic>)['step'] as int? ?? 0;
      return SetupStep.values[index.clamp(0, SetupStep.values.length - 1)];
    } catch (_) {
      return SetupStep.values.first;
    }
  }

  Future<void> go(SetupStep step) async {
    state = AsyncData(step);
    final key = _key;
    if (key == null) return;
    try {
      await ref.read(localStoreProvider).write(key, jsonEncode({'step': step.index}));
    } catch (_) {
      // Remembering the step is a convenience; the wizard works without it.
    }
  }
}

final setupWizardStepProvider =
    AsyncNotifierProvider<SetupWizardStepNotifier, SetupStep>(SetupWizardStepNotifier.new);

/// REAL `POST /api/v1/organization/setup`.
class SetupRepository {
  SetupRepository(this._api);

  final AuthedApi _api;

  Future<void> complete() => _api.post(ApiConstants.organizationSetup, const {});
}

final setupRepositoryProvider = Provider<SetupRepository>(
  (ref) => SetupRepository(ref.watch(authedApiProvider)),
);

/// Marks setup finished for the whole organization and re-reads `/me`, so
/// [Organization.setupCompletedAt] is set before the wizard closes.
Future<void> completeSetup(WidgetRef ref) async {
  await ref.read(setupRepositoryProvider).complete();
  await ref.read(authControllerProvider.notifier).refresh();
}
