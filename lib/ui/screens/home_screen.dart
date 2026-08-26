import 'package:flutter/material.dart';

import 'package:harmony/app/app_config.dart';
import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/audio/just_audio_service.dart';
import 'package:harmony/state/drone_controller.dart';
import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/ui/components/pitch_selector.dart';
import 'package:harmony/ui/components/play_pause_button.dart';

/// Main Shruti drone screen: Sa selection and play/pause.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, AudioService? audioService})
    : _audioService = audioService;

  final AudioService? _audioService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DroneController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DroneController(
      audioService: widget._audioService ?? JustAudioService(),
    );
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final errorMessage = _controller.errorMessage;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppConfig.appName, style: textTheme.titleLarge),
              const SizedBox(height: DesignTokens.spaceXl),
              Text(
                'Sa',
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceSm),
              Text(
                _controller.selectedPitch.label,
                style: textTheme.displaySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceXl),
              PitchSelector(
                selectedPitch: _controller.selectedPitch,
                onPitchSelected: _controller.selectPitch,
              ),
              const SizedBox(height: DesignTokens.spaceXl),
              if (errorMessage != null) ...[
                Text(
                  errorMessage,
                  style: textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DesignTokens.spaceMd),
              ],
              PlayPauseButton(
                isPlaying: _controller.isPlaying,
                isBusy: _controller.isBusy,
                onPressed: _controller.togglePlayback,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
