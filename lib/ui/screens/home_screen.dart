import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:harmony/audio/audio_service.dart';

import 'package:harmony/audio/just_audio_service.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/state/drone_controller.dart';
import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/ui/components/pitch_selector.dart';
import 'package:harmony/ui/components/play_pause_button.dart';
import 'package:harmony/ui/components/secondary_pill_button.dart';
import 'package:harmony/ui/components/shruti_info_sheet.dart';
import 'package:harmony/ui/screens/assist_mode_screen.dart';

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

  Future<void> _openAssistMode() async {
    // Home Shruti belongs to this practice flow — stop it before Tutor Mode.
    await _controller.pausePlayback();
    if (!mounted) {
      return;
    }

    final pitch = await Navigator.of(context).push<Pitch>(
      MaterialPageRoute<Pitch>(builder: (_) => const AssistModeScreen()),
    );
    if (!mounted || pitch == null) {
      return;
    }
    await _controller.playPitch(pitch);
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _controller.errorMessage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              DesignTokens.background,
              DesignTokens.backgroundMid,
              DesignTokens.backgroundBottom,
            ],
            stops: [0.0, 0.32, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              28,
              DesignTokens.spaceMd,
              28,
              DesignTokens.spaceLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 4),
                PitchSelector(
                  selectedPitch: _controller.selectedPitch,
                  onPitchSelected: _controller.selectPitch,
                ),
                const Spacer(flex: 1),
                if (errorMessage != null) ...[
                  Text(
                    errorMessage,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                const Spacer(flex: 3),
                Center(
                  child: Text.rich(
                    TextSpan(
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DesignTokens.onSurface,
                        height: 1.3,
                      ),
                      children: [
                        const TextSpan(
                          text: 'Not sure which Shruti is right for you?',
                        ),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Semantics(
                            button: true,
                            label: 'What is Shruti?',
                            child: IconButton(
                              key: const ValueKey<String>('shruti-info-button'),
                              tooltip: 'What is Shruti?',
                              onPressed: () => ShrutiInfoSheet.show(context),
                              icon: Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: DesignTokens.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                              style: IconButton.styleFrom(
                                foregroundColor: DesignTokens.onSurface
                                    .withValues(alpha: 0.55),
                                minimumSize: const Size(32, 32),
                                maximumSize: const Size(32, 32),
                                fixedSize: const Size(32, 32),
                                padding: const EdgeInsets.only(left: 2),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                Center(
                  child: SecondaryPillButton(
                    label: 'Find my Shruti',
                    onPressed: _openAssistMode,
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
