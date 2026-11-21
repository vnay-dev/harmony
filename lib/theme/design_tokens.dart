import 'package:flutter/material.dart';

/// Design tokens for colors, spacing, and typography.
///
/// Keep tokens focused on values used by the current UI. Expand only as needed.
class DesignTokens {
  const DesignTokens._();

  // Colors — soft cool blue palette from Harmony home design
  static const Color background = Color(0xFFFBFDFF);
  static const Color backgroundMid = Color(0xFFF2F5FA);
  static const Color backgroundBottom = Color(0xFFCED7E6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF2A3A51);
  static const Color muted = Color(0xFF6B7A90);
  static const Color outline = Color(0xFFCDDBF9);
  static const Color accent = Color(0xFF225EBF);
  static const Color playIcon = Color(0xFF225EBF);
  static const Color playIconUnderReflection = Color(0xFF7A9DD5);
  static const Color primary = Color(0xFF2A3A51);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color playButtonFace = Color(0xFFCED7E6);
  static const Color playButtonHighlight = Color(0xFFEAEFF5);
  static const Color playButtonReflectionTop = Color(0xFFF1F4FA);
  static const Color playButtonReflectionBottom = Color(0xFFDFE4ED);
  static const Color softShadow = Color(0xFFA9B8D0);

  // Listening state — warm cream/peach family (Tutor Mode "Harmony is listening")
  static const Color listeningCore = Color(0xFFFFFDF9);
  static const Color listeningWarm = Color(0xFFFFF7ED);
  static const Color listeningMist = Color(0xFFF9E9D8);
  static const Color listeningSky = Color(0xFFF3DCC6);
  static const Color listeningRim = Color(0xFFE8C9A8);
  static const Color listeningEdge = Color(0xFFD9B48C);

  /// Soft listening cue accent — lighter/warmer than [listeningEdge], same family.
  /// Used by the pitch-direction dial so listening UI stays warm orange, not blue.
  static const Color listeningAccent = Color(0xFFE5B584);

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
  static const double fontSizePitch = 56;

  // Shape & controls
  static const double radiusMd = 12;
  static const double radiusLg = 28;
  static const double radiusPill = 45;
  static const double controlHeight = 56;
  static const double stepButtonSize = 39.2;
  static const double stepButtonIconSize = 22.4;
  static const double stepButtonRadius = 9.8;
  static const double stepButtonGap = 16.8;
  static const double pitchLabelWidth = 108;

  /// Matches the up/down arrow stack: 2 buttons + gap.
  static const double pitchLabelHeight =
      stepButtonSize * 2 + stepButtonGap; // 95.2
  static const double playButtonFrameSize = 200;
  static const double playButtonSize = 122;
  static const double playButtonHaloSize = 169;
  static const double playButtonReflectionHeight = 64;
}
