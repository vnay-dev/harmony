import 'package:flutter/material.dart';

import 'package:harmony/theme/design_tokens.dart';

/// Primary play/pause control for the drone.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = isPlaying ? 'Pause' : 'Play';
    final icon = isPlaying ? Icons.pause : Icons.play_arrow;

    return SizedBox(
      width: double.infinity,
      height: DesignTokens.controlHeight,
      child: FilledButton.icon(
        onPressed: isBusy ? null : onPressed,
        icon: isBusy
            ? SizedBox(
                width: DesignTokens.spaceLg,
                height: DesignTokens.spaceLg,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : Icon(icon, size: DesignTokens.spaceXl),
        label: Text(label),
      ),
    );
  }
}
