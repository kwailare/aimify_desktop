import 'package:flutter/material.dart';

/// Counts up from 0 to [value] once, then holds — the "wow, it's alive"
/// touch on the dashboard's metric cards. Re-animates from 0 whenever
/// [value] changes (e.g. after recording a sale updates the mock data),
/// which is a reasonable way to draw the eye to what just moved.
class AnimatedCounterText extends StatelessWidget {
  const AnimatedCounterText({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  final double value;
  final String Function(double) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return Text(format(animatedValue), style: style);
      },
    );
  }
}
