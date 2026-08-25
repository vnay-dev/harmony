import 'package:flutter/material.dart';

/// Design tokens for colors, spacing, and typography.
///
/// Keep tokens focused on values used by the current UI. Expand only as needed.
class DesignTokens {
  const DesignTokens._();

  // Colors
  static const Color background = Color(0xFFF7F5F2);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1C1B1A);
  static const Color primary = Color(0xFF2F4A3C);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Spacing
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // Typography
  static const double fontSizeBody = 16;
  static const double fontSizeTitle = 24;
  static const double fontSizeDisplay = 32;
}
