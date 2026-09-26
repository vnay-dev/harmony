import 'package:flutter/material.dart';

import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/audio/just_audio_service.dart';
import 'package:harmony/audio/reference_sound_generator.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/mic_pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/reference_pitch_adjuster.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/theme/design_tokens.dart';
import 'package:harmony/tutor/flutter_tutor_voice.dart';
import 'package:harmony/tutor/speech_to_text_recognizer.dart';
import 'package:harmony/tutor/tutor_session.dart';
import 'package:harmony/tutor/tutor_speech_recognizer.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice.dart';
import 'package:harmony/ui/components/voice_activity_indicator.dart';

/// Voice-first singing tutor that finds a comfortable Shruti.
class AssistModeScreen extends StatefulWidget {
  const AssistModeScreen({
    super.key,
    PitchDetectionService? detectionService,
    AudioService? audioService,
    StablePitchCandidateFinder? candidateFinder,
    ReferencePitchAdjuster? pitchAdjuster,
    TargetPitchMatcher? targetMatcher,
    ReferenceSoundGenerator? referenceSoundGenerator,
    AssistModeController? controller,
    TutorSession? tutorSession,
    TutorVoice? tutorVoice,
    TutorSpeechRecognizer? speechRecognizer,
    this.timing,
    this.tutorTiming,
    this.initialReferencePitch,
    this.wait,
    this.prepareAudioSession,
    this.autoBegin = true,
  }) : _detectionService = detectionService,
       _audioService = audioService,
       _candidateFinder = candidateFinder,
       _pitchAdjuster = pitchAdjuster,
       _targetMatcher = targetMatcher,
       _referenceSoundGenerator = referenceSoundGenerator,
       _controller = controller,
       _tutorSession = tutorSession,
       _tutorVoice = tutorVoice,
       _speechRecognizer = speechRecognizer;

  final PitchDetectionService? _detectionService;
  final AudioService? _audioService;
  final StablePitchCandidateFinder? _candidateFinder;
  final ReferencePitchAdjuster? _pitchAdjuster;
  final TargetPitchMatcher? _targetMatcher;
  final ReferenceSoundGenerator? _referenceSoundGenerator;
  final AssistModeController? _controller;
  final TutorSession? _tutorSession;
  final TutorVoice? _tutorVoice;
  final TutorSpeechRecognizer? _speechRecognizer;

  /// Optional timing overrides (tests / tuning).
  final AssistTimingConfig? timing;

  /// Optional tutor speech pacing overrides.
  final TutorTimingConfig? tutorTiming;

  /// Optional starting Sa (defaults to the app default pitch).
  final Pitch? initialReferencePitch;

  /// Optional wait override so tests can skip window delays.
  final Future<void> Function(Duration duration)? wait;

  /// Optional audio-session setup override (tests inject a no-op).
  final Future<void> Function()? prepareAudioSession;

  /// When true (default), welcome speech runs and the session auto-starts.
  final bool autoBegin;

  @override
  State<AssistModeScreen> createState() => _AssistModeScreenState();
}

class _AssistModeScreenState extends State<AssistModeScreen> {
  late final AssistModeController _controller;
  late final TutorSession _tutor;
  late final bool _ownsController;
  late final bool _ownsTutor;

  @override
  void initState() {
    super.initState();
    final injectedController = widget._controller;
    if (injectedController != null) {
      _controller = injectedController;
      _ownsController = false;
    } else {
      _controller = AssistModeController(
        detectionService:
            widget._detectionService ?? MicPitchDetectionService(),
        audioService:
            widget._audioService ??
            JustAudioService(handleInterruptions: false),
        candidateFinder: widget._candidateFinder,
        pitchAdjuster: widget._pitchAdjuster,
        targetMatcher: widget._targetMatcher,
        referenceSoundGenerator: widget._referenceSoundGenerator,
        timing: widget.timing ?? const AssistTimingConfig(),
        initialReferencePitch:
            widget.initialReferencePitch ?? Pitch.defaultPitch,
        wait: widget.wait,
        prepareAudioSession: widget.prepareAudioSession,
      );
      _ownsController = true;
    }

    final injectedTutor = widget._tutorSession;
    if (injectedTutor != null) {
      _tutor = injectedTutor;
      _ownsTutor = false;
    } else {
      _tutor = TutorSession(
        engine: _controller,
        voice: widget._tutorVoice ?? FlutterTutorVoice(),
        speechRecognizer:
            widget._speechRecognizer ?? SpeechToTextTutorRecognizer(),
        timing: widget.tutorTiming ?? const TutorTimingConfig(),
        // Do not share the engine wait — speech pauses must never block on
        // Assist listen/reference windows.
      );
      _ownsTutor = true;
    }

    _tutor.addListener(_onTutorChanged);
    _controller.addListener(_onTutorChanged);

    if (widget.autoBegin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _tutor.begin();
        }
      });
    }
  }

  void _onTutorChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tutor.removeListener(_onTutorChanged);
    _controller.removeListener(_onTutorChanged);
    if (_ownsTutor) {
      _tutor.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Find your Shruti')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      key: const ValueKey<String>('assist-content-scroll'),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_tutor.confirmedShrutiLabel != null) ...[
                              Text(
                                _tutor.confirmedShrutiLabel!,
                                key: const ValueKey<String>(
                                  'assist-confirmed-shruti',
                                ),
                                style: textTheme.displaySmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: DesignTokens.spaceLg),
                            ],
                            if (_tutor.showCountdown) ...[
                              _CountdownDisplay(
                                value: _tutor.countdownValue ?? 0,
                                colorScheme: colorScheme,
                                textTheme: textTheme,
                              ),
                              const SizedBox(height: DesignTokens.spaceLg),
                            ] else ...[
                              Text(
                                _tutor.headline,
                                key: ValueKey<String>(
                                  'assist-headline-${_tutor.step.name}',
                                ),
                                style: textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                              if (_tutor.supportText != null) ...[
                                const SizedBox(height: DesignTokens.spaceMd),
                                Text(
                                  _tutor.supportText!,
                                  key: ValueKey<String>(
                                    'assist-support-${_tutor.step.name}',
                                  ),
                                  style: textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.72,
                                    ),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                            if (_controller.uiPhase ==
                                AssistUiPhase.listening) ...[
                              const SizedBox(height: DesignTokens.spaceXl),
                              VoiceActivityIndicator(
                                level: _controller.voiceActivity,
                              ),
                            ],
                            if (_tutor.showListenProgress) ...[
                              const SizedBox(height: DesignTokens.spaceLg),
                              _ListenProgress(
                                progress: _controller.listenProgress,
                                colorScheme: colorScheme,
                              ),
                            ],
                            if (_controller.uiPhase ==
                                    AssistUiPhase.playingReference ||
                                _controller.uiPhase ==
                                    AssistUiPhase.assistedSinging) ...[
                              const SizedBox(height: DesignTokens.spaceXl),
                              Icon(
                                Icons.graphic_eq,
                                size: 36,
                                color: colorScheme.primary,
                                key: const ValueKey<String>(
                                  'assist-playing-icon',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              ..._buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    final busy = _controller.isBusy || _tutor.isSpeaking;

    if (_tutor.showPlayMyShruti) {
      return [
        SizedBox(
          height: DesignTokens.controlHeight,
          child: FilledButton(
            key: const ValueKey<String>('assist-play-my-shruti'),
            onPressed: busy
                ? null
                : () {
                    final pitch = _controller.referencePitch;
                    Navigator.of(context).pop<Pitch>(pitch);
                  },
            child: const Text('Play My Shruti'),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        SizedBox(
          height: DesignTokens.controlHeight,
          child: OutlinedButton(
            key: const ValueKey<String>('assist-try-again'),
            onPressed: busy ? null : _tutor.tryAgain,
            child: const Text('Try Again'),
          ),
        ),
      ];
    }

    if (_tutor.showSessionStopped) {
      return [
        SizedBox(
          height: DesignTokens.controlHeight,
          child: FilledButton(
            key: const ValueKey<String>('assist-session-stopped-try-again'),
            onPressed: _tutor.tryAgain,
            child: const Text('Try Again'),
          ),
        ),
      ];
    }

    if (_tutor.showYesNoFallback) {
      return [
        SizedBox(
          height: DesignTokens.controlHeight,
          child: FilledButton(
            key: const ValueKey<String>('assist-lower-audible-yes'),
            onPressed: busy ? null : () => _tutor.answerLowerAudibility(true),
            child: const Text('Yes'),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        SizedBox(
          height: DesignTokens.controlHeight,
          child: OutlinedButton(
            key: const ValueKey<String>('assist-lower-too-low'),
            onPressed: busy ? null : () => _tutor.answerLowerAudibility(false),
            child: const Text('No'),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        _stopButton(),
      ];
    }

    if (_tutor.showComfortFallback) {
      return [
        SizedBox(
          height: DesignTokens.controlHeight,
          child: FilledButton(
            key: const ValueKey<String>('assist-upper-comfortable'),
            onPressed: busy ? null : () => _tutor.answerUpperComfort(true),
            child: const Text('Comfortable'),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        SizedBox(
          height: DesignTokens.controlHeight,
          child: OutlinedButton(
            key: const ValueKey<String>('assist-upper-strained'),
            onPressed: busy ? null : () => _tutor.answerUpperComfort(false),
            child: const Text('Not comfortable'),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        _stopButton(),
      ];
    }

    if (_tutor.showTryAgain) {
      return [
        SizedBox(
          height: DesignTokens.controlHeight,
          child: FilledButton(
            key: const ValueKey<String>('assist-unresolved-try-again'),
            onPressed: busy
                ? null
                : () {
                    if (_tutor.step == TutorStep.startingNoteFailure) {
                      _tutor.retryStartingNote();
                    } else {
                      _tutor.tryAgain();
                    }
                  },
            child: const Text('Try Again'),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        _stopButton(),
      ];
    }

    if (_tutor.showStop) {
      return [_stopButton()];
    }

    // Welcome — no CTA; voice auto-continues.
    return const [];
  }

  Widget _stopButton() {
    return SizedBox(
      height: DesignTokens.controlHeight,
      child: OutlinedButton(
        key: const ValueKey<String>('assist-stop'),
        onPressed: _tutor.stop,
        child: const Text('Stop'),
      ),
    );
  }
}

class _CountdownDisplay extends StatelessWidget {
  const _CountdownDisplay({
    required this.value,
    required this.colorScheme,
    required this.textTheme,
  });

  final int value;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final label = '$value';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (currentChild, previousChildren) {
        return currentChild ?? const SizedBox.shrink();
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Text(
        label,
        key: ValueKey<String>('tutor-countdown-$label'),
        style: textTheme.displaySmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ListenProgress extends StatelessWidget {
  const _ListenProgress({required this.progress, required this.colorScheme});

  final double progress;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
      child: LinearProgressIndicator(
        key: const ValueKey<String>('assist-listen-progress'),
        value: progress.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: colorScheme.primary.withValues(alpha: 0.16),
        color: colorScheme.primary,
      ),
    );
  }
}
