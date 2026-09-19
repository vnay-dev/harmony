import 'package:flutter/material.dart';

import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/audio/just_audio_service.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/mic_pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/reference_pitch_adjuster.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/theme/design_tokens.dart';

/// Assist Mode: Stage 1 find starting Shruti, Stage 2 explore comfort range.
class AssistModeScreen extends StatefulWidget {
  const AssistModeScreen({
    super.key,
    PitchDetectionService? detectionService,
    AudioService? audioService,
    StablePitchCandidateFinder? candidateFinder,
    ReferencePitchAdjuster? pitchAdjuster,
    TargetPitchMatcher? targetMatcher,
    AssistModeController? controller,
    this.timing,
    this.initialReferencePitch,
    this.wait,
    this.prepareAudioSession,
  }) : _detectionService = detectionService,
       _audioService = audioService,
       _candidateFinder = candidateFinder,
       _pitchAdjuster = pitchAdjuster,
       _targetMatcher = targetMatcher,
       _controller = controller;

  final PitchDetectionService? _detectionService;
  final AudioService? _audioService;
  final StablePitchCandidateFinder? _candidateFinder;
  final ReferencePitchAdjuster? _pitchAdjuster;
  final TargetPitchMatcher? _targetMatcher;
  final AssistModeController? _controller;

  /// Optional timing overrides (tests / tuning).
  final AssistTimingConfig? timing;

  /// Optional starting Sa (defaults to the app default pitch).
  final Pitch? initialReferencePitch;

  /// Optional wait override so tests can skip window delays.
  final Future<void> Function(Duration duration)? wait;

  /// Optional audio-session setup override (tests inject a no-op).
  final Future<void> Function()? prepareAudioSession;

  @override
  State<AssistModeScreen> createState() => _AssistModeScreenState();
}

class _AssistModeScreenState extends State<AssistModeScreen> {
  late final AssistModeController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    final injected = widget._controller;
    if (injected != null) {
      _controller = injected;
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
        timing: widget.timing ?? const AssistTimingConfig(),
        initialReferencePitch:
            widget.initialReferencePitch ?? Pitch.defaultPitch,
        wait: widget.wait,
        prepareAudioSession: widget.prepareAudioSession,
      );
      _ownsController = true;
    }
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// Prominent Shruti for Stage 1 result, Stage 2 testing, or completion.
  Pitch? get _prominentShruti {
    final phase = _controller.uiPhase;
    if (phase == AssistUiPhase.intro || phase == AssistUiPhase.retry) {
      return null;
    }
    if (phase == AssistUiPhase.startingPointFound) {
      return _controller.stage1Shruti ?? _controller.referencePitch;
    }
    if (phase == AssistUiPhase.completed) {
      return _controller.referencePitch;
    }
    if (_controller.isExploringRange) {
      return _controller.currentExploreCandidate ?? _controller.referencePitch;
    }
    return null;
  }

  bool get _showProminentShruti => _prominentShruti != null;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final errorMessage = _controller.errorMessage;
    final uiPhase = _controller.uiPhase;
    final prominent = _prominentShruti;
    final showRound =
        _controller.isSessionActive &&
        !_controller.isExploringRange &&
        uiPhase != AssistUiPhase.intro &&
        uiPhase != AssistUiPhase.completed &&
        uiPhase != AssistUiPhase.startingPointFound &&
        uiPhase != AssistUiPhase.awaitingComfort;

    return Scaffold(
      appBar: AppBar(title: const Text('Assist Mode')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showRound) ...[
                Text(
                  'Round ${_controller.currentRound}',
                  key: const ValueKey<String>('assist-round'),
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.64),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Text(
                  _cycleHint(uiPhase),
                  key: ValueKey<String>('assist-cycle-$uiPhase'),
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DesignTokens.spaceLg),
              ],
              const Spacer(),
              if (_showProminentShruti && prominent != null) ...[
                Text(
                  prominent.label,
                  key: ValueKey<String>(
                    uiPhase == AssistUiPhase.completed
                        ? 'assist-confirmed-shruti'
                        : 'assist-prominent-shruti',
                  ),
                  style: textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DesignTokens.spaceLg),
              ],
              Text(
                _actionCue(uiPhase, prominent),
                key: ValueKey<String>('assist-headline-$uiPhase'),
                style: textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (_supportText(uiPhase) != null) ...[
                const SizedBox(height: DesignTokens.spaceMd),
                Text(
                  _supportText(uiPhase)!,
                  key: ValueKey<String>('assist-support-$uiPhase'),
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (uiPhase == AssistUiPhase.intro) ...[
                const SizedBox(height: DesignTokens.spaceMd),
                Text(
                  "You don't need to know your pitch.",
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (uiPhase == AssistUiPhase.listening) ...[
                const SizedBox(height: DesignTokens.spaceXl),
                _ListenProgress(
                  progress: _controller.listenProgress,
                  colorScheme: colorScheme,
                  showSingHint: !_controller.isExploringRange,
                ),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: DesignTokens.spaceLg),
                Text(
                  errorMessage,
                  style: textTheme.bodyLarge?.copyWith(
                    color: colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              ..._buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  String _cycleHint(AssistUiPhase phase) {
    switch (phase) {
      case AssistUiPhase.playingReference:
        return 'LISTEN → sing → Harmony adjusts';
      case AssistUiPhase.preparingToListen:
      case AssistUiPhase.listening:
        return _controller.isVerifying
            ? 'listen → SING → confirm'
            : 'listen → SING → Harmony adjusts';
      case AssistUiPhase.processing:
      case AssistUiPhase.showingTransition:
        return _controller.isVerifying
            ? 'listen → sing → CONFIRM'
            : 'listen → sing → HARMONY ADJUSTS';
      case AssistUiPhase.verifying:
        return 'Almost there — confirming';
      case AssistUiPhase.retry:
        return 'Let\'s try this round again';
      case AssistUiPhase.intro:
      case AssistUiPhase.startingPointFound:
      case AssistUiPhase.awaitingComfort:
      case AssistUiPhase.completed:
        return '';
    }
  }

  /// Primary instruction: what the user should do right now.
  String _actionCue(AssistUiPhase phase, Pitch? prominent) {
    final label = prominent?.label;

    if (_controller.isExploringRange ||
        phase == AssistUiPhase.startingPointFound ||
        phase == AssistUiPhase.completed) {
      switch (phase) {
        case AssistUiPhase.startingPointFound:
          return 'We found your match';
        case AssistUiPhase.showingTransition:
          return _controller.isExploreStepUpPending
              ? 'Great. Let\'s try one step higher.'
              : 'Now let\'s find your comfortable Shruti';
        case AssistUiPhase.playingReference:
          return 'Listen';
        case AssistUiPhase.preparingToListen:
          return 'Get ready';
        case AssistUiPhase.listening:
          return 'Sing and hold';
        case AssistUiPhase.processing:
          return _controller.didMatchCurrentExploreTarget
              ? 'Got it'
              : 'Checking…';
        case AssistUiPhase.awaitingComfort:
          return label == null ? 'How does that feel?' : 'How does $label feel?';
        case AssistUiPhase.completed:
          return 'Your comfortable Shruti';
        case AssistUiPhase.intro:
        case AssistUiPhase.verifying:
        case AssistUiPhase.retry:
          break;
      }
    }

    switch (phase) {
      case AssistUiPhase.intro:
        return 'Find your Shruti';
      case AssistUiPhase.playingReference:
        return 'Listen to your reference';
      case AssistUiPhase.verifying:
        return 'Listen once more';
      case AssistUiPhase.preparingToListen:
        return 'Get ready';
      case AssistUiPhase.listening:
        return _controller.isVerifying
            ? 'Sing your comfortable note again.'
            : 'Now, sing comfortably and hold your note.';
      case AssistUiPhase.processing:
      case AssistUiPhase.showingTransition:
        return 'Lovely. Take a moment to listen.';
      case AssistUiPhase.retry:
        return "I couldn't catch a steady note";
      case AssistUiPhase.startingPointFound:
        return 'We found your match';
      case AssistUiPhase.awaitingComfort:
        return label == null ? 'How does that feel?' : 'How does $label feel?';
      case AssistUiPhase.completed:
        return 'Your comfortable Shruti';
    }
  }

  String? _supportText(AssistUiPhase phase) {
    if (_controller.isExploringRange ||
        phase == AssistUiPhase.startingPointFound) {
      switch (phase) {
        case AssistUiPhase.startingPointFound:
          return 'Now let\'s find your comfortable Shruti';
        case AssistUiPhase.showingTransition:
          return _controller.isExploreStepUpPending
              ? 'Next, listen and sing along.'
              : null;
        case AssistUiPhase.playingReference:
        case AssistUiPhase.preparingToListen:
        case AssistUiPhase.listening:
        case AssistUiPhase.processing:
        case AssistUiPhase.awaitingComfort:
          return null;
        case AssistUiPhase.completed:
          return 'Your Shruti is ready. Enjoy practicing.';
        case AssistUiPhase.intro:
        case AssistUiPhase.verifying:
        case AssistUiPhase.retry:
          break;
      }
    }

    switch (phase) {
      case AssistUiPhase.intro:
        return 'Harmony will play a reference, then ask you to sing.';
      case AssistUiPhase.playingReference:
        return 'Relax and listen.';
      case AssistUiPhase.verifying:
        return 'Harmony thinks this reference fits — confirming with you.';
      case AssistUiPhase.preparingToListen:
        return 'When you are ready, sing one comfortable note.';
      case AssistUiPhase.listening:
        return 'Keep holding the same note.';
      case AssistUiPhase.processing:
        return _controller.isVerifying
            ? 'Checking that this still feels right.'
            : 'Harmony is gently adjusting your reference.';
      case AssistUiPhase.showingTransition:
        return _controller.isVerifying
            ? 'One more listen to confirm.'
            : 'Next, listen again to the updated reference.';
      case AssistUiPhase.retry:
        return 'Try again and hold one comfortable note a little longer.';
      case AssistUiPhase.startingPointFound:
        return 'Now let\'s find your comfortable Shruti';
      case AssistUiPhase.awaitingComfort:
        return null;
      case AssistUiPhase.completed:
        return 'Your Shruti is ready. Enjoy practicing.';
    }
  }

  List<Widget> _buildActions() {
    final busy = _controller.isBusy;

    switch (_controller.uiPhase) {
      case AssistUiPhase.intro:
        return [
          SizedBox(
            height: DesignTokens.controlHeight,
            child: FilledButton(
              onPressed: busy ? null : _controller.startSession,
              child: const Text('Start'),
            ),
          ),
        ];
      case AssistUiPhase.playingReference:
      case AssistUiPhase.verifying:
      case AssistUiPhase.preparingToListen:
      case AssistUiPhase.listening:
      case AssistUiPhase.processing:
      case AssistUiPhase.showingTransition:
      case AssistUiPhase.startingPointFound:
        return [
          SizedBox(
            height: DesignTokens.controlHeight,
            child: OutlinedButton(
              onPressed: busy ? null : _controller.stopSession,
              child: const Text('Stop'),
            ),
          ),
        ];
      case AssistUiPhase.awaitingComfort:
        return [
          SizedBox(
            height: DesignTokens.controlHeight,
            child: FilledButton(
              key: const ValueKey<String>('assist-comfortable'),
              onPressed: busy ? null : _controller.reportComfortable,
              child: const Text('Comfortable'),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          SizedBox(
            height: DesignTokens.controlHeight,
            child: OutlinedButton(
              key: const ValueKey<String>('assist-not-comfortable'),
              onPressed: busy ? null : _controller.reportNotComfortable,
              child: const Text('Not comfortable'),
            ),
          ),
        ];
      case AssistUiPhase.retry:
        return [
          SizedBox(
            height: DesignTokens.controlHeight,
            child: FilledButton(
              onPressed: busy ? null : _controller.retryRound,
              child: const Text('Try again'),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          SizedBox(
            height: DesignTokens.controlHeight,
            child: OutlinedButton(
              onPressed: busy ? null : _controller.stopSession,
              child: const Text('Stop'),
            ),
          ),
        ];
      case AssistUiPhase.completed:
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
              onPressed: busy ? null : _controller.tryAgain,
              child: const Text('Try Again'),
            ),
          ),
        ];
    }
  }
}

class _ListenProgress extends StatelessWidget {
  const _ListenProgress({
    required this.progress,
    required this.colorScheme,
    required this.showSingHint,
  });

  final double progress;
  final ColorScheme colorScheme;
  final bool showSingHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.mic, size: 36, color: colorScheme.primary),
        const SizedBox(height: DesignTokens.spaceMd),
        ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          child: LinearProgressIndicator(
            key: const ValueKey<String>('assist-listen-progress'),
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.16),
            color: colorScheme.primary,
          ),
        ),
        if (showSingHint) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            'Keep singing…',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
