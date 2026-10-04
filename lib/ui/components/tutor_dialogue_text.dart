import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/tutor/tutor_compliment.dart';
import 'package:harmony/tutor/tutor_dialogue_timing.dart';

/// Tutor dialogue that writes progressively in sync with spoken audio timing.
class TutorDialogueText extends StatefulWidget {
  const TutorDialogueText({
    super.key,
    required this.text,
    this.isSpeaking = false,
    this.isInstruction = false,
  });

  final String text;
  final bool isSpeaking;

  /// Secondary hint style (e.g. listening prompt) — not spoken dialogue.
  final bool isInstruction;

  @override
  State<TutorDialogueText> createState() => _TutorDialogueTextState();
}

class _TutorDialogueTextState extends State<TutorDialogueText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal;
  TutorLineTiming? _timing;

  /// Continuous character cursor: integer part = fully visible count.
  double _cursor = 0;

  TextStyle? _cachedStyle;
  String? _cachedText;
  double? _cachedMaxWidth;
  double? _cachedMaxHeight;
  bool? _cachedIsInstruction;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this);
    _reveal.addListener(_onTick);
    _startReveal(widget.text, animate: widget.isSpeaking);
  }

  @override
  void didUpdateWidget(covariant TutorDialogueText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _invalidateStyleCache();
      _startReveal(widget.text, animate: widget.isSpeaking);
      return;
    }
    if (oldWidget.isInstruction != widget.isInstruction) {
      _invalidateStyleCache();
      if (mounted) {
        setState(() {});
      }
    }
    if (oldWidget.isSpeaking != widget.isSpeaking) {
      if (widget.isSpeaking) {
        if (_cursor < widget.text.characters.length) {
          _startReveal(widget.text, animate: true);
        }
      } else {
        _finishReveal();
      }
    }
  }

  void _invalidateStyleCache() {
    _cachedStyle = null;
    _cachedText = null;
    _cachedMaxWidth = null;
    _cachedMaxHeight = null;
    _cachedIsInstruction = null;
  }

  void _startReveal(String text, {required bool animate}) {
    _reveal.stop();
    _timing = TutorDialogueTiming.forLine(text);
    final length = text.characters.length;

    if (!animate || text.isEmpty || _timing == null) {
      _cursor = length.toDouble();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _cursor = 0;
    if (mounted) {
      setState(() {});
    }
    _reveal
      ..duration = _timing!.duration
      ..forward(from: 0);
  }

  void _finishReveal() {
    _reveal.stop();
    final length = widget.text.characters.length.toDouble();
    if (_cursor != length && mounted) {
      setState(() => _cursor = length);
    } else {
      _cursor = length;
    }
  }

  void _onTick() {
    final timing = _timing;
    if (timing == null || !mounted) {
      return;
    }
    // Linear cursor tracks clip duration; per-character fade softens edges.
    final length = widget.text.characters.length;
    final next = length * _reveal.value;
    if ((next - _cursor).abs() > 0.01) {
      setState(() => _cursor = next);
    }
    if (_reveal.isCompleted) {
      _finishReveal();
    }
  }

  @override
  void dispose() {
    _reveal
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final maxHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 180.0;
          final style = _styleFor(
            context: context,
            text: widget.text,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          );

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: maxWidth,
              child: Text.rich(_buildSpan(style), textAlign: TextAlign.center),
            ),
          );
        },
      ),
    );
  }

  TextSpan _buildSpan(TextStyle? style) {
    final baseColor = style?.color ?? DesignTokens.onSurface;
    final chars = widget.text.characters.toList(growable: false);
    if (chars.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    // Inline in the same reveal — never rewrite the spoken sentence.
    // "Beautiful. You did it." → "Beautiful 💙! You did it."
    // "That's lovely." → "That's lovely 💙!"
    // "Wonderful. We found…" → "Wonderful 💙! We found…"
    final insertAt = TutorCompliment.celebrationInsertIndex(widget.text);
    final celebrationStyle = style?.copyWith(
      color: DesignTokens.accent,
      fontWeight: FontWeight.w600,
    );

    final spans = <InlineSpan>[];
    for (var i = 0; i < chars.length; i++) {
      if (i == insertAt) {
        // Reveal with the compliment word, then continue the rest.
        final celebrationAlpha = (_cursor - insertAt).clamp(0.0, 1.0);
        final eased = celebrationAlpha <= 0
            ? 0.0
            : celebrationAlpha >= 1
            ? 1.0
            : Curves.easeOut.transform(celebrationAlpha);
        if (eased > 0) {
          final textColor = baseColor.withValues(alpha: eased);
          spans.add(
            TextSpan(
              text: ' ',
              style: style?.copyWith(color: textColor),
            ),
          );
          spans.add(
            TextSpan(
              text: '💙',
              style: celebrationStyle?.copyWith(
                color: DesignTokens.accent.withValues(alpha: eased),
              ),
            ),
          );
          // Keep "!" on the dialogue color — only the heart is accent blue.
          spans.add(
            TextSpan(
              text: '!',
              style: style?.copyWith(color: textColor),
            ),
          );
        }
        if (chars[i] == '.') {
          continue;
        }
      }
      final distance = _cursor - i;
      final alpha = distance <= 0
          ? 0.0
          : distance >= 1
          ? 1.0
          : Curves.easeOut.transform(distance);
      spans.add(
        TextSpan(
          text: chars[i],
          style: style?.copyWith(color: baseColor.withValues(alpha: alpha)),
        ),
      );
    }
    return TextSpan(children: spans);
  }

  TextStyle? _styleFor({
    required BuildContext context,
    required String text,
    required double maxWidth,
    required double maxHeight,
  }) {
    if (_cachedStyle != null &&
        _cachedText == text &&
        _cachedMaxWidth == maxWidth &&
        _cachedMaxHeight == maxHeight &&
        _cachedIsInstruction == widget.isInstruction) {
      return _cachedStyle;
    }
    final style = _fitStyle(
      context: context,
      text: text,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    _cachedStyle = style;
    _cachedText = text;
    _cachedMaxWidth = maxWidth;
    _cachedMaxHeight = maxHeight;
    _cachedIsInstruction = widget.isInstruction;
    return style;
  }

  TextStyle? _fitStyle({
    required BuildContext context,
    required String text,
    required double maxWidth,
    required double maxHeight,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final color = widget.isInstruction
        ? DesignTokens.muted
        : DesignTokens.onSurface;
    final weight = widget.isInstruction ? FontWeight.w400 : FontWeight.w500;
    final candidates = <TextStyle?>[
      textTheme.headlineLarge,
      textTheme.headlineMedium,
      textTheme.headlineSmall,
      textTheme.titleLarge,
      textTheme.titleMedium,
    ];

    for (final candidate in candidates) {
      final style = candidate?.copyWith(
        fontWeight: weight,
        color: color,
        height: 1.25,
      );
      if (style == null) {
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
      if (painter.height <= maxHeight) {
        return style;
      }
    }

    return textTheme.titleMedium?.copyWith(
      fontWeight: weight,
      color: color,
      height: 1.25,
    );
  }
}
