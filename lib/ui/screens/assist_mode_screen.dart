import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

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
import 'package:harmony/tutor/asset_tutor_voice.dart';
import 'package:harmony/tutor/speech_to_text_recognizer.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_session.dart';
import 'package:harmony/tutor/tutor_speech_recognizer.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice.dart';
import 'package:harmony/ui/components/pitch_direction_dial.dart';
import 'package:harmony/ui/components/shruti_reveal_celebration.dart';
import 'package:harmony/ui/components/tutor_action_button.dart';
import 'package:harmony/ui/components/tutor_dialogue_text.dart';
import 'package:harmony/ui/components/tutor_hear_sa_control.dart';
import 'package:harmony/ui/components/tutor_presence_circle.dart';

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

  /// When true (default), welcome speech runs and waits for "Let's begin".
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
        voice: widget._tutorVoice ?? AssetTutorVoice(),
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

  void _goHome() {
    // Detach before teardown so stop()/pop cannot rebuild a dying route.
    _tutor.removeListener(_onTutorChanged);
    _controller.removeListener(_onTutorChanged);

    if (_tutor.step != TutorStep.complete && _tutor.step != TutorStep.stopped) {
      // Start cancellation without awaiting listen/wait teardown.
      unawaited(_tutor.stop());
    }
    if (!mounted) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Tutor Mode',
          style: textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.62),
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          if (_tutor.showHome)
            IconButton(
              key: const ValueKey<String>('tutor-home'),
              tooltip: 'Home',
              onPressed: _goHome,
              icon: Icon(
                Icons.home_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildTutorSurface()),
              const SizedBox(height: DesignTokens.spaceMd),
              ..._buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  /// Circle slot above an independent transcript region.
  ///
  /// Shared by Stage 1, Stage 2, and terminal states so the calm circle +
  /// dialogue composition never flips to the old headline surface.
  Widget _buildTutorSurface() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  child: SizedBox(
                    height: TutorPresenceCircle.slotSize,
                    width: double.infinity,
                    child: Center(
                      child: TutorPresenceCircle(
                        state: _tutor.presenceState,
                        voiceLevel: _controller.voiceActivity,
                      ),
                    ),
                  ),
                ),
                // Supporting Stage 2 listen cue — keeps circle + dialogue hierarchy.
                if (_controller.uiPhase == AssistUiPhase.listening &&
                    _controller.isExploringRange) ...[
                  const SizedBox(height: DesignTokens.spaceMd),
                  PitchDirectionDial(
                    centsFromTarget: _controller.liveCentsFromTarget,
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                ] else
                  const SizedBox(height: DesignTokens.spaceLg),
                _TutorDialogueContent(tutor: _tutor),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActions() {
    // Terminal CTAs stay available even if completion speech is finishing.
    if (_tutor.showPlayMyShruti) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-play-my-shruti'),
          label: 'Play My Shruti',
          onPressed: _tutor.isSpeaking
              ? null
              : () {
                  final pitch = _controller.referencePitch;
                  Navigator.of(context).pop<Pitch>(pitch);
                },
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TutorActionButton(
          key: const ValueKey<String>('assist-try-again'),
          label: 'Try Again',
          primary: false,
          onPressed: _tutor.isSpeaking ? null : _tutor.tryAgain,
        ),
      ];
    }

    if (_tutor.showSessionStopped) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-session-stopped-try-again'),
          label: 'Try Again',
          onPressed: _tutor.tryAgain,
        ),
      ];
    }

    // No in-flow CTAs while Harmony is speaking — same as Stage 1.
    if (_tutor.isSpeaking) {
      return const [];
    }

    if (_tutor.showDifferentSoundChoice) {
      final canAnswer = _tutor.canAnswerDifferentSound;
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-different-sound-yes'),
          label: 'Yes',
          onPressed: canAnswer ? () => _tutor.answerDifferentSound(true) : null,
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TutorActionButton(
          key: const ValueKey<String>('assist-different-sound-no'),
          label: 'No',
          primary: false,
          onPressed: canAnswer
              ? () => _tutor.answerDifferentSound(false)
              : null,
        ),
      ];
    }

    if (_tutor.showYesNoFallback) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-lower-audible-yes'),
          label: TutorScripts.ctaHeardClearly,
          onPressed: () => _tutor.answerLowerAudibility(true),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TutorActionButton(
          key: const ValueKey<String>('assist-lower-too-low'),
          label: TutorScripts.ctaHardToHear,
          primary: false,
          onPressed: () => _tutor.answerLowerAudibility(false),
        ),
      ];
    }

    if (_tutor.showComfortFallback) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-upper-comfortable'),
          label: TutorScripts.ctaComfortable,
          onPressed: () => _tutor.answerUpperComfort(true),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TutorActionButton(
          key: const ValueKey<String>('assist-upper-strained'),
          label: TutorScripts.ctaNotComfortable,
          primary: false,
          onPressed: () => _tutor.answerUpperComfort(false),
        ),
      ];
    }

    if (_tutor.showTryAgain) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-unresolved-try-again'),
          label: 'Try Again',
          onPressed: _tutor.tryAgain,
        ),
      ];
    }

    if (_tutor.showPrimaryAction) {
      final label = _tutor.primaryActionLabel ?? '';
      return [
        TutorActionButton(
          key: ValueKey<String>('assist-primary-$label'),
          label: label,
          onPressed: _tutor.continuePrimaryAction,
        ),
      ];
    }

    return const [];
  }
}

/// Stable transcript + optional Stage 1 example controls (circle-independent).
class _TutorDialogueContent extends StatelessWidget {
  const _TutorDialogueContent({required this.tutor});

  final TutorSession tutor;

  /// Keeps dialogue / controls from shifting the circle on Stage 1.
  static const double _dialogueSlotHeight = 120;

  /// Caps listen-prompt type size so the music cue can sit close beneath it.
  static const double _referenceListenTextMaxHeight = 64;

  @override
  Widget build(BuildContext context) {
    final dialogue = tutor.dialogueText;
    final showExample = tutor.showHearSa;
    final confirmed = tutor.confirmedShrutiLabel;
    final showReferenceListenCue =
        dialogue == TutorScripts.referenceListenPrompt;

    // Completion already emphasizes the Shruti name; let dialogue size naturally.
    final useFixedDialogueSlot = confirmed == null;

    final dialogueText = dialogue == null
        ? const SizedBox.shrink()
        : TutorDialogueText(
            // Key by the on-screen text (not stale activeDialogue id) so a
            // leftover countdown id such as S09 cannot keep a widget alive
            // across the listen-prompt → countdown transition.
            key: ValueKey<String>(
              'tutor-dialogue-$dialogue'
              '${tutor.isDialogueInstruction ? '-hint' : ''}',
            ),
            text: dialogue,
            isSpeaking: tutor.isSpeaking,
            isInstruction: tutor.isDialogueInstruction,
          );

    // Compact text + two-note cue as one instruction unit (gap is spaceSm only).
    final dialogueChild = showReferenceListenCue
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _referenceListenTextMaxHeight,
                ),
                child: dialogueText,
              ),
              const SizedBox(height: DesignTokens.spaceSm),
              Icon(
                Symbols.music_note_2,
                key: const ValueKey<String>('assist-reference-listen-cue'),
                size: 28,
                fill: 1.0,
                color: DesignTokens.muted.withValues(alpha: 0.72),
              ),
            ],
          )
        : dialogueText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (confirmed != null) ...[
          ShrutiRevealCelebration(
            key: ValueKey<String>('assist-shruti-celebration-$confirmed'),
            child: Text(
              confirmed,
              key: const ValueKey<String>('assist-confirmed-shruti'),
              style: Theme.of(context).textTheme.displaySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
        ],
        if (useFixedDialogueSlot)
          SizedBox(
            height: _dialogueSlotHeight,
            width: double.infinity,
            child: dialogueChild,
          )
        else
          SizedBox(width: double.infinity, child: dialogueChild),
        // Keep the example controls visually separate from the instruction.
        if (showExample) ...[
          const SizedBox(height: 28),
          TutorHearSaControl(
            isPlaying: tutor.isHearSaPlaying,
            phase: tutor.exampleControlPhase,
            onPressed: tutor.toggleHearSa,
          ),
          if (tutor.showShuffleExample)
            TutorShuffleExampleAction(
              enabled: tutor.canShuffleExample,
              onPressed: tutor.shuffleExampleSound,
            ),
        ],
      ],
    );
  }
}
