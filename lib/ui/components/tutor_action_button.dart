import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';

/// Tutor CTA that fades in calmly when it appears.
///
/// [primary] matches the Stage 1 blue filled pill. [secondary] is a calm
/// outlined pill for No / Try Again style answers.
class TutorActionButton extends StatefulWidget {
  const TutorActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
  });

  final String label;
  final VoidCallback? onPressed;

  /// When false, renders as an outlined secondary action.
  final bool primary;

  @override
  State<TutorActionButton> createState() => _TutorActionButtonState();
}

class _TutorActionButtonState extends State<TutorActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _opacity = CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic);
    _fade.forward();
  }

  @override
  void didUpdateWidget(covariant TutorActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label ||
        oldWidget.primary != widget.primary) {
      _fade
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
    );

    final button = widget.primary
        ? FilledButton(
            key: ValueKey<String>('tutor-cta-${widget.label}'),
            onPressed: widget.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: DesignTokens.accent,
              foregroundColor: DesignTokens.onPrimary,
              shape: shape,
              textStyle: textStyle,
            ),
            child: Text(widget.label),
          )
        : OutlinedButton(
            key: ValueKey<String>('tutor-cta-secondary-${widget.label}'),
            onPressed: widget.onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: DesignTokens.onSurface,
              side: const BorderSide(color: DesignTokens.onSurface),
              shape: shape,
              textStyle: textStyle,
            ),
            child: Text(widget.label),
          );

    return FadeTransition(
      opacity: _opacity,
      child: SizedBox(
        height: DesignTokens.controlHeight,
        width: double.infinity,
        child: button,
      ),
    );
  }
}
