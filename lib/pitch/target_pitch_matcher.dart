import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';

/// Whether the singer is successfully matching a target frequency.
enum TargetPitchMatchState {
  /// No target is active.
  waiting,

  /// Target is active; waiting for a stable sung pitch to evaluate.
  listening,

  /// Stable pitch is available and being compared to the target.
  approaching,

  /// Pitch has stayed within tolerance long enough to count as a match.
  matched,

  /// A prior match was lost after the singer moved away from the target.
  lost,
}

/// Determines whether live pitch readings match a target frequency.
///
/// Answers only "is the user matching this target?" — not what their Shruti is.
/// UI-agnostic: feed [PitchReading]s from the existing mic/YIN pipeline.
class TargetPitchMatcher {
  TargetPitchMatcher({
    this.toleranceCents = 50,
    this.samplesToMatch = 6,
    this.samplesToLoseMatch = 3,
    PitchStabilityTracker? stabilityTracker,
  }) : assert(toleranceCents > 0),
       assert(samplesToMatch > 0),
       assert(samplesToLoseMatch > 0),
       _stabilityTracker = stabilityTracker ?? PitchStabilityTracker();

  /// Maximum absolute cents error accepted as "on target".
  final double toleranceCents;

  /// Consecutive in-tolerance samples (while stable) required to match.
  final int samplesToMatch;

  /// Consecutive out-of-tolerance samples (while matched) required to leave
  /// the matched state.
  final int samplesToLoseMatch;

  final PitchStabilityTracker _stabilityTracker;

  TargetPitchMatchState _state = TargetPitchMatchState.waiting;
  double? _targetFrequencyHz;
  double? _centsFromTarget;
  int _inToleranceCount = 0;
  int _outOfToleranceCount = 0;

  TargetPitchMatchState get state => _state;

  /// Active target in Hz, or `null` when [state] is [TargetPitchMatchState.waiting].
  double? get targetFrequencyHz => _targetFrequencyHz;

  /// Signed cents error from the last evaluated (stable) reading.
  ///
  /// Positive means sharp of the target. `null` until a stable pitch is
  /// evaluated against the target.
  double? get centsFromTarget => _centsFromTarget;

  bool get isMatched => _state == TargetPitchMatchState.matched;

  /// Begins a matching trial against [targetFrequencyHz].
  void start(double targetFrequencyHz) {
    assert(targetFrequencyHz > 0);
    _targetFrequencyHz = targetFrequencyHz;
    _resetProgress();
    _state = TargetPitchMatchState.listening;
  }

  /// Ends the trial and returns to [TargetPitchMatchState.waiting].
  void stop() {
    _targetFrequencyHz = null;
    _resetProgress();
    _state = TargetPitchMatchState.waiting;
  }

  /// Clears match progress while keeping the current target (if any).
  ///
  /// Returns to [TargetPitchMatchState.listening] when a target is active,
  /// otherwise [TargetPitchMatchState.waiting].
  void reset() {
    final target = _targetFrequencyHz;
    _resetProgress();
    if (target == null) {
      _state = TargetPitchMatchState.waiting;
      return;
    }
    _targetFrequencyHz = target;
    _state = TargetPitchMatchState.listening;
  }

  /// Processes one reading from the pitch pipeline.
  ///
  /// Silence and invalid/unvoiced readings are ignored so brief detection
  /// dropouts do not reset the trial.
  void add(PitchReading reading) {
    if (_state == TargetPitchMatchState.waiting) {
      return;
    }

    final target = _targetFrequencyHz;
    if (target == null) {
      return;
    }

    final frequency = reading.frequencyHz;
    if (!reading.hasPitch || frequency == null || frequency <= 0) {
      return;
    }

    final note = noteFromFrequency(frequency);
    if (note == null) {
      return;
    }

    _stabilityTracker.add(note);

    if (!_stabilityTracker.isStable) {
      _inToleranceCount = 0;
      _outOfToleranceCount = 0;
      _centsFromTarget = null;
      if (_state == TargetPitchMatchState.matched) {
        // Stability was lost after mismatches accumulated; treat as lost match.
        _state = TargetPitchMatchState.lost;
      } else if (_state == TargetPitchMatchState.approaching) {
        _state = TargetPitchMatchState.listening;
      }
      // listening / lost stay as-is while unstable.
      return;
    }

    final cents = centsBetweenFrequencies(frequency, target);
    if (cents == null) {
      return;
    }

    _centsFromTarget = cents;
    final withinTolerance = cents.abs() <= toleranceCents;

    switch (_state) {
      case TargetPitchMatchState.waiting:
        break;
      case TargetPitchMatchState.listening:
      case TargetPitchMatchState.lost:
      case TargetPitchMatchState.approaching:
        _updateApproachOrMatch(withinTolerance);
        break;
      case TargetPitchMatchState.matched:
        _updateWhileMatched(withinTolerance);
        break;
    }
  }

  void _updateApproachOrMatch(bool withinTolerance) {
    if (withinTolerance) {
      _outOfToleranceCount = 0;
      _inToleranceCount += 1;
      if (_inToleranceCount >= samplesToMatch) {
        _state = TargetPitchMatchState.matched;
        _outOfToleranceCount = 0;
      } else {
        _state = TargetPitchMatchState.approaching;
      }
      return;
    }

    _inToleranceCount = 0;
    _outOfToleranceCount = 0;
    _state = TargetPitchMatchState.approaching;
  }

  void _updateWhileMatched(bool withinTolerance) {
    if (withinTolerance) {
      _outOfToleranceCount = 0;
      return;
    }

    _outOfToleranceCount += 1;
    if (_outOfToleranceCount >= samplesToLoseMatch) {
      _inToleranceCount = 0;
      _outOfToleranceCount = 0;
      _state = TargetPitchMatchState.lost;
    }
  }

  void _resetProgress() {
    _stabilityTracker.reset();
    _centsFromTarget = null;
    _inToleranceCount = 0;
    _outOfToleranceCount = 0;
  }
}
