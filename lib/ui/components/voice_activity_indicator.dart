import 'package:flutter/material.dart';

/// Soft response to microphone energy while the tutor is listening.
///
/// Silence stays small and still. Singing grows the orb. This is not a
/// waveform, pitch graph, or looping decoration.
class VoiceActivityIndicator extends StatelessWidget {
  const VoiceActivityIndicator({super.key, required this.level});

  /// 0 is silence. 1 is a strong sound from the live microphone window.
  final double level;

  static const double restDiameter = 28;
  static const double _span = 56;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final amount = level.clamp(0.0, 1.0);
    final diameter = restDiameter + (_span * amount);
    return Center(
      child: AnimatedContainer(
        key: const ValueKey<String>('voice-activity-orb'),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.primary.withValues(alpha: 0.18 + (0.45 * amount)),
        ),
      ),
    );
  }
}
