import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';

/// Subtle pitch-direction cue: too low ← on target → too high.
///
/// Uses signed cents from the existing Stage 2 matcher. Null [centsFromTarget]
/// keeps the indicator soft and centered so silence never misleads.
class PitchDirectionDial extends StatefulWidget {
  const PitchDirectionDial({
    super.key,
    required this.centsFromTarget,
    this.visible = true,
  });

  /// Signed cents error. Positive = sharp / too high. Null = no reliable pitch.
  final double? centsFromTarget;

  /// When false, the dial fades to a subdued idle state.
  final bool visible;

  /// Visual full-scale magnitude in cents (±).
  static const double visualRangeCents = 100;

  /// Matcher tolerance treated as "near target" for soft confirmation.
  static const double nearTargetCents = 50;

  /// Especially satisfying zone around center.
  static const double sweetSpotCents = 18;

  static const double height = 36;

  @override
  State<PitchDirectionDial> createState() => _PitchDirectionDialState();
}

class _PitchDirectionDialState extends State<PitchDirectionDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  /// Smoothed normalized position in `[-1, 1]`.
  double _display = 0;

  /// Target normalized position from the latest cents reading.
  double _target = 0;

  /// 0 = inactive / no pitch, 1 = live pitch driving the indicator.
  double _liveAmount = 0;
  double _liveTarget = 0;

  /// Soft confirmation when near / on target.
  double _centerGlow = 0;

  static const double _smoothing = 0.16;
  static const double _liveSmoothing = 0.12;

  @override
  void initState() {
    super.initState();
    _applyCents(widget.centsFromTarget, animate: false);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onTick);
    if (widget.visible) {
      _ensureTicking();
    }
  }

  @override
  void didUpdateWidget(covariant PitchDirectionDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyCents(widget.centsFromTarget, animate: true);
    if (!widget.visible) {
      _liveTarget = 0;
      _target = 0;
    }
    _ensureTicking();
  }

  void _ensureTicking() {
    if (!_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _applyCents(double? cents, {required bool animate}) {
    if (cents == null) {
      _liveTarget = 0;
      _target = 0;
      if (!animate) {
        _liveAmount = 0;
        _display = 0;
        _centerGlow = 0;
      }
      return;
    }

    _liveTarget = 1;
    final clamped = (cents / PitchDirectionDial.visualRangeCents).clamp(
      -1.0,
      1.0,
    );
    // Ease large errors so edges feel controlled; keep near-zero expressive.
    final shaped = Curves.easeOut.transform(clamped.abs()) * clamped.sign;
    _target = shaped;
    if (!animate) {
      _liveAmount = 1;
      _display = shaped;
      _centerGlow = _glowForCents(cents);
    }
  }

  double _glowForCents(double cents) {
    final abs = cents.abs();
    if (abs <= PitchDirectionDial.sweetSpotCents) {
      return 1.0;
    }
    if (abs >= PitchDirectionDial.nearTargetCents) {
      return 0.0;
    }
    final t =
        (PitchDirectionDial.nearTargetCents - abs) /
        (PitchDirectionDial.nearTargetCents -
            PitchDirectionDial.sweetSpotCents);
    return Curves.easeOut.transform(t.clamp(0.0, 1.0));
  }

  void _onTick() {
    if (!mounted) {
      return;
    }
    final nextDisplay = _display + (_target - _display) * _smoothing;
    final nextLive = _liveAmount + (_liveTarget - _liveAmount) * _liveSmoothing;
    final glowTarget = widget.centsFromTarget == null
        ? 0.0
        : _glowForCents(widget.centsFromTarget!);
    final nextGlow = _centerGlow + (glowTarget - _centerGlow) * 0.14;

    final settled =
        (nextDisplay - _target).abs() < 0.001 &&
        (nextLive - _liveTarget).abs() < 0.001 &&
        (nextGlow - glowTarget).abs() < 0.001;

    setState(() {
      _display = nextDisplay;
      _liveAmount = nextLive;
      _centerGlow = nextGlow;
    });

    // Stop when settled so widget tests using pumpAndSettle can finish.
    if (settled) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantics = _semanticsLabel();
    return Semantics(
      label: semantics,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: widget.visible ? 1 : 0,
        child: SizedBox(
          key: const ValueKey<String>('pitch-direction-dial'),
          height: PitchDirectionDial.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _PitchDirectionDialPainter(
              position: _display,
              liveAmount: _liveAmount.clamp(0.0, 1.0),
              centerGlow: _centerGlow.clamp(0.0, 1.0),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel() {
    final cents = widget.centsFromTarget;
    if (!widget.visible) {
      return 'Pitch direction idle';
    }
    if (cents == null) {
      return 'Listening for your pitch';
    }
    if (cents.abs() <= PitchDirectionDial.sweetSpotCents) {
      return 'On target';
    }
    if (cents < 0) {
      return 'A little low — go higher';
    }
    return 'A little high — go lower';
  }
}

class _PitchDirectionDialPainter extends CustomPainter {
  const _PitchDirectionDialPainter({
    required this.position,
    required this.liveAmount,
    required this.centerGlow,
  });

  final double position;
  final double liveAmount;
  final double centerGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackLeft = size.width * 0.12;
    final trackRight = size.width * 0.88;
    final trackWidth = trackRight - trackLeft;
    final trackCenter = Offset((trackLeft + trackRight) / 2, centerY);

    final trackPaint = Paint()
      ..color = DesignTokens.outline.withValues(alpha: 0.55 + 0.25 * liveAmount)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(trackLeft, centerY),
      Offset(trackRight, centerY),
      trackPaint,
    );

    // Soft end hints — direction without technical labels.
    _drawChevron(
      canvas,
      Offset(trackLeft - 10, centerY),
      pointingLeft: true,
      opacity: 0.28 + 0.22 * liveAmount,
    );
    _drawChevron(
      canvas,
      Offset(trackRight + 10, centerY),
      pointingLeft: false,
      opacity: 0.28 + 0.22 * liveAmount,
    );

    // Center resting mark — warm listening accent (not guiding blue).
    final centerMarkPaint = Paint()
      ..color = DesignTokens.listeningAccent.withValues(
        alpha: 0.18 + 0.35 * centerGlow,
      )
      ..style = PaintingStyle.fill;
    canvas.drawCircle(trackCenter, 2.4 + centerGlow * 1.2, centerMarkPaint);

    if (centerGlow > 0.02) {
      final glowPaint = Paint()
        ..color = DesignTokens.listeningAccent.withValues(
          alpha: 0.10 * centerGlow,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(trackCenter, 14 + centerGlow * 6, glowPaint);
    }

    final indicatorX = trackCenter.dx + position * (trackWidth / 2);
    final indicatorCenter = Offset(indicatorX, centerY);
    final indicatorRadius = 5.2 + centerGlow * 1.4;

    final haloPaint = Paint()
      ..color = DesignTokens.listeningAccent.withValues(
        alpha: (0.10 + 0.18 * liveAmount + 0.16 * centerGlow).clamp(0.0, 0.4),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(indicatorCenter, indicatorRadius + 5, haloPaint);

    final fillPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              DesignTokens.surface.withValues(alpha: 0.95),
              DesignTokens.listeningAccent.withValues(
                alpha: 0.55 + 0.35 * liveAmount,
              ),
            ],
            stops: const [0.15, 1],
          ).createShader(
            Rect.fromCircle(center: indicatorCenter, radius: indicatorRadius),
          );
    canvas.drawCircle(indicatorCenter, indicatorRadius, fillPaint);

    final rimPaint = Paint()
      ..color = DesignTokens.listeningAccent.withValues(
        alpha: 0.35 + 0.45 * liveAmount,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(indicatorCenter, indicatorRadius, rimPaint);
  }

  void _drawChevron(
    Canvas canvas,
    Offset tip, {
    required bool pointingLeft,
    required double opacity,
  }) {
    final paint = Paint()
      ..color = DesignTokens.muted.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dir = pointingLeft ? -1.0 : 1.0;
    final path = Path()
      ..moveTo(tip.dx - dir * 4, tip.dy - 4)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - dir * 4, tip.dy + 4);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PitchDirectionDialPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.liveAmount != liveAmount ||
        oldDelegate.centerGlow != centerGlow;
  }
}
