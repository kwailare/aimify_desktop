import 'package:flutter/material.dart';

/// Purely decorative "stock levels" illustration for the login screen's
/// branded panel — echoes the mini bar chart in aimify-web's marketing
/// hero section (`.hero-chart-card` in that project's CSS), reinforcing
/// what the product does without pretending to be a real dashboard.
///
/// Explicitly illustrative sample numbers, same spirit as the "Sample
/// data" badges used once you're past login — labeled as a preview here
/// too so it's never mistaken for a live reading.
class StockPulseCard extends StatefulWidget {
  const StockPulseCard({super.key});

  @override
  State<StockPulseCard> createState() => _StockPulseCardState();
}

class _StockPulseCardState extends State<StockPulseCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  // Bar heights as a fraction of the chart's max height; index 3 is the
  // "low stock" bar rendered in the warning color below the dashed line.
  static const _bars = [0.55, 0.82, 0.68, 0.28, 0.9, 0.62, 0.74];
  static const _lowStockIndex = 3;
  static const _thresholdFraction = 0.4;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC94D);
    const warning = Color(0xFFFF6B52);
    const chartHeight = 108.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock levels',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      'Illustrative preview',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final t = _pulseController.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: gold,
                            boxShadow: [
                              BoxShadow(
                                color: gold.withValues(alpha: 0.55 * (1 - t)),
                                blurRadius: 6 * t,
                                spreadRadius: 2 * t,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: chartHeight,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: chartHeight * _thresholdFraction,
                  child: Row(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          size: const Size(double.infinity, 1),
                          painter: _DashedLinePainter(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'reorder line',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < _bars.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: _bars[i]),
                            duration: Duration(milliseconds: 500 + i * 80),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return FractionallySizedBox(
                                heightFactor: value,
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: i == _lowStockIndex ? warning : gold,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: warning),
              const SizedBox(width: 6),
              Text(
                'Vegetable Oil is below reorder level',
                style: TextStyle(
                  color: warning,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const gap = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}
