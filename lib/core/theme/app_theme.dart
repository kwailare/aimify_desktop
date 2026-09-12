import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Builds the light/dark [ThemeData] for the app from the Aimify brand
/// tokens in [AppColors]. Headings use Space Grotesk, body text Manrope —
/// same pairing as aimify-web.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(brightness: Brightness.light);

  static ThemeData dark() => _build(brightness: Brightness.dark);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    final gold = isDark ? AppColors.goldDark : AppColors.goldLight;
    final amber = isDark ? AppColors.amberDark : AppColors.amberLight;
    final ink = isDark ? AppColors.inkDark : AppColors.inkLight;
    final paper = isDark ? AppColors.paperDark : AppColors.paperLight;
    final muted = isDark ? AppColors.mutedDark : AppColors.mutedLight;
    final warning = isDark ? AppColors.warningDark : AppColors.warningLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: gold,
      onPrimary: isDark ? AppColors.inkLight : Colors.white,
      secondary: amber,
      onSecondary: isDark ? AppColors.inkLight : Colors.white,
      error: warning,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: isDark
          ? const Color(0xFF2E2E2E)
          : const Color(0xFFF3ECDD),
      outline: muted.withValues(alpha: 0.35),
    );

    final headingFont = GoogleFonts.spaceGroteskTextTheme();
    final bodyFont = GoogleFonts.manropeTextTheme();

    final textTheme = bodyFont
        .copyWith(
          displayLarge: headingFont.displayLarge,
          displayMedium: headingFont.displayMedium,
          displaySmall: headingFont.displaySmall,
          headlineLarge: headingFont.headlineLarge,
          headlineMedium: headingFont.headlineMedium,
          headlineSmall: headingFont.headlineSmall,
          titleLarge: headingFont.titleLarge,
          titleMedium: headingFont.titleMedium,
          titleSmall: headingFont.titleSmall,
        )
        .apply(bodyColor: ink, displayColor: ink);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: paper,
      textTheme: textTheme,
      fontFamily: bodyFont.bodyMedium?.fontFamily,
      dividerColor: muted.withValues(alpha: 0.15),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: gold.withValues(alpha: 0.18)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        titleTextStyle: headingFont.titleLarge?.copyWith(color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: muted.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: muted.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gold, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: gold.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: gold),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: amber.withValues(alpha: 0.14),
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: gold),
        selectedLabelTextStyle: TextStyle(
          color: gold,
          fontWeight: FontWeight.w700,
        ),
        unselectedIconTheme: IconThemeData(color: muted),
        unselectedLabelTextStyle: TextStyle(color: muted),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(fontWeight: FontWeight.w700, color: ink),
        dataTextStyle: TextStyle(color: ink),
        dividerThickness: 0.6,
      ),
    );
  }
}
