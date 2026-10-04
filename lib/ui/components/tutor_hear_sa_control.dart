import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_step.dart';
import 'package:harmony/ui/components/secondary_pill_button.dart';

/// Stage 1 secondary control for hearing a synthesized Sa example.
///
/// Supports idle play/pause, calm loading with a travelling border stroke,
/// and a brief "new sound loaded" affirmation.
class TutorHearSaControl extends StatefulWidget {
  const TutorHearSaControl({
    super.key,
    required this.isPlaying,
    required this.phase,
    required this.onPressed,
  });

  final bool isPlaying;
  final TutorExampleControlPhase phase;
  final VoidCallback? onPressed;

  /// Fixed slot height so loading/loaded labels do not shift layout.
  static const double slotHeight = 48;

  @override
  State<TutorHearSaControl> createState() => _TutorHearSaControlState();
}

class _TutorHearSaControlState extends State<TutorHearSaControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _borderTravel;

  @override
  void initState() {
    super.initState();
    _borderTravel = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _syncBorder();
  }

  @override
  void didUpdateWidget(covariant TutorHearSaControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _syncBorder();
    }
  }

  void _syncBorder() {
    if (widget.phase == TutorExampleControlPhase.loading) {
      if (!_borderTravel.isAnimating) {
        _borderTravel.repeat();
      }
    } else {
      _borderTravel
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _borderTravel.dispose();
    super.dispose();
  }

  String get _label {
    switch (widget.phase) {
      case TutorExampleControlPhase.loading:
        return TutorScripts.exampleLoadingLabel;
      case TutorExampleControlPhase.loaded:
        return TutorScripts.exampleLoadedLabel;
      case TutorExampleControlPhase.idle:
        return TutorScripts.hearSaLabel;
    }
  }

  Widget _icon() {
    switch (widget.phase) {
      case TutorExampleControlPhase.loading:
        return const SizedBox(
          key: ValueKey<String>('tutor-hear-sa-loading'),
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: DesignTokens.onSurface,
          ),
        );
      case TutorExampleControlPhase.loaded:
        return const Icon(
          Icons.check_rounded,
          key: ValueKey<String>('tutor-hear-sa-loaded'),
          size: 20,
          color: DesignTokens.onSurface,
        );
      case TutorExampleControlPhase.idle:
        return Icon(
          widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey<String>(
            widget.isPlaying ? 'tutor-hear-sa-pause' : 'tutor-hear-sa-play',
          ),
          size: 20,
          color: DesignTokens.onSurface,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.phase == TutorExampleControlPhase.idle;
    final loading = widget.phase == TutorExampleControlPhase.loading;

    return SizedBox(
      height: TutorHearSaControl.slotHeight,
      child: Center(
        child: AnimatedBuilder(
          animation: _borderTravel,
          builder: (context, child) {
            final pill = SecondaryPillButton(
              key: const ValueKey<String>('tutor-hear-sa'),
              label: _label,
              onPressed: interactive ? widget.onPressed : null,
              iconLeading: true,
              borderColor: loading
                  ? Colors.transparent
                  : DesignTokens.onSurface,
              borderWidth: 1,
              icon: _icon(),
            );
            if (!loading) {
              return pill;
            }
            return CustomPaint(
              foregroundPainter: _TravellingBorderPainter(
                progress: _borderTravel.value,
                radius: DesignTokens.radiusPill,
                color: DesignTokens.accent,
              ),
              child: pill,
            );
          },
        ),
      ),
    );
  }
}

/// Soft highlight that travels around the pill stroke while loading.
class _TravellingBorderPainter extends CustomPainter {
  const _TravellingBorderPainter({
    required this.progress,
    required this.radius,
    required this.color,
  });

  final double progress;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.75), Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = DesignTokens.onSurface.withValues(alpha: 0.22);
    canvas.drawRRect(rrect, base);

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.05),
          color.withValues(alpha: 0.85),
          color.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(progress * 2 * math.pi - math.pi / 2),
      ).createShader(rect);
    canvas.drawPath(path, sweep);
  }

  @override
  bool shouldRepaint(covariant _TravellingBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.radius != radius ||
        oldDelegate.color != color;
  }
}

/// Tertiary one-line text action that asks for a different example sound.
class TutorShuffleExampleAction extends StatelessWidget {
  const TutorShuffleExampleAction({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback? onPressed;

  static const double slotHeight = 32;

  @override
  Widget build(BuildContext context) {
    final color = DesignTokens.muted.withValues(alpha: enabled ? 1 : 0.45);
    final base = Theme.of(context).textTheme.labelLarge;
    return SizedBox(
      height: TutorShuffleExampleAction.slotHeight,
      child: Center(
        child: GestureDetector(
          key: const ValueKey<String>('tutor-shuffle-example'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: color)),
                  ),
                  child: Text(
                    TutorScripts.shuffleExamplePrompt,
                    maxLines: 1,
                    softWrap: false,
                    style: base?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: color,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.shuffle_rounded,
                  key: const ValueKey<String>('tutor-shuffle-example-icon'),
                  size: 16,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
