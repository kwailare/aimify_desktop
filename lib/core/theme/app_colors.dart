import 'package:flutter/material.dart';

/// Aimify brand palette, mirrored from aimify-web's `app/globals.css`
/// (`--aimify-*` custom properties). Keep these two files in sync manually —
/// there is no shared design-token package between the web and desktop apps.
class AppColors {
  AppColors._();

  // Light mode
  static const Color goldLight = Color(0xFFD88B00);
  static const Color amberLight = Color(0xFFF2B233);
  static const Color inkLight = Color(0xFF242424);
  static const Color paperLight = Color(0xFFFDF7EC);
  static const Color mutedLight = Color(0xFF4B4B4B);
  static const Color warningLight = Color(0xFFD1453B);

  // Dark mode
  static const Color goldDark = Color(0xFFF2B233);
  static const Color amberDark = Color(0xFFFFC95C);
  static const Color inkDark = Color(0xFFF8F7F3);
  static const Color paperDark = Color(0xFF171717);
  static const Color mutedDark = Color(0xFFE0DCD3);
  static const Color warningDark = Color(0xFFFF6B52);

  // Neutral surfaces used for cards/tables, not part of the web token set
  // but needed for a desktop data-table-heavy UI.
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF242424);
  static const Color successLight = Color(0xFF2F8F5B);
  static const Color successDark = Color(0xFF4ADE80);
}
