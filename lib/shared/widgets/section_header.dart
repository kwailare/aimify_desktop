import 'package:flutter/material.dart';

/// Consistent page header used across every module screen: title, optional
/// subtitle, an optional [MockDataBadge]-style [badge], and a trailing
/// action slot (usually an "Add ..." button).
///
/// Stacks into a column below [_narrowBreakpoint] so title/subtitle and the
/// action button(s) never get squeezed into an overflowing row on a
/// narrower window.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badge,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget? badge;
  final List<Widget>? actions;

  static const _narrowBreakpoint = 560.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 10),
              badge!,
            ],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    );

    if (actions == null) return titleBlock;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _narrowBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions!),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            Wrap(spacing: 8, runSpacing: 8, children: actions!),
          ],
        );
      },
    );
  }
}
