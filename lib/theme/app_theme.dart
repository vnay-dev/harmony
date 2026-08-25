import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';

/// Builds the app [ThemeData] from [DesignTokens].
class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.light(
      primary: DesignTokens.primary,
      onPrimary: DesignTokens.onPrimary,
      surface: DesignTokens.surface,
      onSurface: DesignTokens.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DesignTokens.background,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: DesignTokens.fontSizeDisplay,
          fontWeight: FontWeight.w600,
          color: DesignTokens.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: DesignTokens.fontSizeTitle,
          fontWeight: FontWeight.w600,
          color: DesignTokens.onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: DesignTokens.fontSizeBody,
          color: DesignTokens.onSurface,
        ),
      ),
    );
  }
}
