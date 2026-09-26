import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/tutor/assist_tutor_hooks.dart';
import 'package:harmony/tutor/tutor_answer.dart';
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
    this.maxStage1AutoRetries = 5,
  }) : _engine = engine,
       _answerParser = answerParser,
       _speech = speechRecognizer ?? SilentTutorSpeechRecognizer(),
       _voice = TutorVoiceCoordinator(voice: voice, timing: timing, wait: wait),
       _timing = timing {
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
    );
    _engine.addListener(_onEngineChanged);
    _syncStepFromEngine();
  }

  final AssistModeController _engine;
  final TutorVoiceCoordinator _voice;
  final TutorSpeechRecognizer _speech;
  final TutorAnswerParser _answerParser;
  final TutorTimingConfig _timing;

  /// After this many auto Stage 1 retries, wait for an explicit Try again tap.
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

  /// Bumped on Stop and on each fresh start so late callbacks cannot continue.
  int _sessionToken = 0;
  Future<void>? _stopTail;

  AssistModeController get engine => _engine;

  TutorStep get step => _step;

  bool get isSpeaking => _voice.isSpeaking;

  /// True while waiting for a spoken Yes/No or comfort answer.
  bool get isListeningForSpeechAnswer => _listeningForSpeechAnswer;

  String? get lastVoiceLine => _voice.lastLine;

  List<String> get spokenLog => _voice.spokenLog;

  /// Countdown values spoken in the current countdown run (tests).
  List<int> get countdownEmitted => List<int>.unmodifiable(_countdownEmitted);

  int? get countdownValue => _engine.countdownValue;

  TutorTeachingLevel get teachingLevel => _engine.teachingLevel;

  double get progress {
    switch (_step) {
      case TutorStep.welcome:
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
        return 0.6;
      case TutorStep.testUpper:
      case TutorStep.askUpperComfort:
        return 0.75;
      case TutorStep.exploreNextShruti:
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

  /// Primary on-screen action cue. During countdown, only the countdown
  /// display shows the digit — headline stays a calm label.
  String get headline {
    switch (_step) {
      case TutorStep.welcome:
        return 'Find your comfortable Shruti';
      case TutorStep.discoverStartingNote:
        if (_engine.uiPhase == AssistUiPhase.countdown) {
          return 'Your turn';
        }
        if (_engine.uiPhase == AssistUiPhase.listening) {
          return 'Your turn';
        }
        if (_engine.uiPhase == AssistUiPhase.playingReference) {
          return 'Listen';
        }
        return 'Sing one comfortable sound';
      case TutorStep.startingNoteFailure:
        return "Let's try once more";
      case TutorStep.startingNoteCaptured:
        return 'Lovely — I heard that';
      case TutorStep.testLower:
      case TutorStep.testMiddle:
      case TutorStep.testUpper:
      case TutorStep.exploreNextShruti:
        return _rangeActionHeadline();
      case TutorStep.askLowerAudibility:
        return 'Could you hear that sound clearly?';
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
    switch (_step) {
      case TutorStep.welcome:
        return "I'll guide you. You just sing.";
      case TutorStep.discoverStartingNote:
        if (_engine.uiPhase == AssistUiPhase.listening) {
          return 'Keep the same sound going.';
        }
        if (_engine.uiPhase == AssistUiPhase.countdown) {
          return null;
        }
        return null;
      case TutorStep.startingNoteCaptured:
        return "Now I'll find a comfortable range for you.";
      case TutorStep.askLowerAudibility:
        return _listeningForSpeechAnswer
            ? 'Say yes or no — or tap below.'
            : 'Say yes or no — or tap below.';
      case TutorStep.askUpperComfort:
        return 'Say comfortable or not comfortable — or tap below.';
      case TutorStep.complete:
        return 'Your comfortable Shruti';
      case TutorStep.unresolved:
        return 'Whenever you are ready.';
      case TutorStep.stopped:
        return TutorScripts.sessionStoppedSupport;
      case TutorStep.startingNoteFailure:
      case TutorStep.testLower:
      case TutorStep.testMiddle:
      case TutorStep.testUpper:
      case TutorStep.exploreNextShruti:
        return _rangeSupportText();
    }
  }

  bool get showCountdown =>
      _engine.uiPhase == AssistUiPhase.countdown &&
      _engine.countdownValue != null;

  bool get showListenProgress =>
      _engine.uiPhase == AssistUiPhase.listening && !_engine.isExploringRange;

  bool get showYesNoFallback => _step == TutorStep.askLowerAudibility;

  bool get showComfortFallback => _step == TutorStep.askUpperComfort;

  bool get showPlayMyShruti => _step == TutorStep.complete;

  bool get showTryAgain =>
      _step == TutorStep.unresolved ||
      (_step == TutorStep.startingNoteFailure &&
          _stage1AutoRetryCount >= maxStage1AutoRetries);

  /// Explicit end state after the user taps Stop.
  bool get showSessionStopped => _step == TutorStep.stopped;

  bool get showStop {
    if (_step == TutorStep.complete || _step == TutorStep.stopped) {
      return false;
    }
    if (_stopRequested && _engine.uiPhase == AssistUiPhase.intro) {
      return false;
    }
    if (_step == TutorStep.welcome &&
        !_welcomeStarted &&
        !_engine.isSessionActive) {
      return false;
    }
    return true;
  }

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
    _setStep(TutorStep.discoverStartingNote);
    await _voice.speakAll(
      TutorScripts.discoverIntro,
      eventIdPrefix: 'discover',
    );
    if (!_isLive(token) || _engine.isSessionActive) {
      return;
    }
    await _engine.startSession();
  }

  Future<void> stop() async {
    if (_isDisposed || _stopRequested) {
      return;
    }
    _sessionToken += 1;
    _stopRequested = true;
    _listeningForSpeechAnswer = false;
    _setStep(TutorStep.stopped);
    _engine.cancelActiveWork();
    _voice.cancelSpeech();
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
    _voice.cancelSpeech();
    _voice.resetEventKeys();
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
    _voice.cancelSpeech();
    _voice.resetEventKeys();
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
    if (_engine.uiPhase != AssistUiPhase.awaitingUpperComfort ||
        !_claimQuestion()) {
      return;
    }
    _listeningForSpeechAnswer = false;
    notifyListeners();
    unawaited(_speech.stop());
    if (comfortable) {
      await _voice.speakOnce('upper-yes-ack', TutorScripts.softAffirmation);
      await _engine.reportUpperSaComfortable();
    } else {
      await _voice.speakOnce('upper-no-ack', TutorScripts.upperNotComfortable);
      await _engine.reportUpperSaStrained();
    }
  }

  Future<void> submitSpokenAnswer(String raw) async {
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

    if (_step == TutorStep.askUpperComfort) {
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

  Future<void> _onBeforeReference() async {
    final token = _sessionToken;
    if (!_isLive(token)) {
      return;
    }
    // Speak while reference is inactive, then lock before the engine plays.
    if (!_engine.isExploringRange) {
      await _voice.speakOnce(
        'stage1-demo-listen-${_engine.stage1FailureCount}',
        TutorScripts.listenFirst,
        pauseAfter: _timing.speechToReferencePause,
      );
      if (!_isLive(token)) {
        return;
      }
      await _voice.beginReferenceAudio();
      notifyListeners();
      return;
    }

    _syncStepFromEngine();
    final point = _engine.currentRangePoint;
    final failure = _engine.rangePointFailureCount;
    final eventBase =
        'ref-${_engine.currentExploreCandidate?.label}-${point?.name}-$failure';

    if (failure == 0) {
      switch (point) {
        case AssistRangePoint.lowerSa:
          if (_engine.searchMode == AssistShrutiSearchMode.initial) {
            _setStep(TutorStep.testLower);
            await _voice.speakOnce(
              '$eventBase-intro',
              TutorScripts.lowerSoundIntro,
            );
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
      await _voice.pause(_timing.speechToReferencePause);
    }

    if (failure == 0) {
      await _voice.speakOnce(
        '$eventBase-listen-first',
        TutorScripts.listenFirst,
        pauseAfter: _timing.speechToReferencePause,
      );
    }
    if (!_isLive(token)) {
      return;
    }
    await _voice.beginReferenceAudio();
    notifyListeners();
  }

  Future<void> _onAfterReference() async {
    final token = _sessionToken;
    _voice.endReferenceAudio();
    await _voice.pause(_timing.referenceToSpeechPause);
    if (!_isLive(token)) {
      return;
    }
    // The reference has stopped. The user will sing alone after the countdown.
    await _voice.speakOnce(
      'now-try-${_engine.currentRound}-'
      '${_engine.currentRangePoint?.name}-'
      '${_engine.stage1FailureCount}-'
      '${_engine.rangePointFailureCount}',
      TutorScripts.nowTryThatSound,
      pauseAfter: _timing.shortTransitionPause,
    );
    notifyListeners();
  }

  Future<void> _onBeforeCountdown() async {
    if (!_isLive(_sessionToken)) {
      return;
    }
    _countdownEpoch += 1;
    _countdownEmitted.clear();
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
    final lines = _engine.countdownKind == AssistCountdownKind.singTogether
        ? TutorScripts.assistedCountdown
        : TutorScripts.countdown;
    final index = 3 - value;
    if (index < 0 || index >= lines.length) {
      return;
    }
    await _voice.speakOnce(
      'countdown-$_countdownEpoch-$value-${_engine.countdownKind.name}',
      lines[index],
      pauseAfter: Duration.zero,
    );
    if (!_isLive(token)) {
      return;
    }
    notifyListeners();
  }

  Future<void> _onBeforeListen() async {
    // The countdown already started the user's turn. Do not add another line.
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
    if (!_isLive(_sessionToken)) {
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
      'assist-ready-${_engine.currentRound}-${_engine.currentRangePoint?.name}',
      TutorScripts.assistedReady,
      pauseAfter: _timing.sentencePause,
    );
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
    if (_engine.assistedAttemptCount >=
        AssistModeController.maxAssistedAttemptsPerPoint) {
      return;
    }
    await _voice.speakOnce(
      'assist-again-${_engine.currentRound}-${_engine.currentRangePoint?.name}-'
      '${_engine.assistedAttemptCount}',
      TutorScripts.practiceOnceMore,
    );
    notifyListeners();
  }

  Future<void> _onAfterListenWindow(bool captured) async {
    if (!captured) {
      return;
    }
    final point = _engine.isExploringRange
        ? _engine.currentRangePoint?.name
        : 'stage1';
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
    if (phase == _lastHandledPhase && phase != AssistUiPhase.retry) {
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
        _setStep(TutorStep.startingNoteCaptured);
        await _voice.speakAll(
          TutorScripts.startingNoteSuccess,
          eventIdPrefix: 'stage1-success',
        );
      case AssistUiPhase.awaitingLowerAudibility:
        _questionOpen = true;
        _setStep(TutorStep.askLowerAudibility);
        await _voice.speakOnce(
          'ask-lower-${_engine.currentRound}',
          TutorScripts.lowerAudibilityQuestion,
        );
        unawaited(_listenForYesNoAnswer());
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
      case AssistUiPhase.rangeBoundaryReached:
        await _engine.acknowledgeRangeBoundary();
      case AssistUiPhase.rangeUnresolved:
        _setStep(TutorStep.unresolved);
        await _voice.speakAll(
          TutorScripts.unresolved,
          eventIdPrefix: 'unresolved',
        );
      case AssistUiPhase.completed:
        _setStep(TutorStep.complete);
        await _voice.speakOnce(
          'complete-${_engine.referencePitch.label}',
          TutorScripts.completion(_engine.referencePitch.label),
        );
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
    _setStep(TutorStep.startingNoteFailure);
    final level = _engine.teachingLevel;
    final failure = _engine.stage1FailureCount;
    switch (level) {
      case TutorTeachingLevel.standard:
      case TutorTeachingLevel.retryOnce:
        await _voice.speakAll(
          TutorScripts.startingNoteRetryOnce,
          eventIdPrefix: 'stage1-retry-$failure',
        );
      case TutorTeachingLevel.guided:
        await _voice.speakAll(
          TutorScripts.startingNoteGuided,
          eventIdPrefix: 'stage1-guided-$failure',
        );
      case TutorTeachingLevel.humAlong:
        await _voice.speakAll(
          TutorScripts.makeEasier,
          eventIdPrefix: 'stage1-easy-$failure',
        );
    }

    if (_stage1AutoRetryCount >= maxStage1AutoRetries) {
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
    if (!_isLive(token) || _step != TutorStep.askUpperComfort) {
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
          _engine.uiPhase != AssistUiPhase.awaitingUpperComfort) {
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
        _engine.uiPhase == AssistUiPhase.awaitingUpperComfort) {
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
    if (!_engine.isExploringRange) {
      if (phase == AssistUiPhase.retry) {
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
      case AssistUiPhase.awaitingUpperComfort:
        _setStep(TutorStep.askUpperComfort);
      case AssistUiPhase.exploringNextShruti:
        _setStep(TutorStep.exploreNextShruti);
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
        return 'Listen';
      case AssistUiPhase.assistedSinging:
        return 'Practice together';
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
    _engine.tutorHooks = null;
    _engine.removeListener(_onEngineChanged);
    unawaited(_speech.dispose());
    unawaited(_voice.dispose());
    super.dispose();
  }
}
