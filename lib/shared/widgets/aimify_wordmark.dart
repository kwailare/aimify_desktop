import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The exact "Aimify" wordmark aimify-web uses in its own app chrome
/// (dashboard/admin/onboarding sidebars, the auth pages) — see
/// `.brand-primary` / `.brand-accent` in that project's `app/globals.css`
/// and their usage as two adjacent spans, e.g. in `components/auth-shell.tsx`:
/// `<span className="brand-primary">Aimi</span><span className="brand-accent">fy</span>`.
///
/// Not the PNG icon from aimify-web's marketing hero section — that mark is
/// only used on the public landing page, never in its authenticated app
/// shell, so it isn't the "same brand logo" for a screen like this one.
///
/// Reproduces: "Aimi" in Space Grotesk 700 at the base size, "fy" ~25%
/// larger in italic Instrument Serif and gold-vivid (`#ff9d0a`, constant in
/// both the web app's light and dark themes), plus the small gold dot
/// flourish CSS draws via `.brand-accent::after`. The dot's position is an
/// approximation — Flutter has no direct equivalent of an absolutely
/// positioned pseudo-element anchored to inline text.
class AimifyWordmark extends StatelessWidget {
  const AimifyWordmark({super.key, this.fontSize = 22, this.inkColor});

  /// Size of the "Aimi" run, in logical pixels; "fy" renders ~25% larger to
  /// match the CSS's 1.4rem / 1.75rem ratio.
  final double fontSize;

  /// Overrides the "Aimi" color instead of deriving it from the ambient
  /// theme — needed on surfaces with a fixed background regardless of
  /// light/dark mode, e.g. the login screen's always-dark brand panel.
  final Color? inkColor;

  static const _goldVivid = Color(0xFFFF9D0A);
  static const _amberBright = Color(0xFFFFC94D);

  @override
  Widget build(BuildContext context) {
    final ink = inkColor ??
        Theme.of(context).textTheme.bodyLarge?.color ??
        Theme.of(context).colorScheme.onSurface;
    final accentSize = fontSize * 1.25;
    final dotSize = accentSize * 0.2;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Aimi',
            style: GoogleFonts.spaceGrotesk(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.01 * fontSize,
              color: ink,
              height: 1,
            ),
          ),
          TextSpan(
            text: 'fy',
            style: GoogleFonts.instrumentSerif(
              fontSize: accentSize,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w400,
              color: _goldVivid,
              height: 1,
            ),
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Transform.translate(
              offset: Offset(2, -dotSize * 0.6),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_amberBright, _goldVivid],
                  ),
                  boxShadow: [
                    BoxShadow(color: _goldVivid, blurRadius: 4, spreadRadius: 0.2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
