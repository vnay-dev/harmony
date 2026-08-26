import 'package:flutter/material.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/ui/components/pitch_chip.dart';

/// Grid of the 12 Sa pitch options.
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
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: DesignTokens.spaceSm,
      crossAxisSpacing: DesignTokens.spaceSm,
      childAspectRatio: 1.8,
      children: [
        for (final pitch in Pitch.values)
          PitchChip(
            pitch: pitch,
            isSelected: pitch == selectedPitch,
            onSelected: onPitchSelected,
          ),
      ],
    );
  }
}
