import 'package:flutter/material.dart';

import 'package:harmony/pitch/assist_range_targets.dart';
import 'package:harmony/theme/design_tokens.dart';

/// Simple LOW → MIDDLE → HIGH guide for the Stage 2 range exercise.
///
/// Shows where the current target sits and, when available, where the user's
/// voice is — without Hz, cents, or other technical labels.
class AssistRangeGuide extends StatelessWidget {
  const AssistRangeGuide({
    super.key,
    required this.currentPoint,
    required this.targetPosition,
    this.voicePosition,
    this.matched = false,
  });

  final AssistRangePoint currentPoint;
  final double targetPosition;
  final double? voicePosition;
  final bool matched;

  static const double _trackHeight = 220;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final clampedTarget = targetPosition.clamp(0.0, 1.0);
    final voice = voicePosition?.clamp(0.0, 1.0);

    return SizedBox(
      key: const ValueKey<String>('assist-range-guide'),
      height: _trackHeight + 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _axisLabel(textTheme, colorScheme, 'High'),
                _axisLabel(textTheme, colorScheme, 'Mid'),
                _axisLabel(textTheme, colorScheme, 'Low'),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spaceMd),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 4,
                              height: height,
                              decoration: BoxDecoration(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          ..._rungMarkers(colorScheme, height),
                          if (voice != null)
                            _marker(
                              top: (1.0 - voice) * height - 10,
                              color: colorScheme.tertiary,
                              size: 20,
                              keyName: 'assist-range-voice-marker',
                              child: Icon(
                                Icons.circle,
                                size: 12,
                                color: colorScheme.onTertiary,
                              ),
                            ),
                          _marker(
                            top: (1.0 - clampedTarget) * height - 14,
                            color: matched
                                ? colorScheme.primary
                                : colorScheme.secondary,
                            size: 28,
                            keyName: 'assist-range-target-marker',
                            child: Icon(
                              matched ? Icons.check : Icons.music_note,
                              size: 16,
                              color: matched
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                Text(
                  AssistRangeTargets.labelFor(currentPoint),
                  key: ValueKey<String>('assist-range-point-$currentPoint'),
                  style: textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(width: 56),
        ],
      ),
    );
  }

  List<Widget> _rungMarkers(ColorScheme colorScheme, double height) {
    // Lower Sa, Pa (~perfect fifth), Upper Sa on a one-octave guide.
    const rungs = <double>[0.0, 700 / 1200, 1.0];
    return [
      for (final rung in rungs)
        Positioned(
          top: (1.0 - rung) * height - 1,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 28,
              height: 2,
              color: colorScheme.onSurface.withValues(alpha: 0.20),
            ),
          ),
        ),
    ];
  }

  Widget _marker({
    required double top,
    required Color color,
    required double size,
    required String keyName,
    required Widget child,
  }) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          key: ValueKey<String>(keyName),
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _axisLabel(
    TextTheme textTheme,
    ColorScheme colorScheme,
    String label,
  ) {
    return Text(
      label,
      style: textTheme.labelMedium?.copyWith(
        color: colorScheme.onSurface.withValues(alpha: 0.56),
      ),
    );
  }
}
