import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:harmony/theme/design_tokens.dart';

/// Gentle explanation of Shruti for first-time users.
class ShrutiInfoSheet extends StatelessWidget {
  const ShrutiInfoSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: DesignTokens.background,
      barrierColor: const Color(0x662A3A51),
      showDragHandle: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const ShrutiInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spaceLg,
          DesignTokens.spaceSm,
          DesignTokens.spaceLg,
          DesignTokens.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: DesignTokens.spaceXs),
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x3326211E),
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: SizedBox(width: 40, height: 4),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'What is Shruti?',
                    style: GoogleFonts.fraunces(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: DesignTokens.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('shruti-info-close'),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: DesignTokens.onSurface.withValues(alpha: 0.7),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    fixedSize: const Size(32, 32),
                    minimumSize: const Size(32, 32),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceMd),
            const Center(child: _ComfortPitchCue()),
            const SizedBox(height: DesignTokens.spaceMd),
            Text(
              'Your Shruti is the pitch that feels most comfortable for your '
              'voice when you sing.\n\n'
              "Think of it as your voice's natural starting point. Once you "
              'find it, you can use it as a reference to sing more comfortably '
              'and stay in tune.',
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.45,
                color: DesignTokens.onSurface.withValues(alpha: 0.88),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceMd),
            Text(
              'In Western music, you may hear this idea described as your key '
              'or tonic.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.4,
                color: DesignTokens.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny cue: a soft path settling toward a comfortable center.
class _ComfortPitchCue extends StatelessWidget {
  const _ComfortPitchCue();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 36,
      child: CustomPaint(painter: _ComfortPitchCuePainter()),
    );
  }
}

class _ComfortPitchCuePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final trackPaint = Paint()
      ..color = DesignTokens.outline.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * 0.08, center.dy),
      Offset(size.width * 0.92, center.dy),
      trackPaint,
    );

    final softPath = Path()
      ..moveTo(size.width * 0.18, center.dy + 8)
      ..quadraticBezierTo(
        size.width * 0.38,
        center.dy - 10,
        center.dx,
        center.dy,
      );
    final pathPaint = Paint()
      ..color = DesignTokens.accent.withValues(alpha: 0.35)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(softPath, pathPaint);

    final glow = Paint()
      ..color = DesignTokens.accent.withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, 9, glow);

    final dot = Paint()..color = DesignTokens.accent.withValues(alpha: 0.85);
    canvas.drawCircle(center, 4.2, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
