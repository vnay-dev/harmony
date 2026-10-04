import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/tutor/assist_tutor_hooks.dart';
import 'package:harmony/tutor/tutor_answer.dart';
import 'package:harmony/tutor/tutor_sa_sample_player.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_speech_recognizer.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice.dart';
import 'package:harmony/tutor/tutor_voice_coordinator.dart';

/// Conversational tutor layer over the existing Assist search engine.
///
/// Owns welcome, spoken scripts (via [TutorVoiceCoordinator]), countdown
/// speech sync, auto-retry, spoken Yes/No listening, and auto-advance after
/// range boundary. Pitch detection and Shruti search stay in
/// [AssistModeController].
class TutorSession extends ChangeNotifier {
  TutorSession({
    required AssistModeController engine,
    required TutorVoice voice,
    TutorSpeechRecognizer? speechRecognizer,
    TutorAnswerParser answerParser = const TutorAnswerParser(),
    TutorTimingConfig timing = const TutorTimingConfig(),
    Future<void> Function(Duration duration)? wait,
    TutorSaSamplePlayer? saSamplePlayer,
    this.maxStage1AutoRetries = 5,
  }) : _engine = engine,
       _answerParser = answerParser,
       _speech = speechRecognizer ?? SilentTutorSpeechRecognizer(),
       _voice = TutorVoiceCoordinator(voice: voice, timing: timing, wait: wait),
       _saSample = saSamplePlayer ?? TutorSaSamplePlayer(),
       _timing = timing {
    _voice.onChanged = _onVoiceChanged;
    _saSample.onChanged = _onSaSampleChanged;
    _engine.tutorHooks = AssistTutorHooks(
      beforeReference: _onBeforeReference,
      afterReference: _onAfterReference,
      beforeCountdown: _onBeforeCountdown,
      onCountdownStep: _onCountdownStep,
      beforeListen: _onBeforeListen,
      afterListenWindow: _onAfterListenWindow,
      beforeAssistedSinging: _onBeforeAssistedSinging,
      onAssistedReferenceWillStart: _onAssistedReferenceWillStart,
      afterAssistedSinging: _onAfterAssistedSinging,
      afterAssistedPracticeUnconfirmed: _onAssistedPracticeUnconfirmed,
      beforeCompletionPlayback: _onBeforeCompletionPlayback,
    );
    _engine.addListener(_onEngineChanged);
    _syncStepFromEngine();
  }

  final AssistModeController _engine;
  final TutorVoiceCoordinator _voice;
  final TutorSpeechRecognizer _speech;
  final TutorAnswerParser _answerParser;
  final TutorTimingConfig _timing;
  final TutorSaSamplePlayer _saSample;

  /// Retained for API compatibility. Stage 1 retries are always explicit taps.
  final int maxStage1AutoRetries;

  TutorStep _step = TutorStep.welcome;
  bool _welcomeStarted = false;
  bool _isDisposed = false;
  bool _handlingPhase = false;
  bool _phaseDirty = false;
  AssistUiPhase? _lastHandledPhase;
  int _stage1AutoRetryCount = 0;
  int _countdownEpoch = 0;
  int _lastHandledStage1FailureCount = 0;
  final List<int> _countdownEmitted = <int>[];
  bool _listeningForSpeechAnswer = false;
  bool _stopRequested = false;
  int _unclearAnswerCount = 0;
  bool _questionOpen = false;
  bool _differentSoundChoiceReady = false;
  TutorPrimaryAction _primaryAction = TutorPrimaryAction.none;
  Completer<void>? _primaryActionCompleter;
  bool _showStage1SuccessMark = false;

  /// After a Stage 1 miss, offer Hear Sa + shuffle under the recovery lines.
  bool _stage1ExampleControls = false;

  /// After S61 finishes speaking: same S61 text uses instruction (grey) style.
  bool _stage1RecoveryInstruction = false;

  /// True once the user commits to singing until Stage 1 listen ends.
  ///
  /// Prevents a stale pre-listen transcript frame while the engine transitions
  /// into [AssistUiPhase.listening].
  bool _stage1AwaitingUserTurn = false;

  /// Holds the "Listen to this sound…" prompt from reference start until
  /// countdown (Stage 2) or solo listen (Stage 1) takes over — blocks stale
  /// pre-reference transcript such as S74.
  bool _holdReferenceListenPrompt = false;

  TutorExampleControlPhase _examplePhase = TutorExampleControlPhase.idle;
  int _exampleShuffleGeneration = 0;

  /// Bumped on Stop and on each fresh start so late callbacks cannot continue.
  int _sessionToken = 0;
  Future<void>? _stopTail;

  AssistModeController get engine => _engine;

  TutorStep get step => _step;

  bool get isSpeaking => _voice.isSpeaking;

  /// True while waiting for a spoken Yes/No or comfort answer.
  bool get isListeningForSpeechAnswer => _listeningForSpeechAnswer;

  String? get lastVoiceLine => _voice.lastLine;

  /// Dialogue currently driving transcript + audio (null when unmapped/silent).
  TutorDialogue? get activeDialogue => _voice.activeDialogue;

  List<String> get spokenLog => _voice.spokenLog;

  /// Countdown values spoken in the current countdown run (tests).
  List<int> get countdownEmitted => List<int>.unmodifiable(_countdownEmitted);

  int? get countdownValue => _engine.countdownValue;

  TutorTeachingLevel get teachingLevel => _engine.teachingLevel;

  /// How many Stage 1 "Let's try again" taps have been used this session.
  int get stage1RetryCount => _stage1AutoRetryCount;

  double get progress {
    switch (_step) {
      case TutorStep.welcome:
      case TutorStep.orientation:
        return 0.05;
      case TutorStep.discoverStartingNote:
      case TutorStep.startingNoteFailure:
        return 0.15;
      case TutorStep.startingNoteCaptured:
        return 0.3;
      case TutorStep.testLower:
      case TutorStep.askLowerAudibility:
        return 0.45;
      case TutorStep.testMiddle:
      case TutorStep.askMiddleComfort:
        return 0.6;
      case TutorStep.testUpper:
      case TutorStep.askUpperComfort:
        return 0.75;
      case TutorStep.exploreNextShruti:
      case TutorStep.offerDifferentSound:
        return 0.85;
      case TutorStep.complete:
        return 1;
      case TutorStep.unresolved:
        return 0.9;
      case TutorStep.stopped:
        return 0;
    }
  }

  bool _isLive(int token) =>
      !_isDisposed && !_stopRequested && token == _sessionToken;

  /// Quiet heading above the journey indicator.
  static const journeyHeading = 'Finding your Shruti';

  /// Journey checklist is retired from the tutor surface (calm circle + dialogue).
  bool get showJourneyProgress => false;

  /// Visible journey place. Null during Stage 1 and after Stop.
  TutorJourneyStage? get journeyStage {
    if (_step == TutorStep.welcome || _step == TutorStep.stopped) {
      return null;
    }
    final phase = _engine.uiPhase;
    if (_step == TutorStep.complete ||
        _step == TutorStep.unresolved ||
        phase == AssistUiPhase.completed ||
        phase == AssistUiPhase.rangeBoundaryReached ||
        phase == AssistUiPhase.rangeUnresolved) {
      return TutorJourneyStage.findShruti;
    }
    if (_engine.isExploringRange) {
      return TutorJourneyStage.exploreRange;
    }
    return null;
  }

  /// Bottom CTA waiting for an explicit Stage 1 tap.
  TutorPrimaryAction get primaryAction => _primaryAction;

  bool get showPrimaryAction => _primaryAction != TutorPrimaryAction.none;

  /// Secondary "Listen to an example" control under the Stage 1 instruction.
  bool get showHearSa =>
      _primaryAction == TutorPrimaryAction.imReadyToListen ||
      (_stage1ExampleControls &&
          _primaryAction == TutorPrimaryAction.letsTryAgain);

  /// Tertiary shuffle prompt under the example button (failure recovery only).
  bool get showShuffleExample =>
      _stage1ExampleControls &&
      _primaryAction == TutorPrimaryAction.letsTryAgain;

  /// True while the optional Stage 1 Sa sample is audible.
  bool get isHearSaPlaying => _saSample.isPlaying;

  /// Idle / loading / loaded visual phase for the example button.
  TutorExampleControlPhase get exampleControlPhase => _examplePhase;

  /// Whether the tertiary shuffle action can start a new prepare cycle.
  ///
  /// Allowed while an example is playing — shuffle stops it, then loads.
  bool get canShuffleExample =>
      showShuffleExample && _examplePhase == TutorExampleControlPhase.idle;

  /// True when [dialogueText] is a non-spoken UI hint (lighter style).
  bool get isDialogueInstruction {
    if (isSpeaking) {
      return false;
    }
    return _stage1RecoveryInstruction ||
        _stage1AwaitingUserTurn ||
        _engine.uiPhase == AssistUiPhase.listening ||
        _engine.uiPhase == AssistUiPhase.assistedSinging ||
        _showsReferenceListenPrompt;
  }

  /// Reference-listen instruction while the hold is active.
  ///
  /// Covers playback, settle ([AssistUiPhase.preparingToListen]), and the
  /// gap until countdown / Stage 1 speech binds a replacement transcript.
  /// While hold is set and no spoken line is bound yet, keep the listen prompt
  /// — even if [isSpeaking] has flipped true during audio spin-up.
  bool get _showsReferenceListenPrompt {
    if (!_holdReferenceListenPrompt) {
      return false;
    }
    if (isSpeaking) {
      final bound = activeDialogue?.text ?? lastVoiceLine;
      if (bound != null && bound.trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  String? get primaryActionLabel {
    switch (_primaryAction) {
      case TutorPrimaryAction.letsBegin:
        return TutorScripts.ctaLetsBegin;
      case TutorPrimaryAction.imReadyToListen:
        return TutorScripts.ctaImReadyToSingSa;
      case TutorPrimaryAction.imReadyForNextStep:
        return TutorScripts.ctaImReady;
      case TutorPrimaryAction.letsTryAgain:
        return TutorScripts.ctaLetsTryAgain;
      case TutorPrimaryAction.playTheSound:
        return TutorScripts.ctaPlayTheSound;
      case TutorPrimaryAction.none:
        return null;
    }
  }

  /// Stage 1 capture success — drives the presence circle success state.
  bool get showStage1SuccessMark => _showStage1SuccessMark;

  /// Visual state for the persistent tutor circle.
  TutorPresenceState get presenceState {
    if (isSpeaking) {
      return TutorPresenceState.speaking;
    }
    if (_showStage1SuccessMark) {
      return TutorPresenceState.success;
    }
    if (_step == TutorStep.complete) {
      return TutorPresenceState.success;
    }
    if (_engine.uiPhase == AssistUiPhase.listening) {
      return TutorPresenceState.listening;
    }
    return TutorPresenceState.idle;
  }

  /// Large dialogue / instruction text for the tutor screen.
  ///
  /// While Harmony is speaking, this is always the active dialogue text — never
  /// a step/phase fallback. After speech, mirrors the last spoken line unless a
  /// listen prompt must replace it (Stage 1 or Stage 2 solo turn).
  String? get dialogueText {
    if (_step == TutorStep.stopped) {
      return TutorScripts.sessionStopped;
    }
    // Hold listen prompt until a replacement spoken line is bound. Checked
    // before the generic speaking branch so audio spin-up cannot expose a
    // stale transcript such as "1..." between reference and countdown.
    if (_holdReferenceListenPrompt) {
      if (isSpeaking) {
        final bound = activeDialogue?.text ?? lastVoiceLine;
        if (bound != null && bound.trim().isNotEmpty) {
          return bound;
        }
      }
      return TutorScripts.referenceListenPrompt;
    }
    // Authoritative while speaking: same object that selected the audio clip.
    if (isSpeaking) {
      final active = activeDialogue?.text ?? lastVoiceLine;
      if (active != null && active.trim().isNotEmpty) {
        return active;
      }
    }
    if (_step == TutorStep.complete) {
      final line = activeDialogue?.text ?? lastVoiceLine;
      // Only keep a real completion transcript — never a leftover question line.
      if (line != null &&
          line.trim().isNotEmpty &&
          line.startsWith(TutorDialogues.s39.text)) {
        return line;
      }
      return TutorScripts.completion(_engine.referencePitch.label);
    }
    if (_step == TutorStep.unresolved) {
      final line = activeDialogue?.text ?? lastVoiceLine;
      if (line != null && line.trim().isNotEmpty) {
        return line;
      }
      return TutorScripts.unresolved.first;
    }
    // While waiting for "Play the sound", keep S74 on screen (not the singing hint).
    if (_primaryAction == TutorPrimaryAction.playTheSound) {
      final line = activeDialogue?.text ?? lastVoiceLine;
      if (line != null && line.trim().isNotEmpty) {
        return line;
      }
    }
    // Countdown must only show real countdown lines — never a stale fragment.
    if (_engine.uiPhase == AssistUiPhase.countdown) {
      final line = activeDialogue?.text ?? lastVoiceLine;
      if (line != null && TutorScripts.isCountdownLine(line)) {
        return line;
      }
      return null;
    }
    // Assisted sing-along owns its instruction — never inherit "1..." from the
    // countdown that just finished.
    if (_engine.uiPhase == AssistUiPhase.assistedSinging) {
      if (isSpeaking) {
        final active = activeDialogue?.text ?? lastVoiceLine;
        if (active != null &&
            active.trim().isNotEmpty &&
            !TutorScripts.isCountdownLine(active)) {
          return active;
        }
      }
      return TutorScripts.assistedSingAlongPrompt;
    }
    if (_stage1AwaitingUserTurn) {
      return TutorScripts.stage1ListenPrompt;
    }
    if (_engine.uiPhase == AssistUiPhase.listening) {
      return TutorScripts.stage1ListenPrompt;
    }
    // Same transcript as the last spoken dialogue (S61 after failure recovery).
    // [_stage1RecoveryInstruction] only changes style via [isDialogueInstruction].
    final line = activeDialogue?.text ?? lastVoiceLine;
    if (line != null && line.trim().isNotEmpty) {
      return line;
    }
    if (_step == TutorStep.startingNoteCaptured) {
      return TutorScripts.stage1Success;
    }
    // Question steps mirror their spoken scripts when speech has not left a line.
    switch (_step) {
      case TutorStep.askLowerAudibility:
        return TutorScripts.lowerAudibilityQuestion;
      case TutorStep.askMiddleComfort:
      case TutorStep.askUpperComfort:
        return TutorScripts.upperComfortQuestion;
      case TutorStep.offerDifferentSound:
        return TutorScripts.offerDifferentSound;
      default:
        return null;
    }
  }

  static String journeyLabel(TutorJourneyStage stage) {
    switch (stage) {
      case TutorJourneyStage.listenToVoice:
        return 'Listen to your voice';
      case TutorJourneyStage.exploreRange:
        return 'Explore your range';
      case TutorJourneyStage.findShruti:
        return 'Find your Shruti';
    }
  }

  TutorJourneyMark journeyMark(TutorJourneyStage stage) {
    final current = journeyStage;
    if (current == null || stage.index > current.index) {
      return TutorJourneyMark.upcoming;
    }
    if (stage == current) {
      return TutorJourneyMark.current;
    }
    return TutorJourneyMark.complete;
  }

  /// Primary on-screen action cue. During countdown, only the countdown
  /// display shows the digit — headline stays a calm label.
  String get headline {
    // While speaking, mirror the active dialogue — except terminal steps whose
    // legacy surface uses fixed celebration / stopped labels.
    if (isSpeaking &&
        _step != TutorStep.complete &&
        _step != TutorStep.unresolved &&
        _step != TutorStep.stopped) {
      final spoken = activeDialogue?.text ?? lastVoiceLine;
      if (spoken != null && spoken.trim().isNotEmpty) {
        return spoken;
      }
    }
    final dialogue = dialogueText;
    if (dialogue != null &&
        (_step == TutorStep.welcome ||
            _step == TutorStep.discoverStartingNote ||
            _step == TutorStep.startingNoteCaptured ||
            _step == TutorStep.startingNoteFailure ||
            !_engine.isExploringRange)) {
      return dialogue;
    }
    switch (_step) {
      case TutorStep.welcome:
      case TutorStep.orientation:
        return TutorScripts.welcome.first;
      case TutorStep.discoverStartingNote:
        if (_engine.uiPhase == AssistUiPhase.refreshingStartingNote) {
          return TutorScripts.stepBackToVoice;
        }
        if (_engine.uiPhase == AssistUiPhase.listening) {
          return TutorScripts.stage1ListenPrompt;
        }
        if (_engine.uiPhase == AssistUiPhase.playingReference) {
          return 'Listen';
        }
        return TutorScripts.firstStepInstruction;
      case TutorStep.startingNoteFailure:
        return TutorScripts.startingNoteRetryOnce.first;
      case TutorStep.startingNoteCaptured:
        return TutorScripts.stage1Success;
      case TutorStep.testLower:
      case TutorStep.testMiddle:
      case TutorStep.testUpper:
      case TutorStep.exploreNextShruti:
        return _rangeActionHeadline();
      case TutorStep.offerDifferentSound:
        return TutorScripts.offerDifferentSound;
      case TutorStep.askLowerAudibility:
        return TutorScripts.lowerAudibilityQuestion;
      case TutorStep.askMiddleComfort:
      case TutorStep.askUpperComfort:
        return 'How did that feel?';
      case TutorStep.complete:
        return 'We found it';
      case TutorStep.unresolved:
        return "Let's try again";
      case TutorStep.stopped:
        return TutorScripts.sessionStopped;
    }
  }

  String? get supportText {
    // Listening screen stays focused — no secondary coaching under the prompt.
    if (_showsReferenceListenPrompt) {
      return null;
    }
    switch (_step) {
      case TutorStep.welcome:
      case TutorStep.orientation:
      case TutorStep.discoverStartingNote:
      case TutorStep.startingNoteCaptured:
        return null;
      case TutorStep.askLowerAudibility:
        return _listeningForSpeechAnswer
            ? 'Say yes or no — or tap below.'
            : 'Say yes or no — or tap below.';
      case TutorStep.askMiddleComfort:
      case TutorStep.askUpperComfort:
        return 'Say comfortable or not comfortable — or tap below.';
      case TutorStep.complete:
        return 'Your comfortable Shruti';
      case TutorStep.unresolved:
        return 'Whenever you are ready.';
      case TutorStep.stopped:
        return TutorScripts.sessionStoppedSupport;
      case TutorStep.offerDifferentSound:
        return 'Say yes or no — or tap below.';
      case TutorStep.startingNoteFailure:
      case TutorStep.testLower:
      case TutorStep.testMiddle:
      case TutorStep.testUpper:
      case TutorStep.exploreNextShruti:
        return _engine.isExploringRange ? _rangeSupportText() : null;
    }
  }

  bool get showCountdown =>
      _engine.isExploringRange &&
      _engine.uiPhase == AssistUiPhase.countdown &&
      _engine.countdownValue != null;

  /// Stage 1 never shows a listen timer or progress ring.
  bool get showListenProgress => false;

  /// Audibility CTAs — only while the question is still open for an answer.
  ///
  /// Cleared by [_claimQuestion] as soon as a tap/spoken answer is accepted so
  /// acknowledgement speech ("That's lovely.") never briefly re-shows the
  /// previous Yes/No buttons after [isSpeaking] flips false during its pause.
  bool get showYesNoFallback =>
      _step == TutorStep.askLowerAudibility && _questionOpen;

  /// Yes / No for trying a nearby sound. Separate from Lower Sa audibility.
  bool get showDifferentSoundChoice =>
      _step == TutorStep.offerDifferentSound &&
      _engine.uiPhase == AssistUiPhase.offeringEasierSound;

  /// True once the recovery question has been offered and can still be answered.
  ///
  /// Stays false while Stage 2 recovery speech is playing, and while a tap is
  /// already in progress, so the choice cannot fire twice or wait on a dead
  /// audio future.
  bool get canAnswerDifferentSound =>
      _differentSoundChoiceReady && _questionOpen && showDifferentSoundChoice;

  /// Comfort CTAs — only while the question is still open for an answer.
  ///
  /// Same lifecycle as [showYesNoFallback]: hide immediately on claim so the
  /// acknowledgement / "keep this comfortable" lines never inherit prior CTAs.
  bool get showComfortFallback =>
      (_step == TutorStep.askMiddleComfort ||
          _step == TutorStep.askUpperComfort) &&
      _questionOpen;

  bool get showPlayMyShruti => _step == TutorStep.complete;

  bool get showTryAgain => _step == TutorStep.unresolved;

  /// Explicit end state after the user taps Stop.
  bool get showSessionStopped => _step == TutorStep.stopped;

  /// Bottom Stop was replaced by the top-right Home control.
  ///
  /// Cancellation still runs through [stop]; the screen invokes it from Home.
  bool get showStop => false;

  /// Top-right Home is available throughout Tutor Mode.
  bool get showHome => true;

  String? get confirmedShrutiLabel =>
      _step == TutorStep.complete ? _engine.referencePitch.label : null;

  Future<void> begin() => _runWelcome(_sessionToken);

  Future<void> _runWelcome(int token) async {
    if (_welcomeStarted || _isDisposed || token != _sessionToken) {
      return;
    }
    _welcomeStarted = true;
    _setStep(TutorStep.welcome);
    notifyListeners();
    await _voice.speakAll(TutorScripts.welcome, eventIdPrefix: 'welcome');
    if (!_isLive(token)) {
      return;
    }
    await _awaitPrimaryAction(token, TutorPrimaryAction.letsBegin);
    if (!_isLive(token)) {
      return;
    }
    await _runFirstStep(token);
  }

  Future<void> _runFirstStep(int token) async {
    _setStep(TutorStep.discoverStartingNote);
    notifyListeners();
    await _voice.speakOnce('first-step-listen', TutorScripts.firstStepListen);
    if (!_isLive(token)) {
      return;
    }
    await _voice.speakOnce(
      'first-step-instruction',
      TutorScripts.firstStepInstruction,
      pauseAfter: _timing.shortTransitionPause,
    );
    if (!_isLive(token)) {
      return;
    }
    await _awaitPrimaryAction(token, TutorPrimaryAction.imReadyToListen);
    if (!_isLive(token) || _engine.isSessionActive) {
      return;
    }
    await _engine.startSession();
  }

  void _onVoiceChanged() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void _onSaSampleChanged() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Plays or pauses the optional Stage 1 Sa sample.
  Future<void> toggleHearSa() async {
    if (_isDisposed ||
        !showHearSa ||
        _examplePhase != TutorExampleControlPhase.idle) {
      return;
    }
    await _saSample.toggle();
  }

  /// Prepares a different synthesized example without auto-playing it.
  ///
  /// Does not speak, clear, or replay tutor dialogue. Only the example button
  /// phase changes while the surrounding layout stays stable.
  Future<void> shuffleExampleSound() async {
    if (_isDisposed || !canShuffleExample) {
      return;
    }
    final token = _sessionToken;
    final generation = ++_exampleShuffleGeneration;
    await _stopHearSa();
    if (!_isLive(token) || generation != _exampleShuffleGeneration) {
      return;
    }
    _examplePhase = TutorExampleControlPhase.loading;
    notifyListeners();
    try {
      await _saSample.prepareNextPitch();
    } catch (_) {
      if (!_isLive(token) || generation != _exampleShuffleGeneration) {
        return;
      }
      _examplePhase = TutorExampleControlPhase.idle;
      notifyListeners();
      return;
    }
    if (!_isLive(token) || generation != _exampleShuffleGeneration) {
      return;
    }
    _examplePhase = TutorExampleControlPhase.loaded;
    notifyListeners();
    // Quiet wait — must not set isSpeaking or the transcript will flash.
    await _voice.waitQuietly(_timing.exampleReadyAffirmationDuration);
    if (!_isLive(token) || generation != _exampleShuffleGeneration) {
      return;
    }
    _examplePhase = TutorExampleControlPhase.idle;
    notifyListeners();
  }

  Future<void> _stopHearSa() async {
    await _saSample.stop();
  }

  void _resetExampleControlPhase() {
    _exampleShuffleGeneration += 1;
    _examplePhase = TutorExampleControlPhase.idle;
  }

  void _beginStage1UserTurn() {
    _stage1AwaitingUserTurn = true;
    _stage1ExampleControls = false;
    _stage1RecoveryInstruction = false;
    // Silent clear — caller notifies once. Emitting here would re-enter
    // auto-continue listeners while the primary-action completer is still open.
    _voice.clearLastLine(notify: false);
  }

  void _endStage1UserTurn() {
    _stage1AwaitingUserTurn = false;
  }

  /// Completes the current tutor CTA wait.
  Future<void> continuePrimaryAction() async {
    final pending = _primaryActionCompleter;
    if (pending == null || pending.isCompleted) {
      return;
    }
    final action = _primaryAction;
    await _stopHearSa();
    if (_isDisposed || pending.isCompleted) {
      return;
    }
    _resetExampleControlPhase();
    // Clear the CTA before any transcript updates so auto-continue listeners
    // cannot invoke this method again for the same completer.
    _primaryAction = TutorPrimaryAction.none;
    if (action == TutorPrimaryAction.imReadyToListen) {
      // Enter listening UI immediately — never flash the previous dialogue.
      _beginStage1UserTurn();
    } else if (action == TutorPrimaryAction.letsTryAgain) {
      _stage1ExampleControls = false;
      _stage1RecoveryInstruction = false;
      if (_engine.stage1GuidedDemoPending) {
        // Guided demo runs next — stay on recovery dialogue until S74 / CTA.
        _endStage1UserTurn();
      } else {
        // Enter listening UI immediately — never flash the previous dialogue.
        _beginStage1UserTurn();
      }
    }
    if (action == TutorPrimaryAction.playTheSound) {
      // Enter the dedicated listen UI immediately — never flash S74 again.
      _endStage1UserTurn();
      _holdReferenceListenPrompt = true;
      _voice.clearLastLine(notify: false);
    }
    notifyListeners();
    if (!pending.isCompleted) {
      pending.complete();
    }
  }

  Future<void> _awaitPrimaryAction(
    int token,
    TutorPrimaryAction action, {
    bool quietTransition = false,
  }) async {
    if (!_isLive(token) || action == TutorPrimaryAction.none) {
      return;
    }
    if (!quietTransition) {
      await _voice.pause(_timing.shortTransitionPause);
      if (!_isLive(token)) {
        return;
      }
    }
    // quietTransition: skip speaking pause so completed S61 stays grey.
    final completer = Completer<void>();
    _primaryActionCompleter = completer;
    _primaryAction = action;
    notifyListeners();
    await completer.future;
    if (identical(_primaryActionCompleter, completer)) {
      _primaryActionCompleter = null;
    }
  }

  void _clearPrimaryAction({bool complete = true}) {
    final pending = _primaryActionCompleter;
    _primaryAction = TutorPrimaryAction.none;
    _primaryActionCompleter = null;
    if (complete && pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  Future<void> stop() async {
    if (_isDisposed || _stopRequested) {
      return;
    }
    _sessionToken += 1;
    _stopRequested = true;
    _listeningForSpeechAnswer = false;
    _differentSoundChoiceReady = false;
    _questionOpen = false;
    _showStage1SuccessMark = false;
    _stage1ExampleControls = false;
    _stage1RecoveryInstruction = false;
    _endStage1UserTurn();
    _holdReferenceListenPrompt = false;
    _resetExampleControlPhase();
    _clearPrimaryAction();
    _setStep(TutorStep.stopped);
    _engine.cancelActiveWork();
    _voice.cancelSpeech();
    unawaited(_stopHearSa());
    notifyListeners();
    unawaited(_speech.stop());
    final tail = _engine.stopSession();
    _stopTail = tail;
    await tail;
    if (identical(_stopTail, tail)) {
      _stopTail = null;
    }
    if (!_isDisposed && _stopRequested) {
      _setStep(TutorStep.stopped);
      notifyListeners();
    }
  }

  Future<void> tryAgain() async {
    if (_step == TutorStep.stopped || _stopRequested) {
      await _restartFromWelcome();
      return;
    }
    await _speech.stop();
    _sessionToken += 1;
    _stage1AutoRetryCount = 0;
    _lastHandledPhase = null;
    _lastHandledStage1FailureCount = 0;
    _unclearAnswerCount = 0;
    _countdownEmitted.clear();
    _showStage1SuccessMark = false;
    _stage1ExampleControls = false;
    _stage1RecoveryInstruction = false;
    _endStage1UserTurn();
    _holdReferenceListenPrompt = false;
    _resetExampleControlPhase();
    _clearPrimaryAction();
    _voice.cancelSpeech();
    _voice.resetEventKeys();
    unawaited(_stopHearSa());
    await _engine.tryAgain();
  }

  /// Starts a new welcome after Stop. Old callbacks keep the previous token.
  Future<void> _restartFromWelcome() async {
    final tail = _stopTail;
    if (tail != null) {
      await tail;
    }
    await _speech.stop();
    _sessionToken += 1;
    final token = _sessionToken;
    _stopRequested = false;
    _welcomeStarted = false;
    _stage1AutoRetryCount = 0;
    _lastHandledPhase = null;
    _lastHandledStage1FailureCount = 0;
    _unclearAnswerCount = 0;
    _countdownEmitted.clear();
    _listeningForSpeechAnswer = false;
    _differentSoundChoiceReady = false;
    _questionOpen = false;
    _showStage1SuccessMark = false;
    _stage1ExampleControls = false;
    _stage1RecoveryInstruction = false;
    _endStage1UserTurn();
    _resetExampleControlPhase();
    _clearPrimaryAction();
    _voice.cancelSpeech();
    _voice.resetEventKeys();
    unawaited(_stopHearSa());
    _setStep(TutorStep.welcome);
    notifyListeners();
    await _runWelcome(token);
  }

  bool _claimQuestion() {
    if (!_questionOpen) {
      return false;
    }
    _questionOpen = false;
    return true;
  }

  Future<void> answerLowerAudibility(bool heardClearly) async {
    if (_engine.uiPhase != AssistUiPhase.awaitingLowerAudibility ||
        !_claimQuestion()) {
      return;
    }
    _listeningForSpeechAnswer = false;
    notifyListeners();
    unawaited(_speech.stop());
    if (heardClearly) {
      await _voice.speakOnce('lower-yes-ack', TutorScripts.softAffirmation);
      await _engine.reportLowerSaAudible();
    } else {
      await _voice.speakOnce('lower-no-ack', TutorScripts.lowerNotClear);
      await _engine.reportLowerSaTooLow();
    }
  }

  Future<void> answerUpperComfort(bool comfortable) async {
    final phase = _engine.uiPhase;
    final isPa = phase == AssistUiPhase.awaitingPaComfort;
    final isUpper = phase == AssistUiPhase.awaitingUpperComfort;
    if ((!isPa && !isUpper) || !_claimQuestion()) {
      return;
    }
    _listeningForSpeechAnswer = false;
    notifyListeners();
    unawaited(_speech.stop());
    if (comfortable) {
      await _voice.speakOnce(
        isPa ? 'pa-yes-ack' : 'upper-yes-ack',
        TutorScripts.softAffirmation,
      );
      if (isPa) {
        await _engine.reportPaComfortable();
      } else {
        await _engine.reportUpperSaComfortable();
      }
    } else {
      await _voice.speakOnce(
        isPa ? 'pa-no-ack' : 'upper-no-ack',
        TutorScripts.upperNotComfortable,
      );
      if (isPa) {
        await _engine.reportPaStrained();
      } else {
        await _engine.reportUpperSaStrained();
      }
    }
  }

  Future<void> answerDifferentSound(bool tryDifferentSound) async {
    if (_engine.uiPhase != AssistUiPhase.offeringEasierSound ||
        _engine.isBusy ||
        !_claimQuestion()) {
      return;
    }
    final token = _sessionToken;
    _differentSoundChoiceReady = false;
    _listeningForSpeechAnswer = false;
    notifyListeners();
    unawaited(_speech.stop());
    if (!tryDifferentSound) {
      await _speakRecoveryDialogue(
        'different-sound-no-${_engine.currentRound}-'
        '${_engine.currentExploreCandidate?.label}',
        TutorDialogues.s73,
      );
      if (!_isLive(token) ||
          _engine.uiPhase != AssistUiPhase.offeringEasierSound) {
        return;
      }
      await _engine.declineDifferentSound();
      return;
    }
    // Yes: no spoken acknowledgement — move straight to the nearby sound.
    await _engine.acceptDifferentSound();
  }

  /// Speaks a recovery [TutorDialogue] atomically (text + audio from one id).
  Future<void> _speakRecoveryDialogue(
    String eventId,
    TutorDialogue dialogue,
  ) async {
    try {
      await _voice.speakDialogueOnce(eventId, dialogue);
    } catch (_) {}
  }

  Future<void> submitSpokenAnswer(String raw) async {
    if (_step == TutorStep.offerDifferentSound) {
      final answer = _answerParser.parseYesNo(raw);
      switch (answer) {
        case TutorYesNoAnswer.yes:
          await answerDifferentSound(true);
        case TutorYesNoAnswer.no:
          await answerDifferentSound(false);
        case TutorYesNoAnswer.unclear:
          await _handleUnclearDifferentSound();
      }
      return;
    }

    if (_step == TutorStep.askLowerAudibility) {
      final answer = _answerParser.parseYesNo(raw);
      switch (answer) {
        case TutorYesNoAnswer.yes:
          await answerLowerAudibility(true);
        case TutorYesNoAnswer.no:
          await answerLowerAudibility(false);
        case TutorYesNoAnswer.unclear:
          await _handleUnclearYesNo();
      }
      return;
    }

    if (_step == TutorStep.askMiddleComfort ||
        _step == TutorStep.askUpperComfort) {
      final answer = _answerParser.parseComfort(raw);
      switch (answer) {
        case TutorComfortAnswer.comfortable:
          await answerUpperComfort(true);
        case TutorComfortAnswer.notComfortable:
          await answerUpperComfort(false);
        case TutorComfortAnswer.unclear:
          await _handleUnclearComfort();
      }
    }
  }

  Future<void> retryStartingNote() => _engine.retryRound();

  // --- Engine hooks (single path for speech around reference / countdown) ---

  /// Speaks S74, waits for "Play the sound", then locks the listen prompt.
  ///
  /// Shared by Stage 1 guided demo and Stage 2 first Lower Sa reference.
  Future<bool> _awaitPlaySoundConsent(int token, String eventId) async {
    await _voice.speakOnce(eventId, TutorScripts.lowerSoundListenPrompt);
    if (!_isLive(token)) {
      return false;
    }
    await _awaitPrimaryAction(token, TutorPrimaryAction.playTheSound);
    if (!_isLive(token)) {
      return false;
    }
    _holdReferenceListenPrompt = true;
    await _voice.beginReferenceAudio();
    notifyListeners();
    return true;
  }

  Future<void> _onBeforeReference() async {
    final token = _sessionToken;
    if (!_isLive(token)) {
      return;
    }
    // Stage 1 guided demo: same consent + listen-screen pattern as Stage 2.
    if (!_engine.isExploringRange) {
      _endStage1UserTurn();
      _stage1ExampleControls = false;
      _stage1RecoveryInstruction = false;
      final ready = await _awaitPlaySoundConsent(
        token,
        'stage1-demo-listen-${_engine.stage1FailureCount}',
      );
      if (!ready) {
        return;
      }
      return;
    }

    _syncStepFromEngine();
    if (_engine.suppressNextRangeIntro) {
      _engine.consumeRangeIntroSuppression();
      // Recovery path keeps a short listen cue; consent CTA is Stage 1 / first
      // Lower Sa only (shared S74 flow above).
      await _voice.speakOnce(
        'ref-recovery-listen-${_engine.currentRound}-'
        '${_engine.currentExploreCandidate?.label}',
        TutorScripts.listenFirst,
      );
      if (!_isLive(token)) {
        return;
      }
      _holdReferenceListenPrompt = true;
      await _voice.beginReferenceAudio();
      notifyListeners();
      return;
    }
    final point = _engine.currentRangePoint;
    final failure = _engine.rangePointFailureCount;
    final eventBase =
        'ref-${_engine.currentExploreCandidate?.label}-${point?.name}-$failure';
    // First Lower Sa in initial search uses the longer listen prompt (S74).
    // All other first-attempt range points keep the short "Just listen." line.
    var listenPrompt = TutorScripts.listenFirst;
    var usePlaySoundConsent = false;

    if (failure == 0) {
      switch (point) {
        case AssistRangePoint.lowerSa:
          if (_engine.searchMode == AssistShrutiSearchMode.initial) {
            _setStep(TutorStep.testLower);
            await _voice.speakOnce(
              '$eventBase-intro',
              TutorScripts.lowerSoundIntro,
            );
            listenPrompt = TutorScripts.lowerSoundListenPrompt;
            usePlaySoundConsent = true;
          } else {
            _setStep(TutorStep.exploreNextShruti);
            await _voice.speakOnce(
              '$eventBase-explore',
              _exploreDirectionLine(),
            );
          }
        case AssistRangePoint.pa:
          _setStep(TutorStep.testMiddle);
          await _voice.speakOnce(
            '$eventBase-intro',
            TutorScripts.middleSoundIntro,
          );
        case AssistRangePoint.upperSa:
          _setStep(TutorStep.testUpper);
          await _voice.speakOnce(
            '$eventBase-intro',
            TutorScripts.upperSoundIntro,
          );
        case null:
          break;
      }
    } else {
      await _speakStruggleLeadIn(eventBase);
    }

    if (!_isLive(token)) {
      return;
    }
    if (usePlaySoundConsent) {
      await _awaitPlaySoundConsent(token, '$eventBase-listen-first');
      return;
    }
    if (failure == 0) {
      // Finish spoken instruction fully before the listen screen. No pauseAfter
      // — reference playback starts as soon as that screen appears.
      await _voice.speakOnce('$eventBase-listen-first', listenPrompt);
    }
    if (!_isLive(token)) {
      return;
    }
    _holdReferenceListenPrompt = true;
    await _voice.beginReferenceAudio();
    notifyListeners();
  }

  Future<void> _onAfterReference() async {
    _voice.endReferenceAudio();
    // Drop any leftover transcript (including a prior countdown "1...") so it
    // cannot resurface after the listen prompt yields to countdown / singing.
    if (_holdReferenceListenPrompt || _engine.isExploringRange) {
      _voice.clearLastLine(notify: false);
    }
    notifyListeners();
  }

  Future<void> _onBeforeCountdown() async {
    if (!_isLive(_sessionToken)) {
      return;
    }
    _countdownEpoch += 1;
    _countdownEmitted.clear();
    // Always clear before countdown so a stale "1..." cannot paint between
    // the listen screen and the first countdown line.
    _voice.clearLastLine(notify: false);
    notifyListeners();
  }

  Future<void> _onCountdownStep(int value) async {
    final token = _sessionToken;
    if (!_isLive(token) || value < 1 || value > 3) {
      return;
    }
    // Exactly one emission per countdown step value per epoch.
    if (_countdownEmitted.contains(value)) {
      return;
    }
    _countdownEmitted.add(value);
    final List<String> lines;
    if (_engine.countdownKind == AssistCountdownKind.singTogether) {
      lines = TutorScripts.assistedCountdown;
    } else if (_engine.rangePointFailureCount == 0) {
      lines = TutorScripts.countdownFirst;
    } else {
      lines = TutorScripts.countdown;
    }
    final index = 3 - value;
    if (index < 0 || index >= lines.length) {
      return;
    }
    // Keep the listen-prompt hold until this line binds so the speak-start
    // gap cannot flash a stale countdown fragment.
    await _voice.speakOnce(
      'countdown-$_countdownEpoch-$value-${_engine.countdownKind.name}',
      lines[index],
      pauseAfter: Duration.zero,
    );
    if (!_isLive(token)) {
      return;
    }
    _holdReferenceListenPrompt = false;
    notifyListeners();
  }

  Future<void> _onBeforeListen() async {
    // Stage 2 with countdown skipped (zero step duration), or Stage 1 after
    // guided-demo reference: enter singing UI without leaking prior transcript.
    if (!_engine.isExploringRange) {
      _beginStage1UserTurn();
    } else {
      _voice.clearLastLine(notify: false);
    }
    _holdReferenceListenPrompt = false;
    notifyListeners();
  }

  Future<void> _onBeforeAssistedSinging() async {
    final token = _sessionToken;
    final point = _engine.currentRangePoint?.name;
    await _voice.speakOnce(
      'assist-practice-${_engine.currentRound}-$point',
      TutorScripts.practiceTogether,
    );
    if (!_isLive(token)) {
      return;
    }
    await _voice.speakOnce(
      'assist-along-${_engine.currentRound}-$point',
      TutorScripts.singAlongWithMe,
      pauseAfter: _timing.speechToReferencePause,
    );
    notifyListeners();
  }

  Future<void> _onAssistedReferenceWillStart() async {
    final token = _sessionToken;
    if (!_isLive(token)) {
      return;
    }
    // Drop countdown "1..." before this screen paints, then own the transcript.
    _holdReferenceListenPrompt = false;
    _voice.clearLastLine(notify: false);
    notifyListeners();
    await _voice.speakOnce(
      'assist-sing-prompt-${_engine.currentRound}-'
      '${_engine.currentRangePoint?.name}',
      TutorScripts.assistedSingAlongPrompt,
      pauseAfter: Duration.zero,
    );
    if (!_isLive(token)) {
      return;
    }
    await _voice.beginReferenceAudio();
    notifyListeners();
  }

  Future<void> _onAfterAssistedSinging() async {
    final token = _sessionToken;
    _voice.endReferenceAudio();
    await _voice.pause(_timing.referenceToSpeechPause);
    if (!_isLive(token)) {
      return;
    }
    await _voice.speakOnce(
      'assist-own-${_engine.currentRound}-${_engine.currentRangePoint?.name}',
      TutorScripts.tryOnYourOwn,
      pauseAfter: _timing.shortTransitionPause,
    );
    notifyListeners();
  }

  Future<void> _onAssistedPracticeUnconfirmed() async {
    final token = _sessionToken;
    _voice.endReferenceAudio();
    if (!_isLive(token)) {
      return;
    }
    await _voice.speakOnce(
      'assist-again-${_engine.currentRound}-${_engine.currentRangePoint?.name}-'
      '${_engine.assistedAttemptCount}',
      TutorScripts.practiceOnceMore,
    );
    notifyListeners();
  }

  /// Speaks the final success line before the confirmed Shruti sample starts.
  Future<void> _onBeforeCompletionPlayback() async {
    final token = _sessionToken;
    if (!_isLive(token)) {
      return;
    }
    _setStep(TutorStep.complete);
    notifyListeners();
    await _voice.speakOnce(
      'complete-${_engine.referencePitch.label}',
      TutorScripts.completion(_engine.referencePitch.label),
    );
  }

  Future<void> _onAfterListenWindow(bool captured) async {
    if (!captured) {
      return;
    }
    final token = _sessionToken;
    if (!_engine.isExploringRange) {
      _endStage1UserTurn();
      _showStage1SuccessMark = true;
      notifyListeners();
      await _voice.speakOnce(
        'stage1-success-${_engine.currentRound}',
        TutorScripts.stage1Success,
      );
      if (!_isLive(token)) {
        return;
      }
      await _voice.speakOnce(
        'stage1-ready-next-${_engine.currentRound}',
        TutorScripts.readyForNextStep,
      );
      if (!_isLive(token)) {
        return;
      }
      await _awaitPrimaryAction(token, TutorPrimaryAction.imReadyForNextStep);
      _showStage1SuccessMark = false;
      notifyListeners();
      // Speak the Stage 2 opening here so the engine stays blocked on this
      // hook until the full clip finishes. Speaking at startingPointFound
      // races the short Stage 2 transition and cuts the line off.
      // Short pause only — Stage 2 entry no longer inserts multi-second waits
      // before the first range intro.
      await _voice.speakOnce(
        'stage2-opening-${_engine.currentRound}-0',
        TutorScripts.startingNoteSuccess.first,
        pauseAfter: _timing.shortTransitionPause,
      );
      return;
    }
    final point = _engine.currentRangePoint?.name;
    await _voice.speakOnce(
      'listen-complete-${_engine.currentRound}-$point',
      TutorScripts.listenComplete,
    );
    notifyListeners();
  }

  Future<void> _speakStruggleLeadIn(String eventBase) async {
    switch (_engine.teachingLevel) {
      case TutorTeachingLevel.standard:
        return;
      case TutorTeachingLevel.retryOnce:
        await _voice.speakOnce(
          '$eventBase-struggle',
          TutorScripts.rangeRetryOnce,
        );
      case TutorTeachingLevel.guided:
        await _voice.speakAll(
          TutorScripts.letMeHelp,
          eventIdPrefix: '$eventBase-help',
        );
      case TutorTeachingLevel.humAlong:
        await _voice.speakAll(
          TutorScripts.makeEasier,
          eventIdPrefix: '$eventBase-easy',
        );
    }
  }

  // --- Reactive handlers for decision / recovery states only ---

  void _onEngineChanged() {
    if (_isDisposed || _stopRequested) {
      return;
    }
    final phase = _engine.uiPhase;
    // Always mirror terminal engine outcomes immediately so CTA state cannot
    // lag behind a finish that answered questions on the engine directly.
    if (phase == AssistUiPhase.completed) {
      _setStep(TutorStep.complete);
    } else if (phase == AssistUiPhase.rangeUnresolved) {
      _setStep(TutorStep.unresolved);
    } else if (_step == TutorStep.complete || _step == TutorStep.unresolved) {
      // Engine Try Again / restart: clear stale narrative for the new search.
      _lastHandledPhase = null;
      _lastHandledStage1FailureCount = 0;
      _unclearAnswerCount = 0;
      _questionOpen = false;
      _differentSoundChoiceReady = false;
      _showStage1SuccessMark = false;
      _stage1ExampleControls = false;
      _stage1RecoveryInstruction = false;
      _endStage1UserTurn();
      _holdReferenceListenPrompt = false;
      _voice.resetEventKeys();
      _voice.clearLastLine(notify: false);
    }
    if (_handlingPhase) {
      _phaseDirty = true;
      notifyListeners();
      return;
    }
    unawaited(_handleEnginePhase());
  }

  Future<void> _handleEnginePhase() async {
    if (_isDisposed || _handlingPhase) {
      _phaseDirty = true;
      return;
    }
    _handlingPhase = true;
    try {
      do {
        _phaseDirty = false;
        await _processEnginePhase();
      } while (_phaseDirty && !_isDisposed);
    } finally {
      _handlingPhase = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _processEnginePhase() async {
    final token = _sessionToken;
    if (!_isLive(token)) {
      return;
    }
    final phase = _engine.uiPhase;

    // Countdown / reference / listen speech is owned by hooks — UI only.
    if (phase == AssistUiPhase.countdown ||
        phase == AssistUiPhase.playingReference ||
        phase == AssistUiPhase.preparingToListen ||
        phase == AssistUiPhase.listening ||
        phase == AssistUiPhase.assistedSinging) {
      _syncStepFromEngine();
      return;
    }

    // Speak reactive lines only once per phase entry.
    if (phase == _lastHandledPhase &&
        phase != AssistUiPhase.retry &&
        phase != AssistUiPhase.refreshingStartingNote) {
      _syncStepFromEngine();
      return;
    }
    if (phase != AssistUiPhase.retry) {
      _lastHandledPhase = phase;
    }

    switch (phase) {
      case AssistUiPhase.processing:
        // Listen-complete speech comes from afterListenWindow hook.
        break;
      case AssistUiPhase.retry:
        if (_lastHandledStage1FailureCount == _engine.stage1FailureCount) {
          break;
        }
        _lastHandledStage1FailureCount = _engine.stage1FailureCount;
        await _onStartingNoteFailure();
      case AssistUiPhase.startingPointFound:
        // Opening line already finished in afterListenWindow after "I'm ready".
        _setStep(TutorStep.startingNoteCaptured);
      case AssistUiPhase.awaitingLowerAudibility:
        _questionOpen = true;
        _setStep(TutorStep.askLowerAudibility);
        await _voice.speakOnce(
          'ask-lower-${_engine.currentRound}',
          TutorScripts.lowerAudibilityQuestion,
        );
        unawaited(_listenForYesNoAnswer());
      case AssistUiPhase.awaitingPaComfort:
        _questionOpen = true;
        _setStep(TutorStep.askMiddleComfort);
        await _voice.speakOnce(
          'ask-pa-${_engine.currentRound}',
          TutorScripts.upperComfortQuestion,
        );
        unawaited(_listenForComfortAnswer());
      case AssistUiPhase.awaitingUpperComfort:
        _questionOpen = true;
        _setStep(TutorStep.askUpperComfort);
        await _voice.speakOnce(
          'ask-upper-${_engine.currentRound}',
          TutorScripts.upperComfortQuestion,
        );
        unawaited(_listenForComfortAnswer());
      case AssistUiPhase.exploringNextShruti:
        _setStep(TutorStep.exploreNextShruti);
      case AssistUiPhase.offeringEasierSound:
        _questionOpen = true;
        _unclearAnswerCount = 0;
        _differentSoundChoiceReady = false;
        _setStep(TutorStep.offerDifferentSound);
        notifyListeners();
        await _speakRecoveryDialogue(
          'easier-${_engine.currentRound}-'
          '${_engine.currentExploreCandidate?.label}-'
          '${_engine.currentRangePoint?.name}',
          TutorDialogues.s70,
        );
        if (!_isLive(token)) {
          return;
        }
        await _speakRecoveryDialogue(
          'offer-sound-${_engine.currentRound}-'
          '${_engine.currentExploreCandidate?.label}-'
          '${_engine.currentRangePoint?.name}',
          TutorDialogues.s71,
        );
        if (!_isLive(token)) {
          return;
        }
        _differentSoundChoiceReady = true;
        notifyListeners();
        unawaited(_listenForDifferentSoundAnswer());
      case AssistUiPhase.refreshingStartingNote:
        _questionOpen = false;
        _stage1AutoRetryCount = 0;
        _lastHandledStage1FailureCount = 0;
        _setStep(TutorStep.discoverStartingNote);
        await _voice.speakOnce(
          'step-back-${_engine.currentRound}',
          TutorScripts.stepBackToVoice,
        );
        if (!_isLive(token)) {
          return;
        }
        await _engine.continueStartingNoteDiscovery();
      case AssistUiPhase.rangeBoundaryReached:
        await _engine.acknowledgeRangeBoundary();
      case AssistUiPhase.rangeUnresolved:
        _setStep(TutorStep.unresolved);
        await _voice.speakAll(
          TutorScripts.unresolved,
          eventIdPrefix: 'unresolved',
        );
      case AssistUiPhase.completed:
        // Success speech + Shruti playback sequencing is owned by
        // [AssistTutorHooks.beforeCompletionPlayback].
        _setStep(TutorStep.complete);
      case AssistUiPhase.showingTransition:
      case AssistUiPhase.intro:
      case AssistUiPhase.countdown:
      case AssistUiPhase.playingReference:
      case AssistUiPhase.preparingToListen:
      case AssistUiPhase.listening:
      case AssistUiPhase.assistedSinging:
      case AssistUiPhase.verifying:
      case AssistUiPhase.awaitingComfort:
        break;
    }

    if (_isLive(token)) {
      _syncStepFromEngine();
    }
  }

  Future<void> _onStartingNoteFailure() async {
    final token = _sessionToken;
    _endStage1UserTurn();
    _setStep(TutorStep.startingNoteFailure);
    final level = _engine.teachingLevel;
    final failure = _engine.stage1FailureCount;
    switch (level) {
      case TutorTeachingLevel.standard:
      case TutorTeachingLevel.retryOnce:
      case TutorTeachingLevel.guided:
        // S70 → S61. Each id supplies transcript text and audio clip.
        // Must not speak S60 / S71 / S62 on this path.
        await _voice.speakDialogues(
          TutorDialogues.stage1FailureRecovery,
          eventIdPrefix: 'stage1-guided-$failure',
        );
        if (_isLive(token)) {
          // S61 finished: keep the same transcript; style → grey + show controls
          // when the primary action is revealed (one notify, no text swap).
          _stage1RecoveryInstruction = true;
          _stage1ExampleControls = true;
        }
      case TutorTeachingLevel.humAlong:
        // Later Stage 1 struggle: hear-first path (not the S70→S61 sequence).
        await _voice.speakDialogues(<TutorDialogue>[
          TutorDialogues.s17,
          TutorDialogues.s18,
        ], eventIdPrefix: 'stage1-easy-$failure');
        if (_isLive(token)) {
          _stage1ExampleControls = true;
        }
    }

    if (!_isLive(token)) {
      return;
    }
    // Wait for an explicit retry tap. Do not auto-play reference / sample audio.
    await _awaitPrimaryAction(
      token,
      TutorPrimaryAction.letsTryAgain,
      quietTransition: _stage1RecoveryInstruction,
    );
    if (!_isLive(token)) {
      return;
    }
    _stage1AutoRetryCount += 1;
    await _engine.retryRound();
  }

  Future<void> _listenForYesNoAnswer() async {
    final token = _sessionToken;
    if (!_isLive(token) || _step != TutorStep.askLowerAudibility) {
      return;
    }
    final available = await _speech.isAvailable;
    if (!available || _isDisposed) {
      return;
    }

    _listeningForSpeechAnswer = true;
    notifyListeners();
    try {
      await _engine.prepareForSpokenAnswer();
      final transcript = await _speech.listen(
        timeout: _timing.speechResponseListenDuration,
        onPartial: (partial) {
          if (_answerParser.parseYesNo(partial) != TutorYesNoAnswer.unclear) {
            unawaited(_speech.stop());
          }
        },
      );
      if (!_isLive(token) ||
          _engine.uiPhase != AssistUiPhase.awaitingLowerAudibility) {
        return;
      }
      if (transcript == null || transcript.isEmpty) {
        return;
      }
      await submitSpokenAnswer(transcript);
    } finally {
      await _engine.restoreAfterSpokenAnswer();
      _listeningForSpeechAnswer = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _listenForComfortAnswer() async {
    final token = _sessionToken;
    if (!_isLive(token) ||
        (_step != TutorStep.askMiddleComfort &&
            _step != TutorStep.askUpperComfort)) {
      return;
    }
    final available = await _speech.isAvailable;
    if (!available || _isDisposed) {
      return;
    }

    _listeningForSpeechAnswer = true;
    notifyListeners();
    try {
      await _engine.prepareForSpokenAnswer();
      final transcript = await _speech.listen(
        timeout: _timing.speechResponseListenDuration,
        onPartial: (partial) {
          if (_answerParser.parseComfort(partial) !=
              TutorComfortAnswer.unclear) {
            unawaited(_speech.stop());
          }
        },
      );
      if (!_isLive(token) ||
          (_engine.uiPhase != AssistUiPhase.awaitingPaComfort &&
              _engine.uiPhase != AssistUiPhase.awaitingUpperComfort)) {
        return;
      }
      if (transcript == null || transcript.isEmpty) {
        return;
      }
      await submitSpokenAnswer(transcript);
    } finally {
      await _engine.restoreAfterSpokenAnswer();
      _listeningForSpeechAnswer = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _listenForDifferentSoundAnswer() async {
    final token = _sessionToken;
    if (!_isLive(token) || _step != TutorStep.offerDifferentSound) {
      return;
    }
    final available = await _speech.isAvailable;
    if (!available || _isDisposed) {
      return;
    }

    _listeningForSpeechAnswer = true;
    notifyListeners();
    try {
      await _engine.prepareForSpokenAnswer();
      final transcript = await _speech.listen(
        timeout: _timing.speechResponseListenDuration,
        onPartial: (partial) {
          if (_answerParser.parseYesNo(partial) != TutorYesNoAnswer.unclear) {
            unawaited(_speech.stop());
          }
        },
      );
      if (!_isLive(token) ||
          _engine.uiPhase != AssistUiPhase.offeringEasierSound) {
        return;
      }
      if (transcript == null || transcript.isEmpty) {
        return;
      }
      await submitSpokenAnswer(transcript);
    } finally {
      await _engine.restoreAfterSpokenAnswer();
      _listeningForSpeechAnswer = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _handleUnclearDifferentSound() async {
    _unclearAnswerCount += 1;
    await _voice.speakAll(
      TutorScripts.unclearYesNo,
      eventIdPrefix: 'unclear-different-$_unclearAnswerCount',
    );
    if (_unclearAnswerCount <= 1 &&
        _engine.uiPhase == AssistUiPhase.offeringEasierSound) {
      unawaited(_listenForDifferentSoundAnswer());
    }
  }

  Future<void> _handleUnclearYesNo() async {
    _unclearAnswerCount += 1;
    await _voice.speakAll(
      TutorScripts.unclearYesNo,
      eventIdPrefix: 'unclear-yesno-$_unclearAnswerCount',
    );
    // One automatic re-listen after unclear speech; then buttons remain.
    if (_unclearAnswerCount <= 1 &&
        _engine.uiPhase == AssistUiPhase.awaitingLowerAudibility) {
      unawaited(_listenForYesNoAnswer());
    }
  }

  Future<void> _handleUnclearComfort() async {
    _unclearAnswerCount += 1;
    await _voice.speakAll(
      TutorScripts.unclearComfort,
      eventIdPrefix: 'unclear-comfort-$_unclearAnswerCount',
    );
    if (_unclearAnswerCount <= 1 &&
        (_engine.uiPhase == AssistUiPhase.awaitingPaComfort ||
            _engine.uiPhase == AssistUiPhase.awaitingUpperComfort)) {
      unawaited(_listenForComfortAnswer());
    }
  }

  void _syncStepFromEngine() {
    if (_stopRequested || _step == TutorStep.stopped) {
      return;
    }
    final phase = _engine.uiPhase;
    if (phase == AssistUiPhase.intro && !_welcomeStarted) {
      _setStep(TutorStep.welcome);
      return;
    }
    // Terminal Stage 2 outcomes stay visible even if the explore flag cleared.
    if (phase == AssistUiPhase.completed) {
      _setStep(TutorStep.complete);
      return;
    }
    if (phase == AssistUiPhase.rangeUnresolved) {
      _setStep(TutorStep.unresolved);
      return;
    }
    if (!_engine.isExploringRange) {
      if (phase == AssistUiPhase.refreshingStartingNote) {
        _setStep(TutorStep.discoverStartingNote);
      } else if (phase == AssistUiPhase.retry) {
        _setStep(TutorStep.startingNoteFailure);
      } else if (phase == AssistUiPhase.startingPointFound) {
        _setStep(TutorStep.startingNoteCaptured);
      } else if (phase == AssistUiPhase.listening ||
          phase == AssistUiPhase.countdown ||
          phase == AssistUiPhase.playingReference ||
          phase == AssistUiPhase.preparingToListen ||
          phase == AssistUiPhase.processing) {
        if (_engine.stage1FailureCount > 0 &&
            phase == AssistUiPhase.playingReference) {
          _setStep(TutorStep.startingNoteFailure);
        } else if (_engine.stage1Shruti != null &&
            phase == AssistUiPhase.processing) {
          _setStep(TutorStep.startingNoteCaptured);
        } else {
          _setStep(TutorStep.discoverStartingNote);
        }
      }
      return;
    }

    switch (phase) {
      case AssistUiPhase.awaitingLowerAudibility:
        _setStep(TutorStep.askLowerAudibility);
        // Open CTAs when attaching to an unanswered question (e.g. tests).
        // Do not reopen after [_claimQuestion] while the phase is unchanged.
        if (_lastHandledPhase != AssistUiPhase.awaitingLowerAudibility) {
          _questionOpen = true;
        }
      case AssistUiPhase.awaitingPaComfort:
        _setStep(TutorStep.askMiddleComfort);
        if (_lastHandledPhase != AssistUiPhase.awaitingPaComfort) {
          _questionOpen = true;
        }
      case AssistUiPhase.awaitingUpperComfort:
        _setStep(TutorStep.askUpperComfort);
        if (_lastHandledPhase != AssistUiPhase.awaitingUpperComfort) {
          _questionOpen = true;
        }
      case AssistUiPhase.exploringNextShruti:
        _setStep(TutorStep.exploreNextShruti);
      case AssistUiPhase.offeringEasierSound:
        _setStep(TutorStep.offerDifferentSound);
      case AssistUiPhase.refreshingStartingNote:
        _setStep(TutorStep.discoverStartingNote);
      case AssistUiPhase.completed:
        _setStep(TutorStep.complete);
      case AssistUiPhase.rangeUnresolved:
        _setStep(TutorStep.unresolved);
      case AssistUiPhase.startingPointFound:
        _setStep(TutorStep.startingNoteCaptured);
      default:
        final point = _engine.currentRangePoint;
        if (point == AssistRangePoint.lowerSa) {
          _setStep(
            _engine.searchMode == AssistShrutiSearchMode.initial
                ? TutorStep.testLower
                : TutorStep.exploreNextShruti,
          );
        } else if (point == AssistRangePoint.pa) {
          _setStep(TutorStep.testMiddle);
        } else if (point == AssistRangePoint.upperSa) {
          _setStep(TutorStep.testUpper);
        }
    }
  }

  String _rangeActionHeadline() {
    final phase = _engine.uiPhase;
    switch (phase) {
      case AssistUiPhase.playingReference:
        return TutorScripts.referenceListenPrompt;
      case AssistUiPhase.assistedSinging:
        return TutorScripts.assistedSingAlongPrompt;
      case AssistUiPhase.countdown:
        return 'Your turn';
      case AssistUiPhase.listening:
        return 'Your turn';
      case AssistUiPhase.preparingToListen:
        return 'Your turn';
      case AssistUiPhase.processing:
        return 'Nice';
      default:
        return 'Follow my voice';
    }
  }

  String? _rangeSupportText() {
    switch (_engine.teachingLevel) {
      case TutorTeachingLevel.humAlong:
        return 'Listen once more, then try that sound.';
      case TutorTeachingLevel.guided:
      case TutorTeachingLevel.retryOnce:
        return 'Listen once more, then try that sound.';
      case TutorTeachingLevel.standard:
        return null;
    }
  }

  String _exploreDirectionLine() {
    switch (_engine.searchMode) {
      case AssistShrutiSearchMode.seekingLower:
        return TutorScripts.exploreLower;
      case AssistShrutiSearchMode.climbing:
      case AssistShrutiSearchMode.seekingHigher:
      case AssistShrutiSearchMode.initial:
        return TutorScripts.exploreHigher;
    }
  }

  void _setStep(TutorStep step) {
    if (_step == step) {
      return;
    }
    _step = step;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _voice.onChanged = null;
    _saSample.onChanged = null;
    _engine.tutorHooks = null;
    _engine.removeListener(_onEngineChanged);
    unawaited(_speech.dispose());
    unawaited(_voice.dispose());
    unawaited(_saSample.dispose());
    super.dispose();
  }
}
