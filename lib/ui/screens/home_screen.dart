import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:harmony/app/app_config.dart';
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
  const HomeScreen({
    super.key,
    AudioService? audioService,
    this.assistModeBuilder,
    this.enableFindMyShruti = AppConfig.enableFindMyShruti,
  }) : _audioService = audioService;

  final AudioService? _audioService;

  /// Optional Tutor Mode route body. Tests inject a screen that skips real
  /// Kitten model download; production uses [AssistModeScreen].
  final WidgetBuilder? assistModeBuilder;

  /// Whether Find My Shruti is offered on this Home screen.
  ///
  /// Defaults to [AppConfig.enableFindMyShruti]. Tests may override to verify
  /// both the gated launch UI and the preserved entry path.
  final bool enableFindMyShruti;

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
    if (!widget.enableFindMyShruti) {
      return;
    }

    // Home Shruti belongs to this practice flow — stop it before Tutor Mode.
    await _controller.pausePlayback();
    if (!mounted) {
      return;
    }

    final pitch = await Navigator.of(context).push<Pitch>(
      MaterialPageRoute<Pitch>(
        builder: widget.assistModeBuilder ?? (_) => const AssistModeScreen(),
      ),
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
                  child: Builder(
                    builder: (context) {
                      final infoTextStyle = GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DesignTokens.onSurface,
                        height: 1.3,
                      );
                      final infoColor = infoTextStyle.color!;
                      // Visible glyph stays compact; OverflowBox keeps a 44×44
                      // tap target without stretching the text line height.
                      const visibleIconSize = 18.0;
                      const tapTargetSize = 44.0;
                      return Text.rich(
                        TextSpan(
                          style: infoTextStyle,
                          children: [
                            const TextSpan(
                              text: 'What does Shruti mean in Indian music?',
                            ),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Semantics(
                                button: true,
                                label: 'What is Shruti?',
                                child: SizedBox(
                                  width: visibleIconSize + 4,
                                  height: visibleIconSize,
                                  child: OverflowBox(
                                    minWidth: tapTargetSize,
                                    maxWidth: tapTargetSize,
                                    minHeight: tapTargetSize,
                                    maxHeight: tapTargetSize,
                                    alignment: Alignment.center,
                                    child: IconButton(
                                      key: const ValueKey<String>(
                                        'shruti-info-button',
                                      ),
                                      tooltip: 'What is Shruti?',
                                      onPressed: () =>
                                          ShrutiInfoSheet.show(context),
                                      icon: Icon(
                                        Icons.info_outline_rounded,
                                        size: visibleIconSize,
                                        color: infoColor,
                                      ),
                                      style: IconButton.styleFrom(
                                        foregroundColor: infoColor,
                                        minimumSize: const Size(
                                          tapTargetSize,
                                          tapTargetSize,
                                        ),
                                        maximumSize: const Size(
                                          tapTargetSize,
                                          tapTargetSize,
                                        ),
                                        fixedSize: const Size(
                                          tapTargetSize,
                                          tapTargetSize,
                                        ),
                                        padding: EdgeInsets.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.standard,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ),
                if (widget.enableFindMyShruti) ...[
                  const SizedBox(height: DesignTokens.spaceMd),
                  Center(
                    child: SecondaryPillButton(
                      key: const ValueKey<String>('find-my-shruti-button'),
                      label: 'Find my Shruti',
                      onPressed: _openAssistMode,
                    ),
                  ),
                ],
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
