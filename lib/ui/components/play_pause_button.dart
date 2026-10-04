import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/ui/play_button_haptics.dart';

/// Soft circular play/pause control for the drone.
///
/// Behaves like a physical latching push button: pressed while playing,
/// raised while paused. Layer order matches the Figma play button.
///
/// Only the visible circular button face accepts taps; the surrounding
/// ripple/stage area is non-interactive.
class PlayPauseButton extends StatefulWidget {
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool isBusy;
  final VoidCallback? onPressed;

  static const Duration _pressDuration = Duration(milliseconds: 180);
  static const Curve _pressCurve = Curves.easeOutCubic;

  /// Diameter of the tappable circular face (matches the raised button).
  static const double hitTargetDiameter = DesignTokens.playButtonSize;

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  static const Duration _rippleDuration = Duration(milliseconds: 5200);

  late final AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: _rippleDuration,
    );
    _syncRipple(playing: widget.isPlaying);
  }

  @override
  void didUpdateWidget(covariant PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncRipple(playing: widget.isPlaying);
    }
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  void _syncRipple({required bool playing}) {
    if (playing) {
      if (!_rippleController.isAnimating) {
        _rippleController.repeat();
      }
    } else {
      _rippleController
        ..stop()
        ..value = 0;
    }
  }

  void _handleTap() {
    if (widget.isBusy || widget.onPressed == null) {
      return;
    }

    if (widget.isPlaying) {
      PlayButtonHaptics.release();
      _syncRipple(playing: false);
    } else {
      PlayButtonHaptics.pressIn();
      _syncRipple(playing: true);
    }
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isPlaying ? 'Pause' : 'Play';
    final isPressed = widget.isPlaying;

    // Extra room so expanding rings aren't clipped by the frame.
    const rippleRoom = 96.0;
    final stageSize = DesignTokens.playButtonFrameSize + rippleRoom;

    return Center(
      child: Semantics(
        button: true,
        enabled: !widget.isBusy,
        label: label,
        child: ExcludeSemantics(
          child: SizedBox(
            width: stageSize,
            height: stageSize,
            child: _CircularHitTarget(
              diameter: PlayPauseButton.hitTargetDiameter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.isBusy ? null : _handleTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _rippleController,
                      builder: (context, child) {
                        if (!widget.isPlaying &&
                            _rippleController.value == 0) {
                          return const SizedBox.shrink();
                        }
                        return CustomPaint(
                          size: Size.square(stageSize),
                          painter: _PlayButtonRipplePainter(
                            progress: _rippleController.value,
                            color: DesignTokens.softShadow,
                          ),
                        );
                      },
                    ),
                    const _PlayButtonParentCircle(),
                    AnimatedScale(
                      scale: isPressed ? 0.94 : 1.0,
                      duration: PlayPauseButton._pressDuration,
                      curve: PlayPauseButton._pressCurve,
                      child: AnimatedSlide(
                        offset: isPressed
                            ? const Offset(0, 0.018)
                            : Offset.zero,
                        duration: PlayPauseButton._pressDuration,
                        curve: PlayPauseButton._pressCurve,
                        child: _PlayButtonSurface(
                          isPressed: isPressed,
                          isBusy: widget.isBusy,
                          isPlaying: widget.isPlaying,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accepts hit tests only inside a circle; does not clip painting (shadows).
class _CircularHitTarget extends SingleChildRenderObjectWidget {
  const _CircularHitTarget({
    required this.diameter,
    required super.child,
  });

  final double diameter;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCircularHitTarget(diameter: diameter);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCircularHitTarget renderObject,
  ) {
    renderObject.diameter = diameter;
  }
}

class _RenderCircularHitTarget extends RenderProxyBox {
  _RenderCircularHitTarget({required double diameter}) : _diameter = diameter;

  double _diameter;

  double get diameter => _diameter;

  set diameter(double value) {
    if (_diameter == value) {
      return;
    }
    _diameter = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final center = Offset(size.width / 2, size.height / 2);
    if ((position - center).distance > _diameter / 2) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

/// Soft rings that expand from the frame circle and fade outward in a loop.
///
/// Each cycle sends a burst of one ripple, then a burst of two, then repeats.
class _PlayButtonRipplePainter extends CustomPainter {
  const _PlayButtonRipplePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const double _maxExpansion = 64;
  static const double _strokeWidth = 1.5;

  /// How long each ripple lives, as a fraction of one animation cycle.
  static const double _rippleLife = 0.42;

  /// Launch times within the cycle: one-ripple burst, then two-ripple burst.
  /// Packed toward a short handoff so the next cycle starts sooner.
  static const List<double> _launchTimes = <double>[
    0.00, // one
    0.38, 0.50, // two
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = DesignTokens.playButtonHaloSize / 2;

    for (final launch in _launchTimes) {
      var age = progress - launch;
      if (age < 0) {
        age += 1.0;
      }
      if (age >= _rippleLife) {
        continue;
      }
      _drawRing(canvas, center, baseRadius, age / _rippleLife);
    }
  }

  void _drawRing(Canvas canvas, Offset center, double baseRadius, double t) {
    // Expansion eases out; opacity lingers then dissolves more gently.
    final expand = Curves.easeOutQuart.transform(t);
    final fade = Curves.easeInCubic.transform(1.0 - t);
    final radius = baseRadius + expand * _maxExpansion;
    final opacity = fade * 0.30;
    if (opacity <= 0.01) {
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth * (0.45 + fade * 0.55)
      ..color = color.withValues(alpha: opacity);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _PlayButtonRipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _PlayButtonParentCircle extends StatelessWidget {
  const _PlayButtonParentCircle();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            DesignTokens.playButtonFace,
            DesignTokens.playButtonHighlight,
          ],
        ),
      ),
      child: SizedBox(
        width: DesignTokens.playButtonHaloSize,
        height: DesignTokens.playButtonHaloSize,
      ),
    );
  }
}

class _PlayButtonSurface extends StatelessWidget {
  const _PlayButtonSurface({
    required this.isPressed,
    required this.isBusy,
    required this.isPlaying,
  });

  final bool isPressed;
  final bool isBusy;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final shadows = isPressed
        ? <BoxShadow>[
            BoxShadow(
              color: DesignTokens.softShadow.withValues(alpha: 0.35),
              offset: const Offset(0, 1),
              blurRadius: 6,
              spreadRadius: -1,
            ),
            BoxShadow(
              color: DesignTokens.softShadow.withValues(alpha: 0.45),
              offset: const Offset(0, 2),
              blurRadius: 5,
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: DesignTokens.softShadow.withValues(alpha: 0.5),
              offset: const Offset(0, -1),
              blurRadius: 19,
            ),
            const BoxShadow(
              color: DesignTokens.softShadow,
              offset: Offset(0, 6),
              blurRadius: 14,
            ),
          ];

    return AnimatedContainer(
      duration: PlayPauseButton._pressDuration,
      curve: PlayPauseButton._pressCurve,
      width: DesignTokens.playButtonSize,
      height: DesignTokens.playButtonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DesignTokens.playButtonFace,
        boxShadow: shadows,
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: DesignTokens.playButtonReflectionHeight,
              child: AnimatedOpacity(
                opacity: isPressed ? 0.55 : 1.0,
                duration: PlayPauseButton._pressDuration,
                curve: PlayPauseButton._pressCurve,
                child: const _PlayButtonReflection(),
              ),
            ),
            if (isBusy)
              const SizedBox(
                width: DesignTokens.spaceXl,
                height: DesignTokens.spaceXl,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: DesignTokens.playIcon,
                ),
              )
            else
              _PlaybackIcon(isPlaying: isPlaying),
          ],
        ),
      ),
    );
  }
}

/// Play/pause icon with a hard color split at the reflection edge.
///
/// Below the reflection: `#225EBF`. Under the reflection: `#7A9DD5`.
class _PlaybackIcon extends StatelessWidget {
  const _PlaybackIcon({required this.isPlaying});

  final bool isPlaying;

  static const double _iconSize = 80;

  @override
  Widget build(BuildContext context) {
    final iconTop = (DesignTokens.playButtonSize - _iconSize) / 2;
    final split =
        ((DesignTokens.playButtonReflectionHeight - iconTop) / _iconSize).clamp(
          0.0,
          1.0,
        );

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            DesignTokens.playIconUnderReflection,
            DesignTokens.playIconUnderReflection,
            DesignTokens.playIcon,
            DesignTokens.playIcon,
          ],
          stops: [0.0, split, split, 1.0],
        ).createShader(bounds);
      },
      child: Icon(
        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: _iconSize,
        color: Colors.white,
      ),
    );
  }
}

/// Top-half ellipse reflection: `#F1F4FA` 88% → `#DFE4ED` 45%, layer 92%.
class _PlayButtonReflection extends StatelessWidget {
  const _PlayButtonReflection();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.92,
      child: Align(
        alignment: Alignment.topCenter,
        child: ClipOval(
          child: SizedBox(
            width: DesignTokens.playButtonSize - 1,
            height: DesignTokens.playButtonReflectionHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    DesignTokens.playButtonReflectionTop.withValues(
                      alpha: 0.88,
                    ),
                    DesignTokens.playButtonReflectionBottom.withValues(
                      alpha: 0.45,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
