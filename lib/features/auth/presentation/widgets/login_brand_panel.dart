import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/widgets/aimify_wordmark.dart';
import 'stock_pulse_card.dart';

/// Dark, illustrated panel shown alongside the login form on wide windows —
/// deliberately a fixed dark background regardless of light/dark app theme
/// (mirrors how aimify-web's own hero section leans darker/richer than its
/// everyday UI), with the same warm gold/amber blooms as that project's
/// `.scene` background treatment, just inverted onto ink instead of paper.
class LoginBrandPanel extends StatelessWidget {
  const LoginBrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF171717),
      child: Stack(
        children: [
          const Positioned.fill(child: _BackgroundBlooms()),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 56, 56, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AimifyWordmark(fontSize: 26, inkColor: Colors.white),
                const SizedBox(height: 28),
                Text(
                  'Run the warehouse\nfrom one screen.',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 34,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Stock, purchases, sales and customer balances — the same '
                  'ledger your whole team works from, kept in sync the '
                  'moment something moves.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 14.5,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 36),
                const StockPulseCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundBlooms extends StatelessWidget {
  const _BackgroundBlooms();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -100,
            child: _bloom(const Color(0xFFFFC95C), 340),
          ),
          Positioned(
            bottom: -160,
            right: -120,
            child: _bloom(const Color(0xFFD88B00), 380),
          ),
          Positioned(
            top: 220,
            right: -80,
            child: _bloom(const Color(0xFFF2B233), 220),
          ),
        ],
      ),
    );
  }

  Widget _bloom(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
