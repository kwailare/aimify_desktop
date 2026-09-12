import 'package:flutter/material.dart';

import '../../../../shared/utils/formatters.dart';
import '../../../auth/domain/auth_models.dart';

/// The dashboard's opening band: a time-aware greeting plus the signed-in
/// user's organization/subscription status — all REAL, straight from
/// `GET /api/v1/me` (see `dashboard_screen.dart`, which passes in [me]).
class DashboardHero extends StatelessWidget {
  const DashboardHero({super.key, required this.me});

  final MeResponse me;

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gold = isDark ? const Color(0xFFF2B233) : const Color(0xFFD88B00);
    final firstName = me.user.name.split(' ').first;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF241C0E), const Color(0xFF1C1C1C)]
              : [const Color(0xFFFFF3DA), const Color(0xFFFDF7EC)],
        ),
        border: Border.all(color: gold.withValues(alpha: 0.18)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          final greetingBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _greeting().toUpperCase(),
                style: TextStyle(
                  color: gold,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    const TextSpan(text: 'Hey '),
                    TextSpan(
                      text: firstName,
                      style: TextStyle(color: gold),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                me.user.email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          );

          final statusBlock = me.hasCompletedOnboarding
              ? _OrgStatusPanel(
                  orgName: me.organization!.name,
                  warehouseName: me.organization!.warehouseName,
                  role: me.role!,
                  subscriptionStatus: me.organization!.subscriptionStatus,
                  trialEndsAt: me.organization!.trialEndsAt,
                )
              : const _OnboardingChip();

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                greetingBlock,
                const SizedBox(height: 20),
                statusBlock,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: greetingBlock),
              const SizedBox(width: 24),
              // A fixed width, not just the panel's own `minWidth` — a Row
              // gives non-Expanded children unbounded max width, and
              // _OrgStatusPanel uses Expanded internally, which needs a
              // bounded width from somewhere above it.
              SizedBox(width: 300, child: statusBlock),
            ],
          );
        },
      ),
    );
  }
}

class _OrgStatusPanel extends StatelessWidget {
  const _OrgStatusPanel({
    required this.orgName,
    required this.warehouseName,
    required this.role,
    required this.subscriptionStatus,
    required this.trialEndsAt,
  });

  final String orgName;
  final String warehouseName;
  final String role;
  final String subscriptionStatus;
  final DateTime? trialEndsAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isTrial = subscriptionStatus.toLowerCase() == 'trial';
    const warning = Color(0xFFD1453B);
    const success = Color(0xFF2F8F5B);

    // Trial length isn't returned by the API — only the end date is. This
    // bar assumes a 14-day trial purely to give the countdown a visual
    // sense of "how much is left," not an exact reading.
    double? trialProgress;
    int? daysLeft;
    if (isTrial && trialEndsAt != null) {
      daysLeft = trialEndsAt!.difference(DateTime.now()).inDays;
      trialProgress = (daysLeft / 14).clamp(0, 1);
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 240),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.5 : 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  orgName,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: (isTrial ? warning : success).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  subscriptionStatus[0].toUpperCase() + subscriptionStatus.substring(1),
                  style: TextStyle(
                    color: isTrial ? warning : success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '$warehouseName · $role',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (trialProgress != null && daysLeft != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: trialProgress,
                minHeight: 6,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(daysLeft <= 3 ? warning : success),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              daysLeft > 0 ? '$daysLeft day(s) left · ends ${dateFormat.format(trialEndsAt!)}' : 'Trial ended',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when `/api/v1/me` returns `organization: null` — the user hasn't
/// finished onboarding on aimify-web yet. A normal, expected state per the
/// API contract, not an error.
class _OnboardingChip extends StatelessWidget {
  const _OnboardingChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 240),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.secondary, size: 20),
          const SizedBox(width: 10),
          const Flexible(child: Text('Finish setup on the Aimify website to unlock your org')),
        ],
      ),
    );
  }
}
