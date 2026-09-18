import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/audio/audio_service.dart';
import 'package:harmony/audio/audio_session_config.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/nearest_supported_shruti.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/reference_pitch_adjuster.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/state/assist_mode_phase.dart';

export 'package:harmony/state/assist_mode_phase.dart';

/// Orchestrates Assist Mode V2 as discrete Listen → Sing → Adjust rounds.
///
/// Tanpura playback and pitch analysis never overlap. Analysis runs only in
/// [AssistUiPhase.listening], after playback has stopped and settled.
///
/// Completion requires an explicit cents-based convergence check and a
/// successful verification listen — not a round counter.
class AssistModeController extends ChangeNotifier {
  AssistModeController({
    required PitchDetectionService detectionService,
    required AudioService audioService,
    StablePitchCandidateFinder? candidateFinder,
    ReferencePitchAdjuster? pitchAdjuster,
    this.timing = const AssistTimingConfig(),
    this.initialReferencePitch = Pitch.defaultPitch,
    Future<void> Function(Duration duration)? wait,
    Future<void> Function()? prepareAudioSession,
  }) : _detectionService = detectionService,
       _audioService = audioService,
       _candidateFinder = candidateFinder ?? StablePitchCandidateFinder(),
       _pitchAdjuster = pitchAdjuster ?? ReferencePitchAdjuster(),
       _wait = wait,
       _prepareAudioSession =
           prepareAudioSession ?? ensurePlayAndRecordAudioSession;

  /// Durations for play / settle / listen / transition.
  final AssistTimingConfig timing;

  /// Starting Sa pitch class for round 1.
  final Pitch initialReferencePitch;

  final PitchDetectionService _detectionService;
  final AudioService _audioService;
  final StablePitchCandidateFinder _candidateFinder;
  final ReferencePitchAdjuster _pitchAdjuster;
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
  int _currentRound = 0;
  Pitch _referencePitch = Pitch.defaultPitch;
  double _listenProgress = 0;

  /// Latched successful capture for the current listen window.
  ///
  /// Once set, timeout/failure paths must not overwrite it.
  StablePitchCandidate? _acceptedListenCandidate;
  bool _listenCaptureResolved = false;

  bool get isBusy => _isBusy;
  bool get isSessionActive => _isSessionActive;
  String? get errorMessage => _errorMessage;

  /// Current UI phase.
  AssistUiPhase get uiPhase => _uiPhase;

  /// 1-based round number while a session is active.
  int get currentRound => _currentRound;

  /// Progress through the listening window, from `0` to `1`.
  double get listenProgress => _listenProgress;

  /// Current reference Sa pitch class.
  Pitch get referencePitch => _referencePitch;

  /// Current reference frequency from the adjuster, if started.
  double? get referenceFrequencyHz => _pitchAdjuster.referenceFrequencyHz;

  /// True while confirming a converged candidate with another listen cycle.
  bool get isVerifying => _isVerifying;

  /// True only while pitch readings are accepted for analysis.
  bool get isPitchAnalysisEnabled => _pitchAnalysisEnabled;

  /// True while the mic is capturing and analysis is enabled.
  bool get isListeningForVoice =>
      _pitchAnalysisEnabled &&
      _detectionService.isListening &&
      _uiPhase == AssistUiPhase.listening;

  bool get isReferencePlaying => _audioService.isPlaying;

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
  /// Only valid from [AssistUiPhase.completed]. Stops confirmed playback,
  /// clears Assist session state, and begins the normal finding flow again.
  /// Does not change Default Mode's selected Shruti.
  Future<void> tryAgain() async {
    if (_isBusy || _isDisposed || _uiPhase != AssistUiPhase.completed) {
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
          _uiPhase == AssistUiPhase.intro) {
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

  /// Close enough (or clamped at range edge): verify once, then complete.
  Future<bool> _handleConverged(
    int generation,
    ReferencePitchAdjustment adjustment,
  ) async {
    _syncReferencePitch(adjustment.referenceFrequencyHz);

    if (_isVerifying) {
      if (kDebugMode) {
        debugPrint(
          'AssistDiag COMPLETE confirmedShruti=${_referencePitch.label} '
          'confirmedHz='
          '${_pitchAdjuster.referenceFrequencyHz?.toStringAsFixed(1) ?? "?"} '
          'source=AssistModeController._referencePitch '
          '(synced from ReferencePitchAdjuster.referenceFrequencyHz)',
        );
      }
      _isVerifying = false;
      _stopListenProgress();
      _closeWindow();
      _setPhase(AssistUiPhase.completed);
      // Keep the confirmed Shruti audible on the completion screen.
      try {
        await _playReferenceForPitch(_referencePitch);
      } on AudioServiceException catch (error) {
        _errorMessage = error.message;
      } catch (_) {
        _errorMessage = 'Failed to play the tanpura sample.';
      }
      notifyListeners();
      return true;
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
    if (_listenCaptureResolved && _acceptedListenCandidate != null) {
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
          'ref=${_referencePitch.label}',
        );
      }
    }
    _candidateFinder.add(reading);
    if (_candidateFinder.hasCandidate) {
      final candidate = _candidateFinder.result();
      if (candidate != null) {
        _tryAcceptListenCandidate(candidate, source: 'mid_listen');
      }
    }
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
    _uiPhase = AssistUiPhase.intro;
    _currentRound = 0;
    _listenProgress = 0;
    _didApplyInitialShrutiCandidate = false;
    _referencePitch = initialReferencePitch;
    await _readingsSubscription?.cancel();
    _readingsSubscription = null;
    await _safeStopDetection();
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
    super.dispose();
  }
}
