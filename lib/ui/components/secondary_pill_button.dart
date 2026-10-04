import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:harmony/theme/design_tokens.dart';

/// Outlined pill used for calm secondary actions (e.g. Home "Find my Shruti").
class SecondaryPillButton extends StatelessWidget {
  const SecondaryPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconLeading = false,
    this.borderColor,
    this.borderWidth = 1,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// When true, [icon] is placed before [label].
  final bool iconLeading;

  /// Override for the pill outline (e.g. calm loading pulse).
  final Color? borderColor;

  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.manrope(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: DesignTokens.onSurface,
    );

    final content = icon == null
        ? Text(label, style: labelStyle)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: iconLeading
                ? [
                    icon!,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        style: labelStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]
                : [
                    Flexible(
                      child: Text(
                        label,
                        style: labelStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    icon!,
                  ],
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
          border: Border.all(
            color: borderColor ?? DesignTokens.onSurface,
            width: borderWidth,
          ),
        ),
        child: content,
      ),
    );
  }
}
