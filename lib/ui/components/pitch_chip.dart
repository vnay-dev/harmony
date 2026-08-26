import 'package:flutter/material.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/theme/design_tokens.dart';

/// A single selectable Sa pitch option.
class PitchChip extends StatelessWidget {
  const PitchChip({
    super.key,
    required this.pitch,
    required this.isSelected,
    required this.onSelected,
  });

  final Pitch pitch;
  final bool isSelected;
  final ValueChanged<Pitch> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected ? colorScheme.primary : colorScheme.surface,
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: InkWell(
        onTap: () => onSelected(pitch),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: Center(
          child: Text(
            pitch.label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
