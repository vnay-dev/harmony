import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/tutor/tutor_step.dart';

/// Persistent circle representing Harmony's presence.
///
/// Soft white-core orb with a gentle blue rim. While speaking, radius breathes
/// calmly. While listening, the orb shifts to the warm [DesignTokens] listening
/// palette and gently follows smoothed microphone energy — calm until the user
/// sings. Layout and animation are isolated from transcript updates in the parent.
class TutorPresenceCircle extends StatefulWidget {
  const TutorPresenceCircle({
    super.key,
    required this.state,
    this.voiceLevel = 0,
  });

  final TutorPresenceState state;

  /// 0–1 microphone energy while listening. Ignored otherwise.
  final double voiceLevel;

  static const double baseSize = 148;

  /// Outer slot that keeps the circle's center fixed while radius changes.
  static const double slotSize = baseSize + 56;

  @override
  State<TutorPresenceCircle> createState() => _TutorPresenceCircleState();
}

class _TutorPresenceCircleState extends State<TutorPresenceCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  TutorPresenceState? _pulsingFor;

  /// EMA of [voiceLevel] for jitter-free size response while listening.
  double _smoothedVoice = 0;

  static const double _voiceAttack = 0.16;
  static const double _voiceRelease = 0.08;
  static const double _voiceIdleThreshold = 0.06;
  static const double _maxVoiceBoost = 22;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant TutorPresenceCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      if (widget.state != TutorPresenceState.listening) {
        _smoothedVoice = 0;
      }
      _syncPulse();
    }
  }

  void _syncPulse() {
    switch (widget.state) {
      case TutorPresenceState.speaking:
        _startPulse(
          TutorPresenceState.speaking,
          const Duration(milliseconds: 1800),
        );
      case TutorPresenceState.listening:
        // Short ticker drives per-frame voice smoothing; size does not
        // breathe from the pulse value itself while calm.
        _startPulse(
          TutorPresenceState.listening,
          const Duration(milliseconds: 1000),
        );
      case TutorPresenceState.success:
      case TutorPresenceState.idle:
        _pulsingFor = null;
        _pulse
          ..stop()
          ..value = 0.35;
    }
  }

  void _startPulse(TutorPresenceState state, Duration duration) {
    if (_pulsingFor == state &&
        _pulse.duration == duration &&
        _pulse.isAnimating) {
      return;
    }
    _pulsingFor = state;
    _pulse
      ..duration = duration
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  double _advanceSmoothedVoice(double target) {
    final rate = target > _smoothedVoice ? _voiceAttack : _voiceRelease;
    _smoothedVoice += (target - _smoothedVoice) * rate;
    if (_smoothedVoice < 0.001) {
      _smoothedVoice = 0;
    }
    return _smoothedVoice;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: switch (widget.state) {
        TutorPresenceState.speaking => 'Harmony is speaking',
        TutorPresenceState.listening => 'Harmony is listening',
        TutorPresenceState.success => 'Harmony heard you',
        TutorPresenceState.idle => 'Harmony',
      },
      child: SizedBox(
        width: TutorPresenceCircle.slotSize,
        height: TutorPresenceCircle.slotSize,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final pulse = _pulse.value;
            final isListening = widget.state == TutorPresenceState.listening;

            var listeningBoost = 0.0;
            if (isListening) {
              final target = widget.voiceLevel.clamp(0.0, 1.0);
              final smoothed = _advanceSmoothedVoice(target);
              if (smoothed > _voiceIdleThreshold) {
                final t =
                    ((smoothed - _voiceIdleThreshold) /
                            (1.0 - _voiceIdleThreshold))
                        .clamp(0.0, 1.0);
                listeningBoost = Curves.easeOut.transform(t) * _maxVoiceBoost;
              }
            }

            final speakBoost = widget.state == TutorPresenceState.speaking
                ? 8 + pulse * 20
                : 0.0;
            final size =
                TutorPresenceCircle.baseSize + speakBoost + listeningBoost;

            return CustomPaint(
              painter: _PresencePainter(
                circleSize: size,
                listening: isListening,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PresencePainter extends CustomPainter {
  const _PresencePainter({
    required this.circleSize,
    required this.listening,
  });

  final double circleSize;
  final bool listening;

  // Calm guiding palette (Harmony speaking / idle).
  static const _mist = Color(0xFFEAF3FC);
  static const _sky = Color(0xFFC5DCF5);
  static const _softBlue = Color(0xFFA8C8EC);
  static const _warmWhite = Color(0xFFFFFCF9);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = circleSize / 2;

    final colors = listening
        ? const [
            DesignTokens.listeningCore,
            DesignTokens.listeningWarm,
            DesignTokens.listeningMist,
            DesignTokens.listeningSky,
            DesignTokens.listeningRim,
            DesignTokens.listeningEdge,
          ]
        : const [
            _warmWhite,
            Color(0xFFFFFEFC),
            Color(0xFFF5F9FD),
            _mist,
            _sky,
            _softBlue,
          ];

    final orb = Paint()
      ..shader = RadialGradient(
        colors: colors,
        stops: const [0.0, 0.45, 0.68, 0.82, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, orb);
  }

  @override
  bool shouldRepaint(covariant _PresencePainter oldDelegate) {
    return oldDelegate.circleSize != circleSize ||
        oldDelegate.listening != listening;
  }
}
