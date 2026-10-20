import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:harmony/tutor/http_tutor_voice.dart';
import 'package:harmony/tutor/kitten_tts_bootstrap.dart';
import 'package:harmony/tutor/kitten_tutor_voice.dart';
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

/// Debug-only. Profile and release builds ignore this define.
const _useHttpTutorVoiceFromEnvironment = bool.fromEnvironment(
  'USE_HTTP_TUTOR_VOICE',
);

bool _wantsHttpTutorVoice(bool useHttpTutorVoice) {
  return useHttpTutorVoice || (kDebugMode && _useHttpTutorVoiceFromEnvironment);
}

/// Kitten Micro + Luna (1.1×) is the default when [tutorVoice] is omitted.
///
/// No feature flag is required. HTTP always wins when selected (widget flag or
/// debug dart-define), including when both HTTP and Kitten flags are enabled.
bool _wantsKittenTutorVoice({
  required bool useHttpTutorVoice,
  required bool useKittenTutorVoice,
}) {
  if (_wantsHttpTutorVoice(useHttpTutorVoice)) {
    return false;
  }
  // Keep reading [useKittenTutorVoice] so the public flag stays part of the
  // selection API (HTTP-vs-Kitten precedence tests). Enabling Kitten no longer
  // depends on it.
  final _ = useKittenTutorVoice;
  return true;
}

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
    KittenTtsBootstrap? kittenBootstrap,
    this.timing,
    this.tutorTiming,
    this.initialReferencePitch,
    this.wait,
    this.prepareAudioSession,
    this.useHttpTutorVoice = false,
    this.useKittenTutorVoice = false,
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
       _speechRecognizer = speechRecognizer,
       _kittenBootstrap = kittenBootstrap;

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
  final KittenTtsBootstrap? _kittenBootstrap;

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

  /// Selects [HttpTutorVoice] when [tutorVoice] is omitted.
  ///
  /// Pass this for local testing against the laptop TTS server, or pass
  /// [tutorVoice] to inject any voice. Takes precedence over Kitten (the
  /// default) and over [useKittenTutorVoice].
  final bool useHttpTutorVoice;

  /// Explicit Kitten request when [tutorVoice] is omitted.
  ///
  /// Kitten Micro + Luna is already the default whenever HTTP is not selected,
  /// so this flag is optional. Kept so HTTP still wins when both are true.
  final bool useKittenTutorVoice;

  /// When true (default), welcome speech runs and waits for "Let's begin".
  final bool autoBegin;

  @override
  State<AssistModeScreen> createState() => _AssistModeScreenState();
}

class _AssistModeScreenState extends State<AssistModeScreen> {
  late final AssistModeController _controller;
  TutorSession? _tutor;
  late final bool _ownsController;
  bool _ownsTutor = false;
  KittenTtsBootstrap? _kittenBootstrap;
  bool _ownsKittenBootstrap = false;
  bool _kittenSessionStarted = false;

  bool get _awaitingKittenReady => _kittenBootstrap != null && _tutor == null;

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

    _controller.addListener(_onChanged);

    final injectedTutor = widget._tutorSession;
    if (injectedTutor != null) {
      _attachTutor(injectedTutor, owns: false);
      if (widget.autoBegin) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _tutor?.begin();
          }
        });
      }
      return;
    }

    final needsKitten =
        widget._tutorVoice == null &&
        _wantsKittenTutorVoice(
          useHttpTutorVoice: widget.useHttpTutorVoice,
          useKittenTutorVoice: widget.useKittenTutorVoice,
        );

    if (needsKitten) {
      final injectedBootstrap = widget._kittenBootstrap;
      if (injectedBootstrap != null) {
        _kittenBootstrap = injectedBootstrap;
        _ownsKittenBootstrap = false;
      } else {
        _kittenBootstrap = KittenTtsBootstrap();
        _ownsKittenBootstrap = true;
      }
      _kittenBootstrap!.addListener(_onChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_bootstrapKittenAndStart());
        }
      });
      return;
    }

    // Non-Kitten path: injected voice, or HTTP debug voice (HTTP wins over Kitten).
    _attachTutor(
      TutorSession(
        engine: _controller,
        voice: widget._tutorVoice ?? HttpTutorVoice(),
        speechRecognizer:
            widget._speechRecognizer ?? SpeechToTextTutorRecognizer(),
        timing: widget.tutorTiming ?? const TutorTimingConfig(),
        // Do not share the engine wait — speech pauses must never block on
        // Assist listen/reference windows.
      ),
      owns: true,
    );
    if (widget.autoBegin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _tutor?.begin();
        }
      });
    }
  }

  void _attachTutor(TutorSession tutor, {required bool owns}) {
    _tutor = tutor;
    _ownsTutor = owns;
    tutor.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _bootstrapKittenAndStart({bool forceRedownload = false}) async {
    final bootstrap = _kittenBootstrap;
    if (bootstrap == null || _kittenSessionStarted) {
      return;
    }
    try {
      final synthesizer = forceRedownload
          ? await bootstrap.retry(forceRedownload: true)
          : await bootstrap.ensureReady();
      if (!mounted || _kittenSessionStarted) {
        return;
      }
      _startKittenTutorSession(synthesizer);
    } catch (_) {
      // [KittenTtsBootstrap] already records failed state + error for the UI.
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _startKittenTutorSession(KittenTutorSynthesizer synthesizer) {
    if (_kittenSessionStarted || !mounted) {
      return;
    }
    _kittenSessionStarted = true;
    final voice = KittenTutorVoice(
      synthesizer: synthesizer,
      // Bootstrap owns the engine lifetime for this screen.
      ownsSynthesizer: false,
    );
    _attachTutor(
      TutorSession(
        engine: _controller,
        voice: voice,
        speechRecognizer:
            widget._speechRecognizer ?? SpeechToTextTutorRecognizer(),
        timing: widget.tutorTiming ?? const TutorTimingConfig(),
      ),
      owns: true,
    );
    setState(() {});
    if (widget.autoBegin) {
      unawaited(_tutor!.begin());
    }
  }

  Future<void> _retryKittenBootstrap() {
    return _bootstrapKittenAndStart();
  }

  void _goHome() {
    // Detach before teardown so stop()/pop cannot rebuild a dying route.
    _tutor?.removeListener(_onChanged);
    _controller.removeListener(_onChanged);
    _kittenBootstrap?.removeListener(_onChanged);

    final tutor = _tutor;
    if (tutor != null &&
        tutor.step != TutorStep.complete &&
        tutor.step != TutorStep.stopped) {
      // Start cancellation without awaiting listen/wait teardown.
      unawaited(tutor.stop());
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
    _tutor?.removeListener(_onChanged);
    _controller.removeListener(_onChanged);
    _kittenBootstrap?.removeListener(_onChanged);
    if (_ownsTutor) {
      _tutor?.dispose();
    }
    if (_ownsKittenBootstrap) {
      _kittenBootstrap?.dispose();
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
    final tutor = _tutor;
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
          if (tutor == null || tutor.showHome)
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
          child: _awaitingKittenReady
              ? _buildKittenReadyGate(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildTutorSurface(tutor!)),
                    const SizedBox(height: DesignTokens.spaceMd),
                    ..._buildActions(tutor),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildKittenReadyGate(BuildContext context) {
    final bootstrap = _kittenBootstrap!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (bootstrap.state == KittenTtsReadyState.failed) {
      final detail = bootstrap.error?.toString().trim();
      return Column(
        key: const ValueKey<String>('kitten-tts-error'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: colorScheme.error.withValues(alpha: 0.85),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          Text(
            'Could not prepare the tutor voice.',
            style: textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            Text(
              detail,
              key: const ValueKey<String>('kitten-tts-error-detail'),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.62),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const Spacer(),
          TutorActionButton(
            key: const ValueKey<String>('kitten-tts-retry'),
            label: 'Retry',
            onPressed: () {
              unawaited(_retryKittenBootstrap());
            },
          ),
        ],
      );
    }

    final progress = bootstrap.progress;
    final determinate = progress > 0 && progress < 1;
    return Column(
      key: const ValueKey<String>('kitten-tts-loading'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              key: const ValueKey<String>('kitten-tts-progress'),
              value: determinate ? progress : null,
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        Text(
          'Preparing tutor voice…',
          style: textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (determinate) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            '${(progress * 100).round()}%',
            key: const ValueKey<String>('kitten-tts-progress-label'),
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const Spacer(),
      ],
    );
  }

  /// Circle slot above an independent transcript region.
  ///
  /// Shared by Stage 1, Stage 2, and terminal states so the calm circle +
  /// dialogue composition never flips to the old headline surface.
  Widget _buildTutorSurface(TutorSession tutor) {
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
                        state: tutor.presenceState,
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
                _TutorDialogueContent(tutor: tutor),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActions(TutorSession tutor) {
    // Terminal CTAs stay available even if completion speech is finishing.
    if (tutor.showPlayMyShruti) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-play-my-shruti'),
          label: 'Play My Shruti',
          onPressed: tutor.isSpeaking
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
          onPressed: tutor.isSpeaking ? null : tutor.tryAgain,
        ),
      ];
    }

    if (tutor.showSessionStopped) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-session-stopped-try-again'),
          label: 'Try Again',
          onPressed: tutor.tryAgain,
        ),
      ];
    }

    // Buttons stay hidden until the current line has finished printing.
    if (tutor.isSpeaking) {
      return const [];
    }

    if (tutor.showDifferentSoundChoice) {
      final canAnswer = tutor.canAnswerDifferentSound;
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-different-sound-yes'),
          label: 'Yes',
          onPressed: canAnswer ? () => tutor.answerDifferentSound(true) : null,
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TutorActionButton(
          key: const ValueKey<String>('assist-different-sound-no'),
          label: 'No',
          primary: false,
          onPressed: canAnswer ? () => tutor.answerDifferentSound(false) : null,
        ),
      ];
    }

    if (tutor.showYesNoFallback) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-lower-audible-yes'),
          label: TutorScripts.ctaHeardClearly,
          onPressed: () => tutor.answerLowerAudibility(true),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TutorActionButton(
          key: const ValueKey<String>('assist-lower-too-low'),
          label: TutorScripts.ctaHardToHear,
          primary: false,
          onPressed: () => tutor.answerLowerAudibility(false),
        ),
      ];
    }

    if (tutor.showComfortFallback) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-upper-comfortable'),
          label: TutorScripts.ctaComfortable,
          onPressed: () => tutor.answerUpperComfort(true),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        TutorActionButton(
          key: const ValueKey<String>('assist-upper-strained'),
          label: TutorScripts.ctaNotComfortable,
          primary: false,
          onPressed: () => tutor.answerUpperComfort(false),
        ),
      ];
    }

    if (tutor.showTryAgain) {
      return [
        TutorActionButton(
          key: const ValueKey<String>('assist-unresolved-try-again'),
          label: 'Try Again',
          onPressed: tutor.tryAgain,
        ),
      ];
    }

    if (tutor.showPrimaryAction) {
      final label = tutor.primaryActionLabel ?? '';
      return [
        TutorActionButton(
          key: ValueKey<String>('assist-primary-$label'),
          label: label,
          onPressed: tutor.continuePrimaryAction,
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
            holdReveal: tutor.isHoldingTranscript,
            revealDuration: tutor.transcriptRevealDuration,
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
