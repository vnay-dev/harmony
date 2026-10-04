import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/ui/components/shruti_selection_sheet.dart';

/// Selected Sa, with controls to step to the next or previous pitch.
class PitchSelector extends StatelessWidget {
  const PitchSelector({
    super.key,
    required this.selectedPitch,
    required this.onPitchSelected,
  });

  final Pitch selectedPitch;
  final ValueChanged<Pitch> onPitchSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PitchLabel(
          pitch: selectedPitch,
          onTap: () => _openSelectionSheet(context),
        ),
        const SizedBox(width: DesignTokens.spaceLg),
        _PitchStepButtons(
          onHigher: () => onPitchSelected(selectedPitch.next),
          onLower: () => onPitchSelected(selectedPitch.previous),
        ),
      ],
    );
  }

  Future<void> _openSelectionSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: DesignTokens.background,
      barrierColor: const Color(0x662A3A51),
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return ShrutiSelectionSheet(
          selectedPitch: selectedPitch,
          onPitchSelected: onPitchSelected,
        );
      },
    );
  }
}

class _PitchLabel extends StatelessWidget {
  const _PitchLabel({required this.pitch, required this.onTap});

  final Pitch pitch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sa ${pitch.label}',
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Select Shruti',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: DesignTokens.pitchLabelWidth,
              height: DesignTokens.pitchLabelHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(color: DesignTokens.outline, width: 1.15),
                ),
                child: Center(
                  child: Text(
                    pitch.label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.fraunces(
                      fontSize: DesignTokens.fontSizePitch,
                      fontWeight: FontWeight.w400,
                      height: 1,
                      color: DesignTokens.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PitchStepButtons extends StatelessWidget {
  const _PitchStepButtons({required this.onHigher, required this.onLower});

  final VoidCallback onHigher;
  final VoidCallback onLower;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DesignTokens.pitchLabelHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StepButton(
            tooltip: 'Higher Sa',
            icon: Icons.keyboard_arrow_up_rounded,
            onPressed: onHigher,
          ),
          _StepButton(
            tooltip: 'Lower Sa',
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: onLower,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(DesignTokens.stepButtonRadius),
          border: Border.all(color: DesignTokens.outline, width: 1.15),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: DesignTokens.stepButtonSize,
            height: DesignTokens.stepButtonSize,
            child: Icon(
              icon,
              color: DesignTokens.onSurface,
              size: DesignTokens.stepButtonIconSize,
            ),
          ),
        ),
      ),
    );
  }
}
