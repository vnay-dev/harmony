import 'package:harmony/models/pitch.dart';

/// Tracks whether recent valid pitch detections are consistent enough to
/// treat the current observation as stable.
///
/// Only valid pitch-class samples should be fed via [add]. Invalid or missing
/// detections are ignored by the caller so brief dropouts do not by themselves
/// clear stability.
class PitchStabilityTracker {
  PitchStabilityTracker({
    this.samplesToBecomeStable = 6,
    this.mismatchesToBecomeUnstable = 3,
  }) : assert(samplesToBecomeStable > 0),
       assert(mismatchesToBecomeUnstable > 0);

  /// Consecutive matching samples required before becoming stable.
  final int samplesToBecomeStable;

  /// Consecutive mismatched samples allowed while stable before clearing.
  final int mismatchesToBecomeUnstable;

  Pitch? _candidatePitch;
  int _candidateCount = 0;
  Pitch? _stablePitch;
  int _mismatchCount = 0;
  bool _isStable = false;

  /// Whether the recent valid detections are currently considered stable.
  bool get isStable => _isStable;

  /// Pitch that earned the current stable state, if any.
  Pitch? get stablePitch => _isStable ? _stablePitch : null;

  /// Clears all history. Call when listening starts or stops.
  void reset() {
    _candidatePitch = null;
    _candidateCount = 0;
    _stablePitch = null;
    _mismatchCount = 0;
    _isStable = false;
  }

  /// Records one valid pitch-class observation and updates stability.
  void add(Pitch pitch) {
    if (_isStable) {
      _handleWhileStable(pitch);
    } else {
      _handleWhileUnstable(pitch);
    }
  }

  void _handleWhileStable(Pitch pitch) {
    if (pitch == _stablePitch) {
      _mismatchCount = 0;
      return;
    }

    // Brief noise / natural wobble: stay stable until mismatches accumulate.
    _mismatchCount += 1;
    if (_mismatchCount < mismatchesToBecomeUnstable) {
      return;
    }

    _isStable = false;
    _stablePitch = null;
    _mismatchCount = 0;
    _candidatePitch = pitch;
    _candidateCount = 1;
  }

  void _handleWhileUnstable(Pitch pitch) {
    if (pitch == _candidatePitch) {
      _candidateCount += 1;
    } else {
      _candidatePitch = pitch;
      _candidateCount = 1;
    }

    if (_candidateCount >= samplesToBecomeStable) {
      _isStable = true;
      _stablePitch = _candidatePitch;
      _mismatchCount = 0;
    }
  }
}
