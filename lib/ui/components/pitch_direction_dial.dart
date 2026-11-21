import 'dart:async';

import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';

/// Pitch-direction cue: too low ← on target → too high.
///
/// Uses signed cents from the existing Stage 2 matcher. Null [centsFromTarget]
/// holds the last valid cue briefly, then returns to a neutral listening state
/// so brief detection gaps never mislead.
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

  /// Matcher tolerance treated as the green target zone (±).
  static const double nearTargetCents = 50;

  /// Especially satisfying zone around center (glow strength).
  static const double sweetSpotCents = 18;

  /// How long to keep the last valid cue after cents become null.
  static const Duration nullHoldDuration = Duration(milliseconds: 250);

  /// Extra cents before leaving / entering the on-pitch zone at the ±50 edge.
  static const double zoneHysteresisCents = 8;

  /// Track height used by the painted dial.
  static const double trackHeight = 36;

  /// Soft green for the in-tolerance target zone and indicator.
  static const Color targetZoneColor = Color(0xFF5B9A6F);

  /// Soft red for out-of-tolerance zones and indicator.
  static const Color outsideZoneColor = Color(0xFFC4746A);

  @override
  State<PitchDirectionDial> createState() => _PitchDirectionDialState();
}

enum _PitchFeedbackZone { listening, low, onPitch, high }

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

  /// Last valid cents driving the visual cue (may outlive a brief null).
  double? _heldCents;

  _PitchFeedbackZone _zone = _PitchFeedbackZone.listening;

  Timer? _nullHoldTimer;

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
    if (!widget.visible) {
      _cancelNullHold();
      _heldCents = null;
      _zone = _PitchFeedbackZone.listening;
      _liveTarget = 0;
      _target = 0;
    } else {
      _applyCents(widget.centsFromTarget, animate: true);
    }
    _ensureTicking();
  }

  void _ensureTicking() {
    if (!_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _cancelNullHold() {
    _nullHoldTimer?.cancel();
    _nullHoldTimer = null;
  }

  void _scheduleNullHoldReset() {
    _cancelNullHold();
    _nullHoldTimer = Timer(PitchDirectionDial.nullHoldDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _heldCents = null;
        _zone = _PitchFeedbackZone.listening;
        _liveTarget = 0;
        _target = 0;
      });
      _ensureTicking();
    });
  }

  void _applyCents(double? cents, {required bool animate}) {
    if (cents == null) {
      if (!animate) {
        _cancelNullHold();
        _heldCents = null;
        _zone = _PitchFeedbackZone.listening;
        _liveTarget = 0;
        _target = 0;
        _liveAmount = 0;
        _display = 0;
        _centerGlow = 0;
        return;
      }

      // Keep the last valid visual cue briefly; ignore repeat nulls mid-hold.
      if (_heldCents == null) {
        _liveTarget = 0;
        _target = 0;
        return;
      }
      if (_nullHoldTimer == null) {
        _scheduleNullHoldReset();
      }
      return;
    }

    _cancelNullHold();
    _heldCents = cents;
    _zone = _classifyWithHysteresis(cents);
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

  _PitchFeedbackZone _classifyWithHysteresis(double cents) {
    final abs = cents.abs();
    const band = PitchDirectionDial.nearTargetCents;
    const h = PitchDirectionDial.zoneHysteresisCents;

    switch (_zone) {
      case _PitchFeedbackZone.onPitch:
        if (abs <= band + h) {
          return _PitchFeedbackZone.onPitch;
        }
        return cents < 0 ? _PitchFeedbackZone.low : _PitchFeedbackZone.high;
      case _PitchFeedbackZone.low:
        if (cents > 0 && abs > band - h) {
          return _PitchFeedbackZone.high;
        }
        if (abs <= band - h) {
          return _PitchFeedbackZone.onPitch;
        }
        return _PitchFeedbackZone.low;
      case _PitchFeedbackZone.high:
        if (cents < 0 && abs > band - h) {
          return _PitchFeedbackZone.low;
        }
        if (abs <= band - h) {
          return _PitchFeedbackZone.onPitch;
        }
        return _PitchFeedbackZone.high;
      case _PitchFeedbackZone.listening:
        if (abs <= band) {
          return _PitchFeedbackZone.onPitch;
        }
        return cents < 0 ? _PitchFeedbackZone.low : _PitchFeedbackZone.high;
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

  Color get _indicatorColor {
    switch (_zone) {
      case _PitchFeedbackZone.onPitch:
        return PitchDirectionDial.targetZoneColor;
      case _PitchFeedbackZone.low:
      case _PitchFeedbackZone.high:
        return PitchDirectionDial.outsideZoneColor;
      case _PitchFeedbackZone.listening:
        return DesignTokens.listeningAccent;
    }
  }

  String get _guidanceText {
    if (!widget.visible) {
      return '';
    }
    switch (_zone) {
      case _PitchFeedbackZone.listening:
        return 'Listening for your pitch';
      case _PitchFeedbackZone.low:
        return 'Sing higher';
      case _PitchFeedbackZone.onPitch:
        return 'On pitch';
      case _PitchFeedbackZone.high:
        return 'Sing lower';
    }
  }

  void _onTick() {
    if (!mounted) {
      return;
    }
    final nextDisplay = _display + (_target - _display) * _smoothing;
    final nextLive = _liveAmount + (_liveTarget - _liveAmount) * _liveSmoothing;
    final held = _heldCents;
    final glowTarget = held == null ? 0.0 : _glowForCents(held);
    final nextGlow = _centerGlow + (glowTarget - _centerGlow) * 0.14;

    final settled =
        (nextDisplay - _target).abs() < 0.001 &&
        (nextLive - _liveTarget).abs() < 0.001 &&
        (nextGlow - glowTarget).abs() < 0.001 &&
        _nullHoldTimer == null;

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
    _cancelNullHold();
    _ticker
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final semantics = _semanticsLabel();
    final guidance = _guidanceText;

    return Semantics(
      label: semantics,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: widget.visible ? 1 : 0,
        child: Column(
          key: const ValueKey<String>('pitch-direction-dial'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: PitchDirectionDial.trackHeight,
              width: double.infinity,
              child: CustomPaint(
                painter: _PitchDirectionDialPainter(
                  position: _display,
                  liveAmount: _liveAmount.clamp(0.0, 1.0),
                  centerGlow: _centerGlow.clamp(0.0, 1.0),
                  indicatorColor: _indicatorColor,
                  zoneLive: _zone != _PitchFeedbackZone.listening,
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Text(
              guidance,
              key: const ValueKey<String>('pitch-direction-guidance'),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: _zone == _PitchFeedbackZone.listening
                    ? DesignTokens.muted
                    : DesignTokens.onSurface,
                fontWeight: _zone == _PitchFeedbackZone.listening
                    ? FontWeight.w400
                    : FontWeight.w600,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXs),
            const _PitchZoneLegend(),
          ],
        ),
      ),
    );
  }

  String _semanticsLabel() {
    if (!widget.visible) {
      return 'Pitch direction idle';
    }
    switch (_zone) {
      case _PitchFeedbackZone.listening:
        return 'Listening for your pitch';
      case _PitchFeedbackZone.low:
        return 'Sing higher';
      case _PitchFeedbackZone.onPitch:
        return 'On pitch';
      case _PitchFeedbackZone.high:
        return 'Sing lower';
    }
  }
}

class _PitchZoneLegend extends StatelessWidget {
  const _PitchZoneLegend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: DesignTokens.muted, fontSize: 12);
    return Row(
      key: const ValueKey<String>('pitch-direction-legend'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendSwatch(PitchDirectionDial.targetZoneColor),
        const SizedBox(width: 4),
        Text('Target zone', style: style),
        const SizedBox(width: DesignTokens.spaceMd),
        _legendSwatch(PitchDirectionDial.outsideZoneColor),
        const SizedBox(width: 4),
        Text('Outside', style: style),
      ],
    );
  }

  Widget _legendSwatch(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PitchDirectionDialPainter extends CustomPainter {
  const _PitchDirectionDialPainter({
    required this.position,
    required this.liveAmount,
    required this.centerGlow,
    required this.indicatorColor,
    required this.zoneLive,
  });

  final double position;
  final double liveAmount;
  final double centerGlow;
  final Color indicatorColor;
  final bool zoneLive;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackLeft = size.width * 0.12;
    final trackRight = size.width * 0.88;
    final trackWidth = trackRight - trackLeft;
    final trackCenter = Offset((trackLeft + trackRight) / 2, centerY);

    // Zone band half-width in track units (normalized [-1, 1] → pixels).
    final zoneHalf =
        (PitchDirectionDial.nearTargetCents /
                PitchDirectionDial.visualRangeCents)
            .clamp(0.0, 1.0);
    // Match the easeOut shaping used by the indicator so the painted band
    // aligns with where an on-pitch reading visually sits.
    final shapedHalf = Curves.easeOut.transform(zoneHalf);
    final greenHalfWidth = shapedHalf * (trackWidth / 2);
    final greenLeft = trackCenter.dx - greenHalfWidth;
    final greenRight = trackCenter.dx + greenHalfWidth;

    final zoneAlpha = 0.22 + 0.18 * liveAmount;
    final redPaint = Paint()
      ..color = PitchDirectionDial.outsideZoneColor.withValues(alpha: zoneAlpha)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final greenPaint = Paint()
      ..color = PitchDirectionDial.targetZoneColor.withValues(
        alpha: zoneAlpha + 0.08,
      )
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Red outer segments.
    canvas.drawLine(
      Offset(trackLeft, centerY),
      Offset(greenLeft, centerY),
      redPaint,
    );
    canvas.drawLine(
      Offset(greenRight, centerY),
      Offset(trackRight, centerY),
      redPaint,
    );
    // Green center target zone (±50 cents).
    canvas.drawLine(
      Offset(greenLeft, centerY),
      Offset(greenRight, centerY),
      greenPaint,
    );

    // Soft baseline track for definition.
    final trackPaint = Paint()
      ..color = DesignTokens.outline.withValues(alpha: 0.35 + 0.15 * liveAmount)
      ..strokeWidth = 1.2
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

    // Center resting mark.
    final centerMarkColor = zoneLive
        ? PitchDirectionDial.targetZoneColor
        : DesignTokens.listeningAccent;
    final centerMarkPaint = Paint()
      ..color = centerMarkColor.withValues(alpha: 0.18 + 0.35 * centerGlow)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(trackCenter, 2.4 + centerGlow * 1.2, centerMarkPaint);

    if (centerGlow > 0.02) {
      final glowPaint = Paint()
        ..color = PitchDirectionDial.targetZoneColor.withValues(
          alpha: 0.12 * centerGlow,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(trackCenter, 14 + centerGlow * 6, glowPaint);
    }

    final indicatorX = trackCenter.dx + position * (trackWidth / 2);
    final indicatorCenter = Offset(indicatorX, centerY);
    final indicatorRadius = 5.2 + centerGlow * 1.4;

    final haloPaint = Paint()
      ..color = indicatorColor.withValues(
        alpha: (0.10 + 0.18 * liveAmount + 0.16 * centerGlow).clamp(0.0, 0.4),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(indicatorCenter, indicatorRadius + 5, haloPaint);

    final fillPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              DesignTokens.surface.withValues(alpha: 0.95),
              indicatorColor.withValues(alpha: 0.55 + 0.35 * liveAmount),
            ],
            stops: const [0.15, 1],
          ).createShader(
            Rect.fromCircle(center: indicatorCenter, radius: indicatorRadius),
          );
    canvas.drawCircle(indicatorCenter, indicatorRadius, fillPaint);

    final rimPaint = Paint()
      ..color = indicatorColor.withValues(alpha: 0.35 + 0.45 * liveAmount)
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
        oldDelegate.centerGlow != centerGlow ||
        oldDelegate.indicatorColor != indicatorColor ||
        oldDelegate.zoneLive != zoneLive;
  }
}
