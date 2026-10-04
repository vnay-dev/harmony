import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/audio/audio_session_config.dart';
import 'package:harmony/audio/reference_sound_generator.dart';
import 'package:harmony/audio/synthesized_reference_sound_generator.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/assist_range_targets.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/nearest_supported_shruti.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/reference_pitch_adjuster.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/supported_shruti_steps.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_candidate_range_result.dart';
import 'package:harmony/state/assist_mode_phase.dart';
import 'package:harmony/tutor/assist_tutor_hooks.dart';
import 'package:harmony/tutor/tutor_step.dart';

export 'package:harmony/pitch/assist_range_targets.dart';
export 'package:harmony/state/assist_candidate_range_result.dart';
export 'package:harmony/state/assist_mode_phase.dart';
export 'package:harmony/tutor/tutor_step.dart';

/// Orchestrates Assist Mode as Stage 1 (capture a comfortable starting note)
/// then Stage 2 (guided Lower Sa → Pa → Upper Sa range check).
///
/// Stage 1 listens to the user's voice only — no Tanpura or reference playback.
/// A stable voice candidate is mapped to the nearest supported Shruti and used
/// only as the Stage 2 starting point (not a final Shruti).
///
/// Stage 2 range references use [ReferenceSoundGenerator]. Pitch analysis runs
/// only in [AssistUiPhase.listening], never overlapping reference playback.
class AssistModeController extends ChangeNotifier {
  AssistModeController({
    required PitchDetectionService detectionService,
    required AudioService audioService,
    StablePitchCandidateFinder? candidateFinder,
    ReferencePitchAdjuster? pitchAdjuster,
    TargetPitchMatcher? targetMatcher,
    ReferenceSoundGenerator? referenceSoundGenerator,
    this.timing = const AssistTimingConfig(),
    this.initialReferencePitch = Pitch.defaultPitch,
    Future<void> Function(Duration duration)? wait,
    Future<void> Function()? prepareAudioSession,
    this.tutorHooks,
  }) : _detectionService = detectionService,
       _audioService = audioService,
       _candidateFinder = candidateFinder ?? StablePitchCandidateFinder(),
       _pitchAdjuster = pitchAdjuster ?? ReferencePitchAdjuster(),
       _targetMatcher = targetMatcher ?? TargetPitchMatcher(),
       _referenceSoundGenerator =
           referenceSoundGenerator ?? SynthesizedReferenceSoundGenerator(),
       _ownsReferenceSoundGenerator = referenceSoundGenerator == null,
       _wait = wait,
       _prepareAudioSession =
           prepareAudioSession ?? ensurePlayAndRecordAudioSession;

  /// Durations for play / settle / listen / transition.
  final AssistTimingConfig timing;

  /// Fallback pitch before Stage 1 captures a starting note (also used after reset).
  final Pitch initialReferencePitch;

  /// Presentation gates for the tutor layer (speech before/after reference).
  AssistTutorHooks? tutorHooks;

  final PitchDetectionService _detectionService;
  final AudioService _audioService;
  final StablePitchCandidateFinder _candidateFinder;
  final ReferencePitchAdjuster _pitchAdjuster;
  final TargetPitchMatcher _targetMatcher;
  final ReferenceSoundGenerator _referenceSoundGenerator;
  final bool _ownsReferenceSoundGenerator;
  final Future<void> Function(Duration duration)? _wait;
  final Future<void> Function() _prepareAudioSession;

  StreamSubscription<PitchReading>? _readingsSubscription;
  Timer? _windowTimer;
  Timer? _progressTimer;
  Completer<void>? _windowCompleter;
  int _sessionGeneration = 0;
  bool _isBusy = false;
  bool _isSessionActive = false;
  bool _pitchAnalysisEnabled = false;
  bool _isDisposed = false;
  String? _errorMessage;

  AssistUiPhase _uiPhase = AssistUiPhase.intro;
  AssistStage _stage = AssistStage.findingStart;
  int _currentRound = 0;
  Pitch _referencePitch = Pitch.defaultPitch;
  double _listenProgress = 0;

  /// Stage 1 starting Shruti locked when a stable voice candidate is accepted.
  Pitch? _stage1Shruti;

  /// Candidate Shruti currently under Stage 2 range test.
  Pitch? _currentCandidate;

  /// Lower Sa / Pa / Upper Sa frequencies for [_currentCandidate].
  AssistRangeTargets? _rangeTargets;

  /// Current discrete range-test target.
  AssistRangePoint? _currentRangePoint;

  /// True after a Stage 2 listen latched a TargetPitchMatcher match.
  bool _rangeMatchAccepted = false;

  /// Latest voiced Hz while listening in Stage 2 (for the range guide).
  double? _rangeVoiceHz;
  double _voiceActivity = 0;

  /// Results for each candidate tested in this Stage 2 session.
  final List<AssistCandidateRangeResult> _testedCandidates =
      <AssistCandidateRangeResult>[];

  /// Mutable result for the candidate currently under test.
  AssistCandidateRangeResult? _activeCandidateResult;

  /// Last candidate the user marked Upper Sa as comfortable.
  Pitch? _lastComfortableShruti;

  /// Candidate where Upper Sa felt strained (upper boundary), if any.
  Pitch? _currentBoundaryShruti;

  /// Stage 2 search posture (climb / seek higher / seek lower).
  AssistShrutiSearchMode _searchMode = AssistShrutiSearchMode.initial;

  /// True after the user confirmed Lower Sa is audible on some candidate.
  ///
  /// While climbing, later candidates skip the Lower Sa question because the
  /// lower side already moved up with the previous comfortable Shruti.
  bool _lowerSideAccessible = false;

  /// Latched successful capture for the current Stage 1 listen window.
  StablePitchCandidate? _acceptedListenCandidate;
  bool _listenCaptureResolved = false;

  /// How many Stage 1 capture attempts have failed in this session.
  int _stage1FailureCount = 0;

  /// How many times the current Stage 2 range point failed to match.
  int _rangePointFailureCount = 0;
  int _assistedAttempts = 0;

  /// True after the user agreed to leave one stuck sound in this episode.
  ///
  /// Cleared when that new sound is matched, or when Stage 1 listens again.
  bool _movedForRecovery = false;

  /// True after the user chose to stay with the current sound.
  bool _soundChangeDeclined = false;

  /// One assisted pass requested by [declineDifferentSound].
  bool _forceAssistedPass = false;

  /// Skip the next directional range intro. The solo reference still plays.
  bool _suppressNextRangeIntro = false;
  AssistRecoveryMode _recoveryMode = AssistRecoveryMode.normal;
  AssistCountdownKind _countdownKind = AssistCountdownKind.soloRetry;

  /// Current spoken countdown digit: 3, 2, or 1. Null when idle.
  int? _countdownValue;

  /// Whether the next Stage 1 retry should play a guided demo first.
  bool _stage1GuidedDemoPending = false;

  bool get isBusy => _isBusy;
  bool get isSessionActive => _isSessionActive;
  String? get errorMessage => _errorMessage;

  /// Current UI phase.
  AssistUiPhase get uiPhase => _uiPhase;

  /// Whether Stage 2 range exploration is active.
  AssistStage get stage => _stage;

  bool get isExploringRange => _stage == AssistStage.exploringRange;

  /// Current discrete range point, if Stage 2 is active.
  AssistRangePoint? get currentRangePoint => _currentRangePoint;

  /// Target frequencies for the current Stage 2 candidate.
  AssistRangeTargets? get rangeTargets => _rangeTargets;

  /// Active match target in Hz during Stage 2, if any.
  double? get currentRangeTargetHz {
    final targets = _rangeTargets;
    final point = _currentRangePoint;
    if (targets == null || point == null) {
      return null;
    }
    return targets.frequencyHzFor(point);
  }

  /// Pitch class of the Tanpura sample for the current range point.
  Pitch? get currentRangePlaybackPitch {
    final targets = _rangeTargets;
    final point = _currentRangePoint;
    if (targets == null || point == null) {
      return null;
    }
    return targets.playbackPitchFor(point);
  }

  /// Guide position (0–1) of the fixed current target.
  double? get rangeTargetGuidePosition {
    final targets = _rangeTargets;
    final point = _currentRangePoint;
    if (targets == null || point == null) {
      return null;
    }
    return targets.guidePositionFor(point);
  }

  /// Guide position (0–1) of the latest voiced pitch, if available.
  double? get rangeVoiceGuidePosition {
    final targets = _rangeTargets;
    final hz = _rangeVoiceHz;
    if (targets == null || hz == null) {
      return null;
    }
    return targets.guidePositionForHz(hz);
  }

  /// True when Stage 2 has latched a successful match for the current point.
  bool get didMatchCurrentRangeTarget => _rangeMatchAccepted;

  /// Signed cents from the active Stage 2 target while listening.
  ///
  /// Positive means sharp of the target. `null` when not in a Stage 2 listen,
  /// or when no stable pitch has been evaluated yet. Backed by
  /// [TargetPitchMatcher.centsFromTarget] — not a second pitch calculation.
  double? get liveCentsFromTarget {
    if (_uiPhase != AssistUiPhase.listening ||
        _stage != AssistStage.exploringRange) {
      return null;
    }
    return _targetMatcher.centsFromTarget;
  }

  /// Microphone energy while listening, from 0 (silence) to 1 (loud).
  ///
  /// Comes from the same pitch-detection audio window. Zero outside listening.
  double get voiceActivity => _voiceActivity;

  /// 1-based round number while a session is active.
  int get currentRound => _currentRound;

  /// Progress through the listening window, from `0` to `1`.
  double get listenProgress => _listenProgress;

  /// Current reference / candidate Sa pitch class.
  Pitch get referencePitch => _referencePitch;

  /// Current reference frequency from the adjuster, if started.
  double? get referenceFrequencyHz => _pitchAdjuster.referenceFrequencyHz;

  /// Stage 1 confirmed starting Shruti, if Stage 2 has begun.
  Pitch? get stage1Shruti => _stage1Shruti;

  /// Candidate Shruti under test in Stage 2.
  Pitch? get currentExploreCandidate => _currentCandidate;

  /// Immutable view of per-candidate Stage 2 observations.
  List<AssistCandidateRangeResult> get testedCandidates =>
      List<AssistCandidateRangeResult>.unmodifiable(_testedCandidates);

  /// Active candidate result, if a range test is in progress.
  AssistCandidateRangeResult? get activeCandidateResult =>
      _activeCandidateResult;

  /// Last candidate marked comfortable at Upper Sa, if any.
  Pitch? get lastComfortableShruti => _lastComfortableShruti;

  /// Candidate where Upper Sa felt strained (detected upper boundary).
  Pitch? get currentBoundaryShruti => _currentBoundaryShruti;

  /// Current Stage 2 search posture (for tests / diagnostics).
  AssistShrutiSearchMode get searchMode => _searchMode;

  /// Legacy Stage 1 verify flag — always false after voice-only discovery.
  bool get isVerifying => false;

  /// True only while pitch readings are accepted for analysis.
  bool get isPitchAnalysisEnabled => _pitchAnalysisEnabled;

  /// True while the mic is capturing and analysis is enabled.
  bool get isListeningForVoice =>
      _pitchAnalysisEnabled &&
      _detectionService.isListening &&
      _uiPhase == AssistUiPhase.listening;

  bool get isReferencePlaying =>
      _audioService.isPlaying || _referenceSoundGenerator.isPlaying;

  /// Stage 1 failures so far (drives escalating tutor help).
  int get stage1FailureCount => _stage1FailureCount;

  /// Consecutive no-match count for the current Stage 2 range point.
  int get rangePointFailureCount => _rangePointFailureCount;

  /// Assisted sing-along attempts used on the current range point.
  int get assistedAttemptCount => _assistedAttempts;

  /// Whether the current range point is in normal, assisted, or verification.
  AssistRecoveryMode get recoveryMode => _recoveryMode;

  /// Which countdown lead-in is active.
  AssistCountdownKind get countdownKind => _countdownKind;

  /// True only when the mic path can exclude the speaker reference.
  ///
  /// This build cannot. See [assistedUserVocalIsolationAvailable].
  bool get canIsolateUserFromReference => assistedUserVocalIsolationAvailable;

  /// Solo attempts before Harmony switches from "try again" to sing-along.
  ///
  /// The first miss is an ordinary retry. The next miss starts assisted
  /// practice. A miss after that practice changes strategy instead of ending.
  static const int soloMissesBeforeAssistance = 2;

  /// True when the next range intro should not name a direction.
  ///
  /// Set after the user agrees to try a nearby sound. The tutor consumes it.
  bool get suppressNextRangeIntro => _suppressNextRangeIntro;

  /// Clears [suppressNextRangeIntro] once the tutor has skipped that intro.
  void consumeRangeIntroSuppression() {
    _suppressNextRangeIntro = false;
  }

  /// Spoken/visual countdown value (3, 2, or 1). Null outside countdown.
  int? get countdownValue => _countdownValue;

  /// Tutor teaching intensity derived from recent struggle counts.
  TutorTeachingLevel get teachingLevel {
    if (_stage == AssistStage.findingStart) {
      if (_stage1FailureCount >= 3) {
        return TutorTeachingLevel.humAlong;
      }
      if (_stage1FailureCount >= 2) {
        return TutorTeachingLevel.guided;
      }
      if (_stage1FailureCount >= 1) {
        return TutorTeachingLevel.retryOnce;
      }
      return TutorTeachingLevel.standard;
    }

    if (_rangePointFailureCount >= 3) {
      return TutorTeachingLevel.humAlong;
    }
    if (_rangePointFailureCount >= 2) {
      return TutorTeachingLevel.guided;
    }
    if (_rangePointFailureCount >= 1) {
      return TutorTeachingLevel.retryOnce;
    }
    return TutorTeachingLevel.standard;
  }

  /// True while a guided Stage 1 demo should play before the next listen.
  bool get stage1GuidedDemoPending => _stage1GuidedDemoPending;

  /// Starts round 1 from the intro.
  Future<void> startSession() async {
    if (_isBusy || _isSessionActive) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    _currentRound = 0;
    _listenProgress = 0;
    _clearListenCapture();
    _candidateFinder.reset();
    _pitchAdjuster.reset();
    _clearStage2State();
    _stage1FailureCount = 0;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _clearRecoveryEpisode();
    _countdownValue = null;
    _stage1GuidedDemoPending = false;
    _referencePitch = initialReferencePitch;
    notifyListeners();

    final generation = ++_sessionGeneration;

    try {
      await _prepareAudioSession();
      _isSessionActive = true;
    } catch (_) {
      _errorMessage = "Let's try that again in a moment.";
      _isSessionActive = false;
      _uiPhase = AssistUiPhase.intro;
      return;
    } finally {
      _isBusy = false;
      notifyListeners();
    }

    await _runRoundLoop(generation);
  }

  /// Drops in-flight rounds immediately so a later callback cannot continue.
  ///
  /// Safe to call more than once. Does not wait on audio, speech, or the mic.
  void cancelActiveWork() {
    if (_isDisposed) {
      return;
    }
    _sessionGeneration += 1;
    _isSessionActive = false;
    _isBusy = false;
    _recoveryMode = AssistRecoveryMode.normal;
    _countdownKind = AssistCountdownKind.soloRetry;
    _countdownValue = null;
    _voiceActivity = 0;
    _stopListenProgress();
    _disablePitchAnalysis();
    _uiPhase = AssistUiPhase.intro;
    notifyListeners();
  }

  /// Leaves Assist Mode and returns to the intro.
  Future<void> stopSession() async {
    if (_isDisposed) {
      return;
    }

    cancelActiveWork();
    await _resetToIntro();
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Retries the current Stage 1 round after insufficient singing.
  ///
  /// When [stage1FailureCount] is high enough, plays a short guided demo before
  /// the countdown so the tutor can demonstrate the sound.
  Future<void> retryRound() async {
    if (_isBusy || _uiPhase != AssistUiPhase.retry || !_isSessionActive) {
      return;
    }

    final generation = _sessionGeneration;
    await _playAndListenRound(generation, incrementRound: false);
  }

  /// Discards the confirmed Shruti and starts a fresh Assist search.
  ///
  /// Only valid from [AssistUiPhase.completed] or
  /// [AssistUiPhase.rangeUnresolved]. Stops confirmed playback,
  /// clears Assist session state, and begins the normal finding flow again.
  /// Does not change Default Mode's selected Shruti.
  Future<void> tryAgain() async {
    if (_isBusy ||
        _isDisposed ||
        (_uiPhase != AssistUiPhase.completed &&
            _uiPhase != AssistUiPhase.rangeUnresolved)) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    // Invalidate timers, waits, and listeners from the completed session so
    // they cannot restore completion after this restart.
    _sessionGeneration += 1;
    await _resetToIntro();

    // Bootstrap a new search the same way [startSession] does.
    _currentRound = 0;
    _listenProgress = 0;
    _clearListenCapture();
    _candidateFinder.reset();
    _pitchAdjuster.reset();
    _clearStage2State();
    _stage1FailureCount = 0;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _clearRecoveryEpisode();
    _countdownValue = null;
    _stage1GuidedDemoPending = false;
    _referencePitch = initialReferencePitch;

    final generation = ++_sessionGeneration;

    try {
      await _prepareAudioSession();
      _isSessionActive = true;
    } catch (_) {
      _errorMessage = "Let's try that again in a moment.";
      _isSessionActive = false;
      _uiPhase = AssistUiPhase.intro;
      return;
    } finally {
      _isBusy = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }

    await _runRoundLoop(generation);
  }

  /// User could hear and match Lower Sa — continue to Pa.
  Future<void> reportLowerSaAudible() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.awaitingLowerAudibility ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    final result = _activeCandidateResult;
    result?.lowerSaAudible = true;
    _lowerSideAccessible = true;

    _currentRangePoint = AssistRangePoint.pa;
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _setPhase(AssistUiPhase.showingTransition);

    try {
      await _awaitPhase(timing.transitionDuration, generation);
    } finally {
      _isBusy = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }

    if (!_isActive(generation)) {
      return;
    }
    await _runRangeTestLoop(generation);
  }

  /// Lower Sa was too low — reject candidate and seek the next higher Shruti.
  ///
  /// Search mode becomes [AssistShrutiSearchMode.seekingHigher]: stop at the
  /// first fully comfortable candidate found while moving up.
  Future<void> reportLowerSaTooLow() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.awaitingLowerAudibility ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    final result = _activeCandidateResult;
    final current = _currentCandidate;
    result?.lowerSaAudible = false;
    _lowerSideAccessible = false;

    if (_searchMode == AssistShrutiSearchMode.seekingLower) {
      // Moving down hit an inaccessible Lower Sa — no supported fit remains.
      _currentBoundaryShruti ??= current;
      _setPhase(AssistUiPhase.rangeUnresolved);
      _isBusy = false;
      notifyListeners();
      if (kDebugMode) {
        debugPrint(
          'AssistDiag LOWER_TOO_LOW candidate=${current?.label} '
          'while seekingLower → unresolved',
        );
      }
      return;
    }

    _searchMode = AssistShrutiSearchMode.seekingHigher;

    // Leave awaiting immediately so a second tap cannot double-advance.
    _setPhase(AssistUiPhase.exploringNextShruti);
    _isBusy = false;
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
        'AssistDiag LOWER_TOO_LOW candidate=${current?.label} '
        '→ seekingHigher',
      );
    }

    await _advanceCandidateOrFinish(
      generation,
      upward: true,
      alreadyShowingExploringNext: true,
    );
  }

  /// Pa felt comfortable — continue to Upper Sa within the same candidate.
  Future<void> reportPaComfortable() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.awaitingPaComfort ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    final result = _activeCandidateResult;
    result?.paComfortable = true;

    if (kDebugMode) {
      debugPrint(
        'AssistDiag PA_COMFORTABLE candidate=${_currentCandidate?.label}',
      );
    }

    _currentRangePoint = AssistRangePoint.upperSa;
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _setPhase(AssistUiPhase.showingTransition);

    try {
      await _awaitPhase(timing.transitionDuration, generation);
    } finally {
      _isBusy = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }

    if (!_isActive(generation)) {
      return;
    }
    await _runRangeTestLoop(generation);
  }

  /// Pa felt strained — same adjustment path as a strained higher note.
  Future<void> reportPaStrained() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.awaitingPaComfort ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    final result = _activeCandidateResult;
    final current = _currentCandidate;
    result?.paComfortable = false;

    if (kDebugMode) {
      debugPrint(
        'AssistDiag PA_STRAINED candidate=${current?.label} '
        'mode=${_searchMode.name}',
      );
    }

    await _handleMiddleOrUpperNotComfortable(
      generation: generation,
      current: current,
      source: 'PA',
    );
  }

  /// Upper Sa felt comfortable.
  ///
  /// - Climbing after a fit: keep exploring higher until strain.
  /// - Seeking higher/lower after a miss: this is the first fit — finish.
  Future<void> reportUpperSaComfortable() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.awaitingUpperComfort ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    final result = _activeCandidateResult;
    final current = _currentCandidate;
    result?.upperSaComfortable = true;
    if (current != null) {
      _lastComfortableShruti = current;
    }
    _lowerSideAccessible = true;

    final stopAtFirstFit =
        _searchMode == AssistShrutiSearchMode.seekingHigher ||
        _searchMode == AssistShrutiSearchMode.seekingLower;

    if (kDebugMode) {
      debugPrint(
        'AssistDiag UPPER_COMFORTABLE candidate=${current?.label} '
        'mode=${_searchMode.name} '
        'stopAtFirstFit=$stopAtFirstFit',
      );
    }

    if (stopAtFirstFit) {
      // First fully comfortable Shruti while seeking — done.
      try {
        await _completeRangeTest(current!);
      } finally {
        _isBusy = false;
        if (!_isDisposed) {
          notifyListeners();
        }
      }
      return;
    }

    // Initial fit or climbing — explore the next higher Shruti.
    _searchMode = AssistShrutiSearchMode.climbing;
    _setPhase(AssistUiPhase.exploringNextShruti);
    _isBusy = false;
    notifyListeners();

    await _advanceCandidateOrFinish(
      generation,
      upward: true,
      alreadyShowingExploringNext: true,
    );
  }

  /// Upper Sa felt strained.
  ///
  /// - If a prior comfortable exists (climbing): stop at that boundary.
  /// - Otherwise: seek one Shruti lower and stop at the first full fit.
  Future<void> reportUpperSaStrained() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.awaitingUpperComfort ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    final result = _activeCandidateResult;
    final current = _currentCandidate;
    result?.upperSaComfortable = false;

    if (kDebugMode) {
      debugPrint(
        'AssistDiag UPPER_STRAINED candidate=${current?.label} '
        'mode=${_searchMode.name}',
      );
    }

    await _handleMiddleOrUpperNotComfortable(
      generation: generation,
      current: current,
      source: 'UPPER',
    );
  }

  /// Shared "not comfortable" adjustment for middle (Pa) and higher (Upper Sa).
  ///
  /// Caller must already hold [_isBusy] and have recorded the comfort flag.
  Future<void> _handleMiddleOrUpperNotComfortable({
    required int generation,
    required Pitch? current,
    required String source,
  }) async {
    _currentBoundaryShruti = current;

    if (_lastComfortableShruti != null) {
      if (kDebugMode) {
        debugPrint(
          'AssistDiag ${source}_STRAINED candidate=${current?.label} '
          'lastComfortable=${_lastComfortableShruti?.label} → boundary',
        );
      }
      _setPhase(AssistUiPhase.rangeBoundaryReached);
      _isBusy = false;
      notifyListeners();
      return;
    }

    if (_searchMode == AssistShrutiSearchMode.seekingHigher) {
      // Audible lower but strained middle/upper while seeking after "too low" —
      // no single supported Shruti fully fits.
      _setPhase(AssistUiPhase.rangeUnresolved);
      _isBusy = false;
      notifyListeners();
      if (kDebugMode) {
        debugPrint(
          'AssistDiag ${source}_STRAINED candidate=${current?.label} '
          'while seekingHigher → unresolved',
        );
      }
      return;
    }

    // Too high with no prior comfortable — seek downward.
    _searchMode = AssistShrutiSearchMode.seekingLower;
    _setPhase(AssistUiPhase.exploringNextShruti);
    _isBusy = false;
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
        'AssistDiag ${source}_STRAINED candidate=${current?.label} '
        '→ seekingLower',
      );
    }

    await _advanceCandidateOrFinish(
      generation,
      upward: false,
      alreadyShowingExploringNext: true,
    );
  }

  /// Acknowledges the upper-boundary message and finishes with the last
  /// comfortable Shruti (never the strained boundary candidate).
  Future<void> acknowledgeRangeBoundary() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.rangeBoundaryReached) {
      return;
    }

    final recommended = _lastComfortableShruti;
    if (recommended == null) {
      _setPhase(AssistUiPhase.rangeUnresolved);
      notifyListeners();
      return;
    }

    _isBusy = true;
    notifyListeners();
    try {
      await _completeRangeTest(recommended);
    } finally {
      _isBusy = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _runRoundLoop(int generation) async {
    while (!_isDisposed &&
        _isSessionActive &&
        generation == _sessionGeneration &&
        _uiPhase != AssistUiPhase.completed) {
      final finished = await _playAndListenRound(generation);
      if (!finished) {
        return;
      }
      if (_uiPhase == AssistUiPhase.completed ||
          _uiPhase == AssistUiPhase.retry ||
          _uiPhase == AssistUiPhase.intro ||
          _uiPhase == AssistUiPhase.refreshingStartingNote ||
          _uiPhase == AssistUiPhase.offeringEasierSound ||
          _stage == AssistStage.exploringRange) {
        return;
      }
    }
  }

  /// Runs one Stage 1 capture cycle: optional guided demo, countdown, listen
  /// for a stable voice note (no Tanpura on the first attempt), map to the
  /// nearest supported Shruti, then enter Stage 2 with that pitch as the
  /// starting candidate only.
  ///
  /// Returns `true` when the cycle finished normally for this generation.
  Future<bool> _playAndListenRound(
    int generation, {
    bool incrementRound = true,
  }) async {
    if (!_isActive(generation)) {
      return false;
    }

    if (incrementRound) {
      _currentRound += 1;
    }
    _listenProgress = 0;

    // Ensure no reference / Tanpura audio is playing during initial discovery
    // unless a guided demo was requested after repeated struggle.
    _disablePitchAnalysis();
    await _safePauseAudio();
    await _safeStopReferenceSound();
    await _safeStopDetection();

    if (_stage1GuidedDemoPending) {
      final demoPlayed = await _playStage1GuidedDemo(generation);
      _stage1GuidedDemoPending = false;
      if (!demoPlayed) {
        return false;
      }
    }

    // Stage 1: the user already tapped "I'm ready" — no spoken/visual countdown.
    // Stage 2 still uses the 3…2…1 lead-in before each solo listen.
    if (_stage == AssistStage.exploringRange) {
      final countedDown = await _runCountdown(generation);
      if (!countedDown) {
        return false;
      }
    } else {
      _countdownValue = null;
    }

    await tutorHooks?.beforeListen?.call();
    if (!_isActive(generation)) {
      return false;
    }

    // LISTEN — mic on, reference audio off.
    _candidateFinder.reset();
    _clearListenCapture();
    _rawF0LogCounter = 0;
    _setPhase(AssistUiPhase.listening);
    try {
      await _startPitchAnalysis();
    } on PitchDetectionException catch (_) {
      _errorMessage = "That's okay. Let's try that once more.";
      _failListenCapture(reason: 'pitch_detection_start_failed');
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = "That's okay. Let's try that once more.";
      _failListenCapture(reason: 'listen_start_failed');
      notifyListeners();
      return true;
    }

    _startListenProgress(generation);
    await _awaitPhase(timing.listenDuration, generation);
    _stopListenProgress();
    if (!_isActive(generation)) {
      return false;
    }

    // END LISTENING — leave listening/failure eligibility before stopping.
    final timedOutWithoutAccept = _acceptedListenCandidate == null;
    if (timedOutWithoutAccept && kDebugMode) {
      debugPrint('AssistDiag LISTEN_TIMEOUT');
    }

    if (_uiPhase == AssistUiPhase.listening) {
      _setPhase(AssistUiPhase.processing);
    }
    _disablePitchAnalysis();
    _logListeningStop(
      reason: _acceptedListenCandidate != null
          ? 'candidate_accepted'
          : 'listen_window_ended',
    );
    await _readingsSubscription?.cancel();
    _readingsSubscription = null;
    await _safeStopDetection();

    final observation = _takeListenObservation();
    await tutorHooks?.afterListenWindow?.call(observation != null);
    if (!_isActive(generation)) {
      return false;
    }

    if (observation == null) {
      _failListenCapture(reason: 'no_candidate_after_listen');
      notifyListeners();
      return true;
    }

    if (kDebugMode) {
      debugPrint('AssistDiag CONTROLLER_RECEIVED_SUCCESS');
      debugPrint(
        'AssistDiag FINAL_RESULT candidate=${observation.pitch.label}@'
        '${observation.frequencyHz.toStringAsFixed(1)}Hz '
        'n=${observation.stableSampleCount}',
      );
    }

    final nearest = nearestSupportedShruti(observation.frequencyHz);
    if (nearest == null) {
      _failListenCapture(reason: 'no_supported_shruti');
      notifyListeners();
      return true;
    }

    // Starting point only — not the user's final Shruti.
    _stage1FailureCount = 0;
    _referencePitch = nearest.pitch;
    _pitchAdjuster.start(nearest.frequencyHz);

    if (kDebugMode) {
      debugPrint(
        'AssistDiag detectedVoiceHz='
        '${observation.frequencyHz.toStringAsFixed(1)}',
      );
      debugPrint('AssistDiag detectedVoiceNote=${observation.pitch.label}');
      debugPrint(
        'AssistDiag startingPointCandidate=${nearest.pitch.label} '
        '(not final Shruti)',
      );
      debugPrint(
        'AssistDiag startingPointHz='
        '${nearest.frequencyHz.toStringAsFixed(1)}',
      );
    }

    // Stage 2 opening already finished in afterListenWindow after "I'm ready".
    // Use the short entry yield so the first range intro follows promptly.
    if (_uiPhase != AssistUiPhase.processing) {
      _setPhase(AssistUiPhase.processing);
    }
    notifyListeners();
    await _awaitPhase(timing.stage2EntryTransitionDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }

    return _beginStage2(generation);
  }

  /// Plays a short mid-range demo so the user can hear a sound to match.
  ///
  /// Used only after repeated Stage 1 struggle — never on the first attempt.
  Future<bool> _playStage1GuidedDemo(int generation) async {
    final demoHz = frequencyHzForPitch(Pitch.g);
    await tutorHooks?.beforeReference?.call();
    if (!_isActive(generation)) {
      return false;
    }

    _setPhase(AssistUiPhase.playingReference);
    _disablePitchAnalysis();
    await _safeStopDetection();
    try {
      await _referenceSoundGenerator.playReference(
        demoHz,
        duration: timing.referencePlayDuration,
      );
    } on AudioServiceException catch (_) {
      _errorMessage = "That's okay. Let's try that once more.";
      return _isActive(generation);
    }

    await _awaitPhase(timing.referencePlayDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }

    _setPhase(AssistUiPhase.preparingToListen);
    await _safeStopReferenceSound();
    await _awaitPhase(timing.settlingDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }
    await tutorHooks?.afterReference?.call();
    return _isActive(generation);
  }

  /// Spoken + visual countdown: 3, 2, 1. Listening starts after 1.
  ///
  /// [countdownValue] is 3, 2, then 1. Skipped when
  /// [AssistTimingConfig.countdownStepDuration] is zero or negative.
  ///
  /// Tutor speech for each step is awaited via [AssistTutorHooks.onCountdownStep]
  /// so spoken and visual countdown stay synchronized and emit once.
  Future<bool> _runCountdown(int generation) async {
    if (timing.countdownStepDuration <= Duration.zero) {
      _countdownValue = null;
      return true;
    }

    await tutorHooks?.beforeCountdown?.call();
    if (!_isActive(generation)) {
      return false;
    }

    for (var value = 3; value >= 1; value--) {
      if (!_isActive(generation)) {
        return false;
      }
      _countdownValue = value;
      _setPhase(AssistUiPhase.countdown);
      notifyListeners();

      final stepSpeech = tutorHooks?.onCountdownStep?.call(value);
      final stepWait = _awaitPhase(timing.countdownStepDuration, generation);
      if (stepSpeech != null) {
        await Future.wait<void>([stepSpeech, stepWait]);
      } else {
        await stepWait;
      }
    }

    _countdownValue = null;
    notifyListeners();
    return _isActive(generation);
  }

  /// Locks Stage 1 starting candidate and begins the guided 3-point range check.
  Future<bool> _beginStage2(int generation) async {
    _stage = AssistStage.exploringRange;
    _stage1Shruti = _referencePitch;
    _testedCandidates.clear();
    _lastComfortableShruti = null;
    _currentBoundaryShruti = null;
    _searchMode = AssistShrutiSearchMode.initial;
    _lowerSideAccessible = false;
    _prepareCandidate(_referencePitch);

    // Keep entry phases for observers. The Stage 2 opening already finished in
    // afterListenWindow, so do not add another multi-second silence before the
    // first range intro ("Let's try a slightly lower sound.").
    _setPhase(AssistUiPhase.startingPointFound);
    await _awaitPhase(timing.stage2EntryTransitionDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }

    _setPhase(AssistUiPhase.showingTransition);
    await _awaitPhase(timing.stage2EntryTransitionDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }

    return _runRangeTestLoop(generation);
  }

  /// Seeds Stage 2 fields for [candidate] without changing UI phase.
  void _prepareCandidate(Pitch candidate) {
    _currentCandidate = candidate;
    _referencePitch = candidate;
    _rangeTargets = AssistRangeTargets(candidate);
    _currentRangePoint = AssistRangePoint.lowerSa;
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _soundChangeDeclined = false;
    _forceAssistedPass = false;
    final result = AssistCandidateRangeResult(candidate);
    _activeCandidateResult = result;
    _testedCandidates.add(result);
    _targetMatcher.stop();
  }

  Future<bool> _runRangeTestLoop(int generation) async {
    while (_isActive(generation) &&
        _stage == AssistStage.exploringRange &&
        !_isRangeDecisionPause) {
      final finished = await _playAndMatchRangePoint(generation);
      if (!finished) {
        return false;
      }
      if (_isRangeDecisionPause ||
          _uiPhase == AssistUiPhase.completed ||
          _uiPhase == AssistUiPhase.intro) {
        return true;
      }
    }
    return _isActive(generation);
  }

  /// True while Stage 2 is waiting on a user answer or has stopped exploring.
  bool get _isRangeDecisionPause =>
      _uiPhase == AssistUiPhase.awaitingLowerAudibility ||
      _uiPhase == AssistUiPhase.awaitingPaComfort ||
      _uiPhase == AssistUiPhase.awaitingUpperComfort ||
      _uiPhase == AssistUiPhase.rangeBoundaryReached ||
      _uiPhase == AssistUiPhase.rangeUnresolved ||
      _uiPhase == AssistUiPhase.offeringEasierSound ||
      _uiPhase == AssistUiPhase.refreshingStartingNote;

  /// Stage 2: play one range point → settle → countdown → listen for match.
  ///
  /// On Lower Sa match: pause for audibility. On Pa match: pause for comfort.
  /// On Upper Sa match: pause for comfort. On no match: retry same point.
  Future<bool> _playAndMatchRangePoint(int generation) async {
    final targets = _rangeTargets;
    final point = _currentRangePoint;
    final candidate = _currentCandidate;
    if (targets == null || point == null || candidate == null) {
      return false;
    }

    final targetHz = targets.frequencyHzFor(point);

    _currentRound += 1;
    _listenProgress = 0;
    _referencePitch = candidate;
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;

    final forcedAssist = _forceAssistedPass;
    if (_forceAssistedPass) {
      _forceAssistedPass = false;
    }
    final useAssisted =
        forcedAssist ||
        (_rangePointFailureCount >= soloMissesBeforeAssistance &&
            _assistedAttempts == 0);

    if (useAssisted) {
      final assisted = await _runAssistedSinging(generation, targetHz);
      if (assisted != AssistedSingResult.readyForSolo ||
          !_isActive(generation)) {
        return false;
      }
    } else {
      // 0) Tutor speaks first — never overlaps reference audio.
      await tutorHooks?.beforeReference?.call();
      if (!_isActive(generation)) {
        return false;
      }

      // Prepare silently while the spoken instruction screen is still up.
      _disablePitchAnalysis();
      await _safeStopDetection();
      await _safePauseAudio();
      if (!_isActive(generation)) {
        return false;
      }

      // 1) LISTEN SCREEN + PLAY — instruction text and reference begin together.
      _setPhase(AssistUiPhase.playingReference);
      try {
        await _referenceSoundGenerator.playReference(
          targetHz,
          duration: timing.referencePlayDuration,
        );
      } on AudioServiceException catch (error) {
        if (kDebugMode) {
          debugPrint(
            'ReferenceToneDiag CONTROLLER_CATCH message=${error.message} '
            'cause=${error.cause} causeType=${error.cause?.runtimeType}',
          );
        }
        _errorMessage = "That's okay. Let's try that once more.";
        await _resetToIntro();
        notifyListeners();
        return false;
      }

      await _awaitPhase(timing.referencePlayDuration, generation);
      if (!_isActive(generation)) {
        return false;
      }

      // 2) STOP + settle — analysis still off.
      _setPhase(AssistUiPhase.preparingToListen);
      await _safeStopReferenceSound();
      await _safePauseAudio();
      _disablePitchAnalysis();
      await _safeStopDetection();

      await _awaitPhase(timing.settlingDuration, generation);
      if (!_isActive(generation)) {
        return false;
      }
      await tutorHooks?.afterReference?.call();
      if (!_isActive(generation)) {
        return false;
      }
    }

    // 3) Countdown — still no mic analysis. Solo verification follows.
    final countedDown = await _runCountdown(generation);
    if (!countedDown) {
      return false;
    }

    await tutorHooks?.beforeListen?.call();
    if (!_isActive(generation)) {
      return false;
    }

    // 4) LISTEN — match the fixed Hz target without octave folding so Lower
    // Sa and Upper Sa remain distinct.
    _targetMatcher.start(targetHz, foldOctaves: false);
    _clearListenCapture();
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
    _rawF0LogCounter = 0;
    _setPhase(AssistUiPhase.listening);
    try {
      await _startPitchAnalysis();
    } on PitchDetectionException catch (_) {
      _errorMessage = "That's okay. Let's try that once more.";
      _targetMatcher.stop();
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = "That's okay. Let's try that once more.";
      _targetMatcher.stop();
      notifyListeners();
      return true;
    }

    _startListenProgress(generation);
    await _awaitPhase(timing.listenDuration, generation);
    _stopListenProgress();
    if (!_isActive(generation)) {
      return false;
    }

    if (_uiPhase == AssistUiPhase.listening) {
      _setPhase(AssistUiPhase.processing);
    }
    _disablePitchAnalysis();
    _logListeningStop(
      reason: _rangeMatchAccepted ? 'target_matched' : 'listen_window_ended',
    );
    await _readingsSubscription?.cancel();
    _readingsSubscription = null;
    await _safeStopDetection();

    final matched = _rangeMatchAccepted || _targetMatcher.isMatched;
    _targetMatcher.stop();
    await tutorHooks?.afterListenWindow?.call(matched);
    if (!_isActive(generation)) {
      return false;
    }

    if (!matched) {
      _rangePointFailureCount += 1;
      if (useAssisted) {
        _assistedAttempts += 1;
      }
      if (kDebugMode) {
        debugPrint(
          'AssistDiag RANGE_NO_MATCH point=${point.name} '
          'targetHz=${targetHz.toStringAsFixed(1)} '
          'failures=$_rangePointFailureCount — retry same point',
        );
      }
      if (useAssisted) {
        _recoveryMode = AssistRecoveryMode.normal;
        if (_movedForRecovery || _soundChangeDeclined) {
          _enterStartingNoteRefresh();
          return _isActive(generation);
        }
        _setPhase(AssistUiPhase.offeringEasierSound);
        return _isActive(generation);
      }
      _setPhase(AssistUiPhase.showingTransition);
      await _awaitPhase(timing.transitionDuration, generation);
      return _isActive(generation);
    }

    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _movedForRecovery = false;
    _soundChangeDeclined = false;
    _forceAssistedPass = false;

    if (kDebugMode) {
      debugPrint(
        'AssistDiag RANGE_MATCHED point=${point.name} '
        'targetHz=${targetHz.toStringAsFixed(1)}',
      );
    }

    final result = _activeCandidateResult;
    switch (point) {
      case AssistRangePoint.lowerSa:
        result?.lowerSaMatched = true;
        if (_shouldSkipLowerAudibilityQuestion) {
          // Climbing: lower side already proven — keep Lower Sa → Pa → Upper
          // Sa audio, but do not re-ask audibility.
          result?.lowerSaAudible = true;
          _currentRangePoint = AssistRangePoint.pa;
          _rangeMatchAccepted = false;
          _rangeVoiceHz = null;
          _rangePointFailureCount = 0;
          _assistedAttempts = 0;
          _setPhase(AssistUiPhase.showingTransition);
          await _awaitPhase(timing.transitionDuration, generation);
          return _isActive(generation);
        }
        _setPhase(AssistUiPhase.awaitingLowerAudibility);
        notifyListeners();
        return true;
      case AssistRangePoint.pa:
        result?.paMatched = true;
        _setPhase(AssistUiPhase.awaitingPaComfort);
        notifyListeners();
        return true;
      case AssistRangePoint.upperSa:
        result?.upperSaMatched = true;
        _setPhase(AssistUiPhase.awaitingUpperComfort);
        notifyListeners();
        return true;
    }
  }

  /// Plays the reference while the user sings along, then hands off to solo.
  ///
  /// Pitch matching stays off for the whole practice window. The window ending
  /// is not a success or a failure. [AssistedSingResult.readyForSolo] means
  /// the caller should run the existing solo countdown and listen.
  Future<AssistedSingResult> _runAssistedSinging(
    int generation,
    double targetHz,
  ) async {
    _recoveryMode = AssistRecoveryMode.assistedSinging;
    _targetMatcher.stop();
    _disablePitchAnalysis();
    await _safeStopDetection();
    _rangeMatchAccepted = false;

    await tutorHooks?.beforeAssistedSinging?.call();
    if (!_isActive(generation)) {
      return AssistedSingResult.stopped;
    }

    _countdownKind = AssistCountdownKind.singTogether;
    final countedDown = await _runCountdown(generation);
    _countdownKind = AssistCountdownKind.soloRetry;
    if (!countedDown || !_isActive(generation)) {
      return AssistedSingResult.stopped;
    }

    _setPhase(AssistUiPhase.assistedSinging);
    _recoveryMode = AssistRecoveryMode.assistedSinging;
    _targetMatcher.stop();
    _disablePitchAnalysis();
    await tutorHooks?.onAssistedReferenceWillStart?.call();
    if (!_isActive(generation)) {
      return AssistedSingResult.stopped;
    }

    try {
      await _referenceSoundGenerator.playReference(
        targetHz,
        duration: timing.assistedSingWindow,
      );
    } on AudioServiceException catch (_) {
      _errorMessage = "That's okay. Let's try that once more.";
      _recoveryMode = AssistRecoveryMode.normal;
      await _resetToIntro();
      notifyListeners();
      return AssistedSingResult.stopped;
    }

    await _awaitPhase(timing.assistedSingWindow, generation);
    if (!_isActive(generation)) {
      return AssistedSingResult.stopped;
    }

    await _safeStopReferenceSound();
    await _safePauseAudio();
    _disablePitchAnalysis();
    await _safeStopDetection();
    _targetMatcher.stop();
    _rangeMatchAccepted = false;

    // The reference and the microphone do not share an echo reference.
    // This window is practice only. Scoring happens on the solo listen.
    _setPhase(AssistUiPhase.preparingToListen);
    _recoveryMode = AssistRecoveryMode.normal;
    await _awaitPhase(timing.settlingDuration, generation);
    if (!_isActive(generation)) {
      return AssistedSingResult.stopped;
    }
    await tutorHooks?.afterAssistedSinging?.call();
    if (!_isActive(generation)) {
      return AssistedSingResult.stopped;
    }
    return AssistedSingResult.readyForSolo;
  }

  /// Stops capture and playback focus so speech recognition can use the mic.
  Future<void> prepareForSpokenAnswer() async {
    _disablePitchAnalysis();
    _targetMatcher.stop();
    await _safeStopDetection();
    await _safeStopReferenceSound();
    await _safePauseAudio();
    await suspendAudioSessionForSpeechRecognition();
  }

  /// Restores the play-and-record session after a spoken answer.
  Future<void> restoreAfterSpokenAnswer() async {
    try {
      await _prepareAudioSession();
    } catch (_) {}
  }

  /// Skip the Lower Sa question while climbing after a prior audible Lower Sa.
  bool get _shouldSkipLowerAudibilityQuestion =>
      _lowerSideAccessible && _searchMode == AssistShrutiSearchMode.climbing;

  /// Moves one Shruti up or down, or finishes / unresolved at supported edges.
  Future<void> _advanceCandidateOrFinish(
    int generation, {
    required bool upward,
    bool alreadyShowingExploringNext = false,
  }) async {
    final current = _currentCandidate;
    if (current == null) {
      return;
    }

    final next = upward
        ? nextHigherSupportedShruti(current)
        : nextLowerSupportedShruti(current);

    if (next == null) {
      if (upward) {
        // Top of supported range — finish with last comfortable if any.
        final recommended = _lastComfortableShruti;
        if (recommended == null) {
          _currentBoundaryShruti ??= current;
          _setPhase(AssistUiPhase.rangeUnresolved);
          notifyListeners();
          return;
        }
        await _completeRangeTest(recommended);
        return;
      }

      // Bottom of supported range while seeking lower — unresolved.
      _currentBoundaryShruti ??= current;
      _setPhase(AssistUiPhase.rangeUnresolved);
      notifyListeners();
      return;
    }

    if (!alreadyShowingExploringNext) {
      _setPhase(AssistUiPhase.exploringNextShruti);
    }
    await _awaitPhase(timing.transitionDuration, generation);
    if (!_isActive(generation)) {
      return;
    }

    _prepareCandidate(next);

    if (kDebugMode) {
      debugPrint(
        'AssistDiag EXPLORE_${upward ? "HIGHER" : "LOWER"} '
        'candidate=${next.label} from=${current.label} '
        'mode=${_searchMode.name}',
      );
    }

    _setPhase(AssistUiPhase.showingTransition);
    await _awaitPhase(timing.transitionDuration, generation);
    if (!_isActive(generation)) {
      return;
    }

    await _runRangeTestLoop(generation);
  }

  /// Completes Stage 2 — plays the recommended Shruti (no comfort score).
  ///
  /// When a tutor is attached, the success dialogue finishes before the Shruti
  /// sample starts so the two audio sources never overlap.
  Future<void> _completeRangeTest(Pitch candidate) async {
    final generation = _sessionGeneration;
    _referencePitch = candidate;
    _stopListenProgress();
    _closeWindow();
    _disablePitchAnalysis();
    _targetMatcher.stop();
    _rangeVoiceHz = null;

    if (kDebugMode) {
      debugPrint(
        'AssistDiag RANGE_COMPLETE candidate=${candidate.label} '
        'lastComfortable=${_lastComfortableShruti?.label} '
        'boundary=${_currentBoundaryShruti?.label} '
        '(no comfort score)',
      );
    }

    // Silence any prior sample / reference so tutor speech is alone.
    await _safePauseAudio();
    await _safeStopReferenceSound();
    if (!_isActive(generation)) {
      return;
    }

    _setPhase(AssistUiPhase.completed);

    // Tutor success dialogue must finish before Shruti playback.
    await tutorHooks?.beforeCompletionPlayback?.call();
    if (!_isActive(generation)) {
      return;
    }

    try {
      await _playReferenceForPitch(candidate);
    } on AudioServiceException catch (_) {
      _errorMessage = "That's okay — your Shruti is ready.";
    } catch (_) {
      _errorMessage = "That's okay — your Shruti is ready.";
    }
    notifyListeners();
  }

  void _clearStage2State() {
    _stage = AssistStage.findingStart;
    _stage1Shruti = null;
    _currentCandidate = null;
    _rangeTargets = null;
    _currentRangePoint = null;
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
    _testedCandidates.clear();
    _activeCandidateResult = null;
    _lastComfortableShruti = null;
    _currentBoundaryShruti = null;
    _searchMode = AssistShrutiSearchMode.initial;
    _lowerSideAccessible = false;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _clearRecoveryEpisode();
    _targetMatcher.stop();
  }

  void _clearRecoveryEpisode() {
    _movedForRecovery = false;
    _soundChangeDeclined = false;
    _forceAssistedPass = false;
    _suppressNextRangeIntro = false;
  }

  /// Nearby supported Shruti in the current search direction.
  ///
  /// Uses [nextHigherSupportedShruti] and [nextLowerSupportedShruti] only.
  /// When the preferred step is already at the edge, the other existing step
  /// is used so one stuck sound does not end discovery.
  Pitch? _nearbyRecoveryShruti(Pitch current) {
    final preferHigher = switch (_searchMode) {
      AssistShrutiSearchMode.seekingLower => false,
      AssistShrutiSearchMode.climbing ||
      AssistShrutiSearchMode.seekingHigher => true,
      AssistShrutiSearchMode.initial =>
        _currentRangePoint != AssistRangePoint.upperSa,
    };
    final primary = preferHigher
        ? nextHigherSupportedShruti(current)
        : nextLowerSupportedShruti(current);
    if (primary != null) {
      return primary;
    }
    return preferHigher
        ? nextLowerSupportedShruti(current)
        : nextHigherSupportedShruti(current);
  }

  /// Leaves the stuck sound for the next supported candidate, then solos.
  ///
  /// Valid only from [AssistUiPhase.offeringEasierSound].
  Future<void> acceptDifferentSound() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.offeringEasierSound ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    final current = _currentCandidate;
    final next = current == null ? null : _nearbyRecoveryShruti(current);
    _movedForRecovery = true;
    _soundChangeDeclined = false;
    _forceAssistedPass = false;
    _recoveryMode = AssistRecoveryMode.normal;

    if (next == null) {
      _isBusy = false;
      if (!_isDisposed) {
        notifyListeners();
      }
      _enterStartingNoteRefresh();
      return;
    }

    _setPhase(AssistUiPhase.exploringNextShruti);
    try {
      await _awaitPhase(timing.transitionDuration, generation);
      if (!_isActive(generation)) {
        return;
      }
      _prepareCandidate(next);
      _suppressNextRangeIntro = true;
      _movedForRecovery = true;

      if (kDebugMode) {
        debugPrint(
          'AssistDiag RECOVERY_NEARBY from=${current?.label} '
          'to=${next.label} mode=${_searchMode.name}',
        );
      }

      _setPhase(AssistUiPhase.showingTransition);
      await _awaitPhase(timing.transitionDuration, generation);
    } finally {
      _isBusy = false;
      if (!_isDisposed) {
        notifyListeners();
      }
    }

    if (!_isActive(generation)) {
      return;
    }
    await _runRangeTestLoop(generation);
  }

  /// Keeps the current sound and runs one more assisted practice pass.
  ///
  /// Valid only from [AssistUiPhase.offeringEasierSound].
  Future<void> declineDifferentSound() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.offeringEasierSound ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    _soundChangeDeclined = true;
    _forceAssistedPass = true;
    _recoveryMode = AssistRecoveryMode.normal;
    _setPhase(AssistUiPhase.showingTransition);

    _isBusy = false;
    if (!_isDisposed) {
      notifyListeners();
    }
    if (!_isActive(generation)) {
      return;
    }
    await _runRangeTestLoop(generation);
  }

  /// Pauses Stage 2 and waits for a fresh Stage 1 starting note.
  ///
  /// Does not end the session or clear the tutor conversation.
  void _enterStartingNoteRefresh() {
    _stage = AssistStage.findingStart;
    _currentCandidate = null;
    _rangeTargets = null;
    _currentRangePoint = null;
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
    _activeCandidateResult = null;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _clearRecoveryEpisode();
    _stage1FailureCount = 0;
    _stage1GuidedDemoPending = false;
    _recoveryMode = AssistRecoveryMode.normal;
    _countdownKind = AssistCountdownKind.soloRetry;
    _targetMatcher.stop();
    _disablePitchAnalysis();
    _setPhase(AssistUiPhase.refreshingStartingNote);
  }

  /// Continues the same session with Stage 1 listening.
  ///
  /// Valid only from [AssistUiPhase.refreshingStartingNote].
  Future<void> continueStartingNoteDiscovery() async {
    if (_isBusy ||
        _isDisposed ||
        !_isSessionActive ||
        _uiPhase != AssistUiPhase.refreshingStartingNote ||
        _stage != AssistStage.findingStart) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final generation = _sessionGeneration;
    _stage1FailureCount = 0;
    _stage1GuidedDemoPending = false;
    _setPhase(AssistUiPhase.showingTransition);

    _isBusy = false;
    if (!_isDisposed) {
      notifyListeners();
    }
    if (!_isActive(generation)) {
      return;
    }
    await _runRoundLoop(generation);
  }

  bool _isActive(int generation) =>
      !_isDisposed && _isSessionActive && generation == _sessionGeneration;

  void _setPhase(AssistUiPhase phase) {
    if (_uiPhase == phase) {
      return;
    }
    if (kDebugMode) {
      debugPrint(
        'AssistDiag STATE_CHANGE old=${_uiPhase.name} new=${phase.name}',
      );
    }
    if (phase != AssistUiPhase.listening) {
      _voiceActivity = 0;
    }
    _uiPhase = phase;
    notifyListeners();
  }

  void _disablePitchAnalysis() {
    _pitchAnalysisEnabled = false;
  }

  void _clearListenCapture() {
    _acceptedListenCandidate = null;
    _listenCaptureResolved = false;
  }

  /// Atomically latches a successful candidate and leaves listening eligibility.
  ///
  /// Returns `false` when a prior decision already resolved this listen window.
  /// The listen timer may still be running; [ _takeListenObservation ] prefers
  /// this latch so a later timeout cannot overwrite success.
  bool _tryAcceptListenCandidate(
    StablePitchCandidate candidate, {
    required String source,
  }) {
    if (_listenCaptureResolved) {
      return false;
    }
    if (_uiPhase != AssistUiPhase.listening &&
        _uiPhase != AssistUiPhase.processing) {
      return false;
    }

    _listenCaptureResolved = true;
    _acceptedListenCandidate = candidate;
    // Leave failure eligibility before any later stop/timeout path runs.
    _disablePitchAnalysis();

    if (kDebugMode) {
      debugPrint(
        'AssistDiag CANDIDATE_SUCCESS hz='
        '${candidate.frequencyHz.toStringAsFixed(1)} '
        'note=${candidate.pitch.label} source=$source',
      );
    }

    if (_uiPhase == AssistUiPhase.listening) {
      _setPhase(AssistUiPhase.processing);
    }
    return true;
  }

  /// Failure for "no steady note" only — never overwrites an accepted candidate.
  void _failListenCapture({required String reason}) {
    if (_acceptedListenCandidate != null) {
      if (kDebugMode) {
        debugPrint(
          'AssistDiag CONTROLLER_FAILURE ignored reason=$reason '
          '(candidate already accepted)',
        );
      }
      return;
    }
    _listenCaptureResolved = true;
    _stage1FailureCount += 1;
    // After two failures, the next retry demonstrates a sound first.
    _stage1GuidedDemoPending = _stage1FailureCount >= 2;
    if (kDebugMode) {
      debugPrint('AssistDiag CONTROLLER_FAILURE reason=$reason');
      debugPrint('AssistDiag FINAL_RESULT kind=failure reason=$reason');
      debugPrint(
        'AssistDiag stage1FailureCount=$_stage1FailureCount '
        'guidedDemoPending=$_stage1GuidedDemoPending',
      );
    }
    if (_uiPhase != AssistUiPhase.retry) {
      _setPhase(AssistUiPhase.retry);
    }
  }

  StablePitchCandidate? _takeListenObservation() {
    final accepted = _acceptedListenCandidate;
    if (accepted != null) {
      return accepted;
    }
    final fromFinder = _candidateFinder.result();
    if (fromFinder != null) {
      _tryAcceptListenCandidate(fromFinder, source: 'listen_end_drain');
      return _acceptedListenCandidate ?? fromFinder;
    }
    return null;
  }

  void _logListeningStop({required String reason}) {
    if (kDebugMode) {
      debugPrint('AssistDiag LISTENING_STOP reason=$reason');
    }
  }

  Future<void> _startPitchAnalysis() async {
    _pitchAnalysisEnabled = true;
    if (!_detectionService.isListening) {
      await _detectionService.start();
    }
    await _readingsSubscription?.cancel();
    _readingsSubscription = _detectionService.readings.listen(
      _onReading,
      onError: _onDetectionError,
    );
  }

  int _rawF0LogCounter = 0;

  void _onReading(PitchReading reading) {
    if (!_pitchAnalysisEnabled || _uiPhase != AssistUiPhase.listening) {
      return;
    }
    if (_listenCaptureResolved) {
      return;
    }
    if (_recoveryMode == AssistRecoveryMode.assistedSinging) {
      return;
    }
    final level = reading.level.clamp(0.0, 1.0);
    if ((level - _voiceActivity).abs() >= 0.02) {
      _voiceActivity = level;
      notifyListeners();
    }
    if (kDebugMode && reading.hasPitch && reading.frequencyHz != null) {
      _rawF0LogCounter += 1;
      if (_rawF0LogCounter % 8 == 1) {
        final hz = reading.frequencyHz!;
        final note = reading.note ?? noteFromFrequency(hz);
        debugPrint(
          'AssistDiag rawF0=${hz.toStringAsFixed(1)}Hz '
          'note=${note?.label ?? "?"} '
          'ref=${_referencePitch.label} '
          'stage=${_stage.name}',
        );
      }
    }

    if (_stage == AssistStage.exploringRange) {
      final centsBefore = _targetMatcher.centsFromTarget;
      if (reading.hasPitch && reading.frequencyHz != null) {
        _rangeVoiceHz = reading.frequencyHz;
      }
      _targetMatcher.add(reading);
      final centsAfter = _targetMatcher.centsFromTarget;
      if ((reading.hasPitch && reading.frequencyHz != null) ||
          centsBefore != centsAfter) {
        notifyListeners();
      }
      if (_targetMatcher.isMatched) {
        _tryAcceptRangeMatch(source: 'mid_listen');
      }
      return;
    }

    _candidateFinder.add(reading);
    if (_candidateFinder.hasCandidate) {
      final candidate = _candidateFinder.result();
      if (candidate != null) {
        _tryAcceptListenCandidate(candidate, source: 'mid_listen');
      }
    }
  }

  /// Latches a Stage 2 range-point match and ends the listen window early.
  bool _tryAcceptRangeMatch({required String source}) {
    if (_listenCaptureResolved || _rangeMatchAccepted) {
      return false;
    }
    if (_uiPhase != AssistUiPhase.listening &&
        _uiPhase != AssistUiPhase.processing) {
      return false;
    }

    _listenCaptureResolved = true;
    _rangeMatchAccepted = true;
    _disablePitchAnalysis();

    if (kDebugMode) {
      debugPrint(
        'AssistDiag RANGE_MATCH_LATCH point=${_currentRangePoint?.name} '
        'source=$source',
      );
    }

    if (_uiPhase == AssistUiPhase.listening) {
      _setPhase(AssistUiPhase.processing);
    }
    _closeWindow();
    return true;
  }

  void _startListenProgress(int generation) {
    _stopListenProgress();
    _listenProgress = 0;
    final started = DateTime.now();
    final totalMs = timing.listenDuration.inMilliseconds;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isActive(generation) || _uiPhase != AssistUiPhase.listening) {
        _stopListenProgress();
        return;
      }
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      _listenProgress = totalMs <= 0
          ? 1.0
          : (elapsed / totalMs).clamp(0.0, 1.0);
      notifyListeners();
    });
  }

  void _stopListenProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _awaitPhase(Duration duration, int generation) async {
    if (duration <= Duration.zero) {
      return;
    }
    await _openWindow(duration);
  }

  Future<void> _openWindow(Duration duration) {
    _closeWindow();
    final window = Completer<void>();
    _windowCompleter = window;

    final customWait = _wait;
    if (customWait != null) {
      unawaited(
        customWait(duration).then((_) {
          if (!window.isCompleted) {
            window.complete();
          }
        }),
      );
    } else {
      _windowTimer = Timer(duration, () {
        if (!window.isCompleted) {
          window.complete();
        }
      });
    }

    return window.future;
  }

  void _closeWindow() {
    _windowTimer?.cancel();
    _windowTimer = null;
    final window = _windowCompleter;
    _windowCompleter = null;
    if (window != null && !window.isCompleted) {
      window.complete();
    }
  }

  Future<void> _playReferenceForPitch(Pitch pitch) async {
    final asset = AudioAssets.sampleFor(pitch);
    if (asset == null) {
      throw AudioServiceException('No tanpura sample is available for Sa.');
    }
    await _audioService.load(asset);
    // Always start (or restart) after an explicit pause before completion
    // speech. Do not skip play when a prior sample was already running.
    await _audioService.play();
  }

  Future<void> _resetToIntro() async {
    _stopListenProgress();
    _disablePitchAnalysis();
    _isSessionActive = false;
    _clearListenCapture();
    _clearStage2State();
    _recoveryMode = AssistRecoveryMode.normal;
    _uiPhase = AssistUiPhase.intro;
    _currentRound = 0;
    _listenProgress = 0;
    _stage1FailureCount = 0;
    _rangePointFailureCount = 0;
    _assistedAttempts = 0;
    _countdownValue = null;
    _stage1GuidedDemoPending = false;
    _referencePitch = initialReferencePitch;
    await _readingsSubscription?.cancel();
    _readingsSubscription = null;
    await _safeStopDetection();
    await _safeStopReferenceSound();
    await _safePauseAudio();
    _candidateFinder.reset();
    _pitchAdjuster.reset();
    _closeWindow();
  }

  void _onDetectionError(Object error) {
    _errorMessage = "That's okay. Let's try that once more.";
    notifyListeners();
  }

  Future<void> _safePauseAudio() async {
    try {
      await _audioService.pause();
    } catch (_) {}
  }

  Future<void> _safeStopReferenceSound() async {
    try {
      await _referenceSoundGenerator.stop();
    } catch (_) {}
  }

  Future<void> _safeStopDetection() async {
    try {
      if (_detectionService.isListening) {
        await _detectionService.stop();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _isDisposed = true;
    _sessionGeneration += 1;
    _closeWindow();
    _stopListenProgress();
    unawaited(_readingsSubscription?.cancel());
    unawaited(_detectionService.dispose());
    unawaited(_audioService.dispose());
    if (_ownsReferenceSoundGenerator) {
      unawaited(_referenceSoundGenerator.dispose());
    } else {
      unawaited(_referenceSoundGenerator.stop());
    }
    super.dispose();
  }
}
