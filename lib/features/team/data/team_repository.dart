import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/team.dart';

/// REAL `/api/v1/team` — list the team and invite people. Changing roles,
/// removing members and revoking invitations stay on the website's Team
/// page. Online-only, like warehouses: an invitation sends an email, so
/// there is nothing useful to queue.
class TeamRepository {
  TeamRepository(this._api);

  final AuthedApi _api;

  Future<TeamOverview> overview() async {
    final json = await _api.get(ApiConstants.team);
    return TeamOverview.fromJson(json);
  }

  /// Returns whether the invitation email went out. `false` means the
  /// invitation was saved but has to be resent from the website.
  Future<bool> invite({required String email, required String role}) async {
    final json = await _api.post(ApiConstants.teamInvitations, {'email': email, 'role': role});
    return json['emailSent'] as bool? ?? false;
  }
}

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(authedApiProvider)),
);

class TeamNotifier extends AsyncNotifier<TeamOverview> {
  @override
  Future<TeamOverview> build() async {
    if (ref.watch(sessionUserIdProvider) == null) {
      return const TeamOverview(members: [], invitations: [], assignableRoles: [], seatsUsed: 0);
    }
    return ref.watch(teamRepositoryProvider).overview();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(ref.read(teamRepositoryProvider).overview);
  }

  /// Throws [ApiException] with a friendly message on refusal (plan limit,
  /// role not allowed, already in an organization...).
  Future<bool> invite({required String email, required String role}) async {
    final sent = await ref.read(teamRepositoryProvider).invite(email: email, role: role);
    await refresh();
    unawaited(ref.read(authControllerProvider.notifier).refresh());
    return sent;
  }
}

final teamProvider = AsyncNotifierProvider<TeamNotifier, TeamOverview>(TeamNotifier.new);
