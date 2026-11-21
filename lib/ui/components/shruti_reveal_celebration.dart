import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:harmony/theme/design_tokens.dart';

/// One-shot party-popper burst around a successfully discovered Shruti label.
///
/// Sequence: result settles → tiny anticipation → pop → confetti → gentle fall.
/// Plays once per mount; never loops. Particles are non-interactive so the
/// Shruti remains readable and tappable.
class ShrutiRevealCelebration extends StatefulWidget {
  const ShrutiRevealCelebration({
    super.key,
    required this.child,
    this.playHaptic = true,
  });

  final Widget child;

  /// Soft haptic at the pop. Disabled in widget tests that forbid platform
  /// channels when desired.
  final bool playHaptic;

  /// Total celebration length, including settle.
  static const Duration duration = Duration(milliseconds: 1350);

  @override
  State<ShrutiRevealCelebration> createState() =>
      _ShrutiRevealCelebrationState();
}

class _ShrutiRevealCelebrationState extends State<ShrutiRevealCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final List<_ConfettiParticle> _particles;
  bool _hapticFired = false;

  @override
  void initState() {
    super.initState();
    _particles = _ConfettiParticle.burst(seed: 42);
    _controller = AnimationController(
      vsync: this,
      duration: ShrutiRevealCelebration.duration,
    )..addListener(_onTick);

    // Result appears first; celebration starts just after it settles.
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 10),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.96,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 8,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.96,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
    ]).animate(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _controller.forward(from: 0);
    });
  }

  void _onTick() {
    // Fire haptic once at the pop (scale overshoot begins ~18% through).
    if (!_hapticFired &&
        widget.playHaptic &&
        _controller.value >= 0.18 &&
        _controller.value < 0.35) {
      _hapticFired = true;
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Burst behind the label so the Shruti stays the hero.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ConfettiPainter(
                      progress: _controller.value,
                      particles: _particles,
                    ),
                  ),
                ),
              ),
              Transform.scale(scale: _scale.value, child: child),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

enum _ParticleKind { ribbon, dot, sparkle, heart }

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.color,
    required this.kind,
    required this.delay,
    required this.drift,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
  final _ParticleKind kind;
  final double delay;
  final double drift;

  static List<_ConfettiParticle> burst({required int seed}) {
    final rng = math.Random(seed);
    final colors = <Color>[
      DesignTokens.accent,
      DesignTokens.playIconUnderReflection,
      DesignTokens.outline,
      const Color(0xFFA8C8EC),
      const Color(0xFFC5DCF5),
      DesignTokens.onSurface.withValues(alpha: 0.55),
    ];

    final particles = <_ConfettiParticle>[];

    // Primary pop — denser, faster, from the result center.
    for (var i = 0; i < 22; i++) {
      particles.add(
        _ConfettiParticle(
          angle: rng.nextDouble() * math.pi * 2,
          speed: 42 + rng.nextDouble() * 58,
          size: 3.5 + rng.nextDouble() * 5.5,
          spin: (rng.nextDouble() - 0.5) * 8,
          color: colors[rng.nextInt(colors.length)],
          kind: i % 5 == 0
              ? _ParticleKind.heart
              : i.isEven
              ? _ParticleKind.ribbon
              : _ParticleKind.dot,
          delay: 0.16 + rng.nextDouble() * 0.06,
          drift: (rng.nextDouble() - 0.5) * 18,
        ),
      );
    }

    // Secondary sparkle — softer, slightly delayed.
    for (var i = 0; i < 10; i++) {
      particles.add(
        _ConfettiParticle(
          angle: rng.nextDouble() * math.pi * 2,
          speed: 28 + rng.nextDouble() * 36,
          size: 2.2 + rng.nextDouble() * 3.2,
          spin: (rng.nextDouble() - 0.5) * 6,
          color: colors[rng.nextInt(3)],
          kind: _ParticleKind.sparkle,
          delay: 0.34 + rng.nextDouble() * 0.08,
          drift: (rng.nextDouble() - 0.5) * 12,
        ),
      );
    }

    return particles;
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress, required this.particles});

  final double progress;
  final List<_ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.12 || progress >= 1) {
      return;
    }

    final origin = Offset(size.width / 2, size.height / 2);
    for (final particle in particles) {
      final local = ((progress - particle.delay) / (1.0 - particle.delay))
          .clamp(0.0, 1.0);
      if (local <= 0) {
        continue;
      }

      final burst = Curves.easeOutCubic.transform(math.min(local / 0.35, 1.0));
      final fall = Curves.easeIn.transform(local);
      final dx =
          math.cos(particle.angle) * particle.speed * burst +
          particle.drift * fall;
      final dy =
          math.sin(particle.angle) * particle.speed * burst * 0.72 +
          54 * fall * fall;
      final opacity = (1.0 - Curves.easeInCubic.transform(local)).clamp(
        0.0,
        1.0,
      );
      if (opacity < 0.02) {
        continue;
      }

      final center = origin + Offset(dx, dy);
      final rotation = particle.spin * local * math.pi;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      _paintParticle(canvas, particle, opacity);
      canvas.restore();
    }
  }

  void _paintParticle(
    Canvas canvas,
    _ConfettiParticle particle,
    double opacity,
  ) {
    final paint = Paint()
      ..color = particle.color.withValues(alpha: opacity * 0.92)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (particle.kind) {
      case _ParticleKind.ribbon:
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size * 0.55,
            height: particle.size * 1.7,
          ),
          const Radius.circular(1.2),
        );
        canvas.drawRRect(rect, paint);
      case _ParticleKind.dot:
        canvas.drawCircle(Offset.zero, particle.size * 0.45, paint);
      case _ParticleKind.sparkle:
        _drawSparkle(canvas, particle.size, paint);
      case _ParticleKind.heart:
        _drawHeartEmoji(canvas, particle.size * 1.35, opacity);
    }
  }

  void _drawSparkle(Canvas canvas, double size, Paint paint) {
    final path = Path()
      ..moveTo(0, -size)
      ..lineTo(size * 0.28, -size * 0.28)
      ..lineTo(size, 0)
      ..lineTo(size * 0.28, size * 0.28)
      ..lineTo(0, size)
      ..lineTo(-size * 0.28, size * 0.28)
      ..lineTo(-size, 0)
      ..lineTo(-size * 0.28, -size * 0.28)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawHeartEmoji(Canvas canvas, double size, double opacity) {
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
          ..pushStyle(
            ui.TextStyle(
              fontSize: size,
              color: DesignTokens.accent.withValues(alpha: opacity * 0.95),
            ),
          )
          ..addText('💙');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: size * 2));
    canvas.drawParagraph(
      paragraph,
      Offset(-paragraph.maxIntrinsicWidth / 2, -paragraph.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
