import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/theme/design_tokens.dart';

/// Bottom sheet for choosing Sa from the 12 pitches.
class ShrutiSelectionSheet extends StatelessWidget {
  const ShrutiSelectionSheet({
    super.key,
    required this.selectedPitch,
    required this.onPitchSelected,
  });

  final Pitch selectedPitch;
  final ValueChanged<Pitch> onPitchSelected;

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
          children: [
            const SizedBox(height: DesignTokens.spaceXs),
            const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x3326211E),
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              child: SizedBox(width: 40, height: 4),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            const _SheetHeader(),
            const SizedBox(height: DesignTokens.spaceLg),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.05,
              children: [
                for (final pitch in Pitch.values)
                  _ShrutiTile(
                    pitch: pitch,
                    isSelected: pitch == selectedPitch,
                    onSelected: onPitchSelected,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Select Shruti',
            style: GoogleFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: DesignTokens.onSurface,
            ),
          ),
        ),
        IconButton(
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
    );
  }
}

class _ShrutiTile extends StatelessWidget {
  const _ShrutiTile({
    required this.pitch,
    required this.isSelected,
    required this.onSelected,
  });

  final Pitch pitch;
  final bool isSelected;
  final ValueChanged<Pitch> onSelected;

  @override
  Widget build(BuildContext context) {
    final noteColor = isSelected
        ? DesignTokens.onPrimary
        : DesignTokens.onSurface;

    return Material(
      color: isSelected ? DesignTokens.accent : DesignTokens.surface,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onSelected(pitch);
        },
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            border: Border.all(
              color: isSelected
                  ? DesignTokens.accent.withValues(alpha: 0.4)
                  : DesignTokens.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              pitch.label,
              style: GoogleFonts.fraunces(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.1,
                color: noteColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
