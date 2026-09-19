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

export 'package:harmony/pitch/assist_range_targets.dart';
export 'package:harmony/state/assist_candidate_range_result.dart';
export 'package:harmony/state/assist_mode_phase.dart';

/// Orchestrates Assist Mode as Stage 1 (find starting Shruti) then Stage 2
/// (guided Lower Sa → Pa → Upper Sa range check).
///
/// Tanpura playback and pitch analysis never overlap. Analysis runs only in
/// [AssistUiPhase.listening], after playback has stopped and settled.
/// Stage 2 range references use [ReferenceSoundGenerator]; Stage 1 keeps the
/// existing Tanpura [AudioService] path.
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

  /// Starting Sa pitch class for Stage 1 round 1.
  final Pitch initialReferencePitch;

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
  bool _isVerifying = false;

  /// Whether the first stable voice pitch has seeded the initial Shruti candidate.
  bool _didApplyInitialShrutiCandidate = false;
  String? _errorMessage;

  AssistUiPhase _uiPhase = AssistUiPhase.intro;
  AssistStage _stage = AssistStage.findingStart;
  int _currentRound = 0;
  Pitch _referencePitch = Pitch.defaultPitch;
  double _listenProgress = 0;

  /// Stage 1 result locked when verification succeeds.
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

  /// Results for each candidate tested in this Stage 2 session.
  final List<AssistCandidateRangeResult> _testedCandidates =
      <AssistCandidateRangeResult>[];

  /// Mutable result for the candidate currently under test.
  AssistCandidateRangeResult? _activeCandidateResult;

  /// Last candidate the user marked Upper Sa as comfortable.
  Pitch? _lastComfortableShruti;

  /// Candidate where Upper Sa felt strained (upper boundary), if any.
  Pitch? _currentBoundaryShruti;

  /// Latched successful capture for the current Stage 1 listen window.
  StablePitchCandidate? _acceptedListenCandidate;
  bool _listenCaptureResolved = false;

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

  /// True while confirming a converged candidate with another listen cycle.
  bool get isVerifying => _isVerifying;

  /// True only while pitch readings are accepted for analysis.
  bool get isPitchAnalysisEnabled => _pitchAnalysisEnabled;

  /// True while the mic is capturing and analysis is enabled.
  bool get isListeningForVoice =>
      _pitchAnalysisEnabled &&
      _detectionService.isListening &&
      _uiPhase == AssistUiPhase.listening;

  bool get isReferencePlaying =>
      _audioService.isPlaying || _referenceSoundGenerator.isPlaying;

  /// Starts round 1 from the intro.
  Future<void> startSession() async {
    if (_isBusy || _isSessionActive) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    _isVerifying = false;
    _currentRound = 0;
    _listenProgress = 0;
    _clearListenCapture();
    _candidateFinder.reset();
    _pitchAdjuster.reset();
    _clearStage2State();
    _didApplyInitialShrutiCandidate = false;
    _referencePitch = initialReferencePitch;
    _pitchAdjuster.start(frequencyHzForPitch(initialReferencePitch));
    notifyListeners();

    final generation = ++_sessionGeneration;

    try {
      await _prepareAudioSession();
      _isSessionActive = true;
    } catch (_) {
      _errorMessage = 'Failed to start Assist Mode.';
      _isSessionActive = false;
      _uiPhase = AssistUiPhase.intro;
      return;
    } finally {
      _isBusy = false;
      notifyListeners();
    }

    await _runRoundLoop(generation);
  }

  /// Leaves Assist Mode and returns to the intro.
  Future<void> stopSession() async {
    if (_isDisposed) {
      return;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    _sessionGeneration += 1;
    await _resetToIntro();

    _isBusy = false;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Retries the current round after insufficient singing.
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

    // Bootstrap a new search the same way [startSession] does. Smart Shruti
    // start remains available because [_didApplyInitialShrutiCandidate] was
    // cleared in [_resetToIntro].
    _isVerifying = false;
    _currentRound = 0;
    _listenProgress = 0;
    _clearListenCapture();
    _candidateFinder.reset();
    _pitchAdjuster.reset();
    _clearStage2State();
    _didApplyInitialShrutiCandidate = false;
    _referencePitch = initialReferencePitch;
    _pitchAdjuster.start(frequencyHzForPitch(initialReferencePitch));

    final generation = ++_sessionGeneration;

    try {
      await _prepareAudioSession();
      _isSessionActive = true;
    } catch (_) {
      _errorMessage = 'Failed to start Assist Mode.';
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

    _currentRangePoint = AssistRangePoint.pa;
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
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

  /// Lower Sa was too low — reject candidate and explore the next higher Shruti.
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
    result?.lowerSaAudible = false;

    // Leave awaiting immediately so a second tap cannot double-advance.
    _setPhase(AssistUiPhase.exploringNextShruti);
    _isBusy = false;
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
        'AssistDiag LOWER_TOO_LOW candidate=${_currentCandidate?.label} '
        '→ explore next higher',
      );
    }

    await _moveToNextCandidateOrFinish(
      generation,
      alreadyShowingExploringNext: true,
    );
  }

  /// Upper Sa felt comfortable — explore the next higher Shruti.
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

    // Leave awaiting immediately so a second tap cannot double-advance.
    _setPhase(AssistUiPhase.exploringNextShruti);
    _isBusy = false;
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
        'AssistDiag UPPER_COMFORTABLE candidate=${current?.label} '
        '→ lastComfortable=${_lastComfortableShruti?.label} '
        '→ explore next higher',
      );
    }

    await _moveToNextCandidateOrFinish(
      generation,
      alreadyShowingExploringNext: true,
    );
  }

  /// Upper Sa felt strained — stop upward exploration at the boundary.
  ///
  /// The strained candidate is never recommended. Final Shruti is the last
  /// candidate marked comfortable, or [AssistUiPhase.rangeUnresolved] when
  /// none exists.
  Future<void> reportUpperSaStrained() async {
    if (_isBusy ||
        _isDisposed ||
        _uiPhase != AssistUiPhase.awaitingUpperComfort ||
        _stage != AssistStage.exploringRange) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    final result = _activeCandidateResult;
    final current = _currentCandidate;
    result?.upperSaComfortable = false;
    _currentBoundaryShruti = current;

    if (kDebugMode) {
      debugPrint(
        'AssistDiag UPPER_STRAINED candidate=${current?.label} '
        'lastComfortable=${_lastComfortableShruti?.label} '
        '→ ${_lastComfortableShruti == null ? "unresolved" : "boundary"}',
      );
    }

    if (_lastComfortableShruti == null) {
      _setPhase(AssistUiPhase.rangeUnresolved);
    } else {
      _setPhase(AssistUiPhase.rangeBoundaryReached);
    }
    _isBusy = false;
    notifyListeners();
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
      // Should not happen; strained-without-prior goes to rangeUnresolved.
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
          _stage == AssistStage.exploringRange) {
        return;
      }
    }
  }

  /// Runs one full play → settle → listen → process cycle.
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

    // 1) PLAY — tanpura on, analysis off.
    _setPhase(
      _isVerifying ? AssistUiPhase.verifying : AssistUiPhase.playingReference,
    );
    _disablePitchAnalysis();
    await _safeStopDetection();
    try {
      await _playReferenceForPitch(_referencePitch);
    } on AudioServiceException catch (error) {
      _errorMessage = error.message;
      await _resetToIntro();
      notifyListeners();
      return false;
    }

    await _awaitPhase(timing.referencePlayDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }

    // 2) STOP tanpura + settle — analysis still off.
    _setPhase(AssistUiPhase.preparingToListen);
    await _safePauseAudio();
    _disablePitchAnalysis();
    await _safeStopDetection();

    await _awaitPhase(timing.settlingDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }

    // 3) LISTEN — analysis on only now.
    _candidateFinder.reset();
    _clearListenCapture();
    _rawF0LogCounter = 0;
    _setPhase(AssistUiPhase.listening);
    try {
      await _startPitchAnalysis();
    } on PitchDetectionException catch (error) {
      _errorMessage = error.message;
      _failListenCapture(reason: 'pitch_detection_start_failed');
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = 'Failed to start listening.';
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

    // 4) END LISTENING — leave listening/failure eligibility before stopping
    // audio. An already-accepted candidate must win over the listen timeout.
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

    _applyInitialShrutiCandidateIfNeeded(observation);

    final previousPitch = _referencePitch;
    final previousHz =
        _pitchAdjuster.referenceFrequencyHz ??
        frequencyHzForPitch(_referencePitch);
    final adjustment = _pitchAdjuster.observe(observation.frequencyHz);
    _logCycleDecision(
      previousPitch: previousPitch,
      previousHz: previousHz,
      observation: observation,
      adjustment: adjustment,
    );

    switch (adjustment.kind) {
      case ReferenceMatchKind.rejected:
        _setPhase(AssistUiPhase.retry);
        if (kDebugMode) {
          debugPrint(
            'AssistDiag CONTROLLER_FAILURE reason=observation_rejected',
          );
          debugPrint('AssistDiag FINAL_RESULT kind=rejected');
        }
        notifyListeners();
        return true;

      case ReferenceMatchKind.adjusted:
        _isVerifying = false;
        _syncReferencePitch(adjustment.referenceFrequencyHz);
        if (kDebugMode) {
          debugPrint(
            'AssistDiag adjusted '
            '${previousPitch.label} → ${_referencePitch.label} '
            '(${previousHz.toStringAsFixed(1)} → '
            '${adjustment.referenceFrequencyHz.toStringAsFixed(1)} Hz)',
          );
          debugPrint(
            'AssistDiag FINAL_RESULT kind=adjusted '
            'uiReferencePitch=${_referencePitch.label}',
          );
        }
        notifyListeners();
        _setPhase(AssistUiPhase.showingTransition);
        await _awaitPhase(timing.transitionDuration, generation);
        return _isActive(generation);

      case ReferenceMatchKind.converged:
        return _handleConverged(generation, adjustment);

      case ReferenceMatchKind.atBoundary:
        // At the supported range edge but still far from the user is NOT a
        // successful Shruti match — do not confirm the stuck reference.
        final distance = adjustment.centsFromReference?.abs();
        final closeEnough =
            distance != null &&
            distance <= _pitchAdjuster.convergenceToleranceCents;
        if (kDebugMode) {
          debugPrint(
            'AssistDiag atBoundary closeEnough=$closeEnough '
            'distanceCents=${distance?.toStringAsFixed(1) ?? "n/a"} '
            'stuckRef=${_referencePitch.label}',
          );
        }
        if (closeEnough) {
          return _handleConverged(generation, adjustment);
        }
        _setPhase(AssistUiPhase.retry);
        if (kDebugMode) {
          debugPrint(
            'AssistDiag CONTROLLER_FAILURE reason=at_boundary_far_from_user',
          );
          debugPrint('AssistDiag FINAL_RESULT kind=atBoundary');
        }
        notifyListeners();
        return true;
    }
  }

  /// Close enough (or clamped at range edge): verify once, then enter Stage 2.
  Future<bool> _handleConverged(
    int generation,
    ReferencePitchAdjustment adjustment,
  ) async {
    _syncReferencePitch(adjustment.referenceFrequencyHz);

    if (_isVerifying) {
      if (kDebugMode) {
        debugPrint(
          'AssistDiag STAGE1_CONFIRMED startingShruti=${_referencePitch.label} '
          '→ entering Stage 2 range check',
        );
      }
      _isVerifying = false;
      _stopListenProgress();
      _closeWindow();
      return _beginStage2(generation);
    }

    if (kDebugMode) {
      debugPrint(
        'AssistDiag converged → verification; candidateRef='
        '${_referencePitch.label}',
      );
    }
    _isVerifying = true;
    notifyListeners();
    _setPhase(AssistUiPhase.showingTransition);
    await _awaitPhase(timing.transitionDuration, generation);
    return _isActive(generation);
  }

  /// Locks Stage 1 result and begins the guided 3-point range check.
  Future<bool> _beginStage2(int generation) async {
    _stage = AssistStage.exploringRange;
    _stage1Shruti = _referencePitch;
    _testedCandidates.clear();
    _lastComfortableShruti = null;
    _currentBoundaryShruti = null;
    _prepareCandidate(_referencePitch);

    _setPhase(AssistUiPhase.startingPointFound);
    await _awaitPhase(timing.transitionDuration, generation);
    if (!_isActive(generation)) {
      return false;
    }

    _setPhase(AssistUiPhase.showingTransition);
    await _awaitPhase(timing.transitionDuration, generation);
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
      _uiPhase == AssistUiPhase.awaitingUpperComfort ||
      _uiPhase == AssistUiPhase.rangeBoundaryReached ||
      _uiPhase == AssistUiPhase.rangeUnresolved;

  /// Stage 2: play one range point → settle → listen for a stable match.
  ///
  /// On Lower Sa match: pause for audibility. On Pa match: continue to Upper
  /// Sa. On Upper Sa match: pause for comfort. On no match: retry same point.
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

    // 1) PLAY — synthesized reference on, analysis off. Stage 1 Tanpura path
    // is not used for range targets (frequency is the source of truth).
    _setPhase(AssistUiPhase.playingReference);
    _disablePitchAnalysis();
    await _safeStopDetection();
    await _safePauseAudio();
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
      _errorMessage = error.message;
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

    // 3) LISTEN — match the fixed Hz target without octave folding so Lower
    // Sa and Upper Sa remain distinct.
    _targetMatcher.start(targetHz, foldOctaves: false);
    _clearListenCapture();
    _rangeMatchAccepted = false;
    _rangeVoiceHz = null;
    _rawF0LogCounter = 0;
    _setPhase(AssistUiPhase.listening);
    try {
      await _startPitchAnalysis();
    } on PitchDetectionException catch (error) {
      _errorMessage = error.message;
      _targetMatcher.stop();
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = 'Failed to start listening.';
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

    if (!matched) {
      if (kDebugMode) {
        debugPrint(
          'AssistDiag RANGE_NO_MATCH point=${point.name} '
          'targetHz=${targetHz.toStringAsFixed(1)} — retry same point',
        );
      }
      _setPhase(AssistUiPhase.showingTransition);
      await _awaitPhase(timing.transitionDuration, generation);
      return _isActive(generation);
    }

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
        _setPhase(AssistUiPhase.awaitingLowerAudibility);
        notifyListeners();
        return true;
      case AssistRangePoint.pa:
        result?.paMatched = true;
        _currentRangePoint = AssistRangePoint.upperSa;
        _rangeMatchAccepted = false;
        _rangeVoiceHz = null;
        _setPhase(AssistUiPhase.showingTransition);
        await _awaitPhase(timing.transitionDuration, generation);
        return _isActive(generation);
      case AssistRangePoint.upperSa:
        result?.upperSaMatched = true;
        _setPhase(AssistUiPhase.awaitingUpperComfort);
        notifyListeners();
        return true;
    }
  }

  /// Advances to the next higher Shruti, or finishes when none remain.
  Future<void> _moveToNextCandidateOrFinish(
    int generation, {
    bool alreadyShowingExploringNext = false,
  }) async {
    final current = _currentCandidate;
    if (current == null) {
      return;
    }

    final next = nextHigherSupportedShruti(current);
    if (next == null) {
      // Top of supported range — recommend last comfortable only (usually
      // the current candidate, just marked comfortable by the caller).
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
        'AssistDiag EXPLORE_NEXT candidate=${next.label} '
        'from=${current.label}',
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
  Future<void> _completeRangeTest(Pitch candidate) async {
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

    _setPhase(AssistUiPhase.completed);
    try {
      await _playReferenceForPitch(candidate);
    } on AudioServiceException catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = 'Failed to play the tanpura sample.';
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
    _targetMatcher.stop();
  }

  void _syncReferencePitch(double referenceHz) {
    final nextPitch = noteFromFrequency(referenceHz);
    if (nextPitch != null) {
      _referencePitch = nextPitch;
    }
  }

  /// Seeds the reference from the first stable voice pitch instead of walking
  /// chromatically from the hardcoded session start (typically C).
  ///
  /// Does not confirm Shruti — only replaces the initial search candidate.
  /// Subsequent observe / verify / adjust behavior is unchanged.
  void _applyInitialShrutiCandidateIfNeeded(StablePitchCandidate observation) {
    if (_didApplyInitialShrutiCandidate || _isVerifying) {
      return;
    }
    _didApplyInitialShrutiCandidate = true;

    final initial = nearestSupportedShruti(observation.frequencyHz);
    if (initial == null) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'AssistDiag detectedVoiceHz='
        '${observation.frequencyHz.toStringAsFixed(1)}',
      );
      debugPrint('AssistDiag detectedVoiceNote=${observation.pitch.label}');
      debugPrint('AssistDiag initialShrutiCandidate=${initial.pitch.label}');
      debugPrint(
        'AssistDiag initialShrutiCandidateHz='
        '${initial.frequencyHz.toStringAsFixed(1)}',
      );
    }

    _referencePitch = initial.pitch;
    _pitchAdjuster.start(initial.frequencyHz);
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
    if (kDebugMode) {
      debugPrint('AssistDiag CONTROLLER_FAILURE reason=$reason');
      debugPrint('AssistDiag FINAL_RESULT kind=failure reason=$reason');
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
      if (reading.hasPitch && reading.frequencyHz != null) {
        _rangeVoiceHz = reading.frequencyHz;
        notifyListeners();
      }
      _targetMatcher.add(reading);
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

  void _logCycleDecision({
    required Pitch previousPitch,
    required double previousHz,
    required StablePitchCandidate observation,
    required ReferencePitchAdjustment adjustment,
  }) {
    if (!kDebugMode) {
      return;
    }
    final adjNote = noteFromFrequency(adjustment.referenceFrequencyHz)?.label;
    debugPrint(
      'AssistDiag cycle=$_currentRound '
      'verifying=$_isVerifying '
      'refBefore=${previousPitch.label}@${previousHz.toStringAsFixed(1)}Hz '
      'stableCandidate=${observation.pitch.label}@'
      '${observation.frequencyHz.toStringAsFixed(1)}Hz '
      '(n=${observation.stableSampleCount}) '
      'cents=${adjustment.centsFromReference?.toStringAsFixed(1) ?? "n/a"} '
      'kind=${adjustment.kind.name} '
      'refAfter=${adjNote ?? "?"}@'
      '${adjustment.referenceFrequencyHz.toStringAsFixed(1)}Hz '
      'uiReferencePitch=${_referencePitch.label}',
    );
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
    if (!_audioService.isPlaying) {
      await _audioService.play();
    }
  }

  Future<void> _resetToIntro() async {
    _stopListenProgress();
    _disablePitchAnalysis();
    _isSessionActive = false;
    _isVerifying = false;
    _clearListenCapture();
    _clearStage2State();
    _uiPhase = AssistUiPhase.intro;
    _currentRound = 0;
    _listenProgress = 0;
    _didApplyInitialShrutiCandidate = false;
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
    _errorMessage = error is PitchDetectionException
        ? error.message
        : 'Pitch detection failed.';
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
