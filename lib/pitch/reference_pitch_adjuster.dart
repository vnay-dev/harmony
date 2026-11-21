import 'dart:math' as math;

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';

/// How one stable user observation relates to the current reference.
enum ReferenceMatchKind {
  /// User pitch was invalid; reference unchanged.
  rejected,

  /// Reference moved toward the user by a bounded step.
  adjusted,

  /// User pitch is within the convergence deadband; do not move the reference.
  converged,

  /// Further movement is blocked by the supported pitch range.
  atBoundary,
}

/// Outcome of one stable-pitch observation against the current reference.
///
/// Does not decide the user's Shruti — only whether the reference moved and
/// whether it is close enough to stop adjusting.
class ReferencePitchAdjustment {
  const ReferencePitchAdjustment({
    required this.referenceFrequencyHz,
    required this.kind,
    this.centsFromReference,
  });

  /// Reference frequency after this observation.
  final double referenceFrequencyHz;

  /// Classification of this observation.
  final ReferenceMatchKind kind;

  /// Signed cents from reference to the (octave-folded) user pitch, if known.
  ///
  /// Positive means the user was sharp of the reference.
  final double? centsFromReference;

  /// Whether the reference moved toward the user.
  bool get didAdjust => kind == ReferenceMatchKind.adjusted;

  /// Whether the reference is close enough to stop adjusting.
  bool get isConverged => kind == ReferenceMatchKind.converged;

  /// Whether the reference cannot move further in the needed direction.
  bool get atBoundary => kind == ReferenceMatchKind.atBoundary;
}

/// Moves a reference pitch toward a user's stable sung pitch in controlled steps.
///
/// Convergence is explicit: when the octave-folded cents distance is within
/// [convergenceToleranceCents], [observe] returns [ReferenceMatchKind.converged]
/// and does not move the reference. Hysteresis widens the stay-converged band
/// so tiny fluctuations do not restart adjustment.
///
/// The reference is clamped to the supported Sa range (C3–B3).
class ReferencePitchAdjuster {
  ReferencePitchAdjuster({
    this.convergenceToleranceCents = 50,
    this.hysteresisCents = 20,
    this.maxStepCents = 100,
    double? minimumReferenceHz,
    double? maximumReferenceHz,
  }) : assert(convergenceToleranceCents > 0),
       assert(hysteresisCents >= 0),
       assert(maxStepCents > 0),
       minimumReferenceHz = minimumReferenceHz ?? frequencyHzForPitch(Pitch.c),
       maximumReferenceHz = maximumReferenceHz ?? frequencyHzForPitch(Pitch.b) {
    assert(this.minimumReferenceHz < this.maximumReferenceHz);
  }

  /// Absolute cents distance at or below which the reference is converged.
  final double convergenceToleranceCents;

  /// Extra cents beyond [convergenceToleranceCents] before leaving convergence.
  ///
  /// Once converged, adjustment resumes only when the error exceeds
  /// tolerance + hysteresis.
  final double hysteresisCents;

  /// Maximum cents the reference may move toward the user in one adjustment.
  final double maxStepCents;

  /// Lowest allowed reference frequency (inclusive).
  final double minimumReferenceHz;

  /// Highest allowed reference frequency (inclusive).
  final double maximumReferenceHz;

  double? _referenceFrequencyHz;
  bool _isConverged = false;

  /// Current reference frequency, or `null` before [start].
  double? get referenceFrequencyHz => _referenceFrequencyHz;

  /// Whether a reference has been established.
  bool get hasReference => _referenceFrequencyHz != null;

  /// Whether the last successful evaluation reported convergence.
  bool get isConverged => _isConverged;

  /// Begins adjustment from an initial reference frequency (Hz).
  void start(double initialReferenceFrequencyHz) {
    assert(initialReferenceFrequencyHz > 0);
    _referenceFrequencyHz = _clamp(initialReferenceFrequencyHz);
    _isConverged = false;
  }

  /// Clears the reference. Call when leaving the adjustment session.
  void reset() {
    _referenceFrequencyHz = null;
    _isConverged = false;
  }

  /// Applies one stable user observation to the reference.
  ///
  /// Invalid frequencies are rejected. Frequencies already inside the supported
  /// Sa range are compared directly. Out-of-range frequencies are folded toward
  /// the reference by octave so a nearby-octave sung note does not force an
  /// unbounded climb.
  ReferencePitchAdjustment observe(double userStableFrequencyHz) {
    final reference = _referenceFrequencyHz;
    if (reference == null) {
      throw StateError('Call start() before observe().');
    }

    if (userStableFrequencyHz <= 0 ||
        userStableFrequencyHz.isNaN ||
        userStableFrequencyHz.isInfinite) {
      return ReferencePitchAdjustment(
        referenceFrequencyHz: reference,
        kind: ReferenceMatchKind.rejected,
      );
    }

    // Frequencies already inside the supported Sa range are compared as-is.
    // Nearest-octave folding (±600¢) would otherwise map A3≈220Hz against C3
    // down to A2≈110Hz, demand a downward move, hit the C minimum, and report
    // atBoundary — discarding a valid in-range sung Sa.
    final comparisonHz =
        userStableFrequencyHz >= minimumReferenceHz &&
            userStableFrequencyHz <= maximumReferenceHz
        ? userStableFrequencyHz
        : foldFrequencyTowardReference(userStableFrequencyHz, reference);
    final cents = centsBetweenFrequencies(comparisonHz, reference);
    if (cents == null) {
      return ReferencePitchAdjustment(
        referenceFrequencyHz: reference,
        kind: ReferenceMatchKind.rejected,
      );
    }

    final absCents = cents.abs();
    final stayConvergedLimit = convergenceToleranceCents + hysteresisCents;

    if (absCents <= convergenceToleranceCents ||
        (_isConverged && absCents <= stayConvergedLimit)) {
      _isConverged = true;
      return ReferencePitchAdjustment(
        referenceFrequencyHz: reference,
        kind: ReferenceMatchKind.converged,
        centsFromReference: cents,
      );
    }

    _isConverged = false;
    final stepCents = cents.clamp(-maxStepCents, maxStepCents);
    final unclamped = reference * math.pow(2, stepCents / 1200).toDouble();
    final next = _clamp(unclamped);

    if ((next - reference).abs() < 1e-9) {
      // Needed direction is blocked by the supported range.
      return ReferencePitchAdjustment(
        referenceFrequencyHz: reference,
        kind: ReferenceMatchKind.atBoundary,
        centsFromReference: cents,
      );
    }

    _referenceFrequencyHz = next;
    return ReferencePitchAdjustment(
      referenceFrequencyHz: next,
      kind: ReferenceMatchKind.adjusted,
      centsFromReference: cents,
    );
  }

  double _clamp(double hz) {
    return hz.clamp(minimumReferenceHz, maximumReferenceHz).toDouble();
  }
}

/// Brings [frequencyHz] within ±600 cents of [referenceHz] by octave steps.
///
/// Keeps pitch-class comparison stable when the singer is in a nearby octave.
double foldFrequencyTowardReference(double frequencyHz, double referenceHz) {
  if (frequencyHz <= 0 ||
      referenceHz <= 0 ||
      frequencyHz.isNaN ||
      referenceHz.isNaN ||
      frequencyHz.isInfinite ||
      referenceHz.isInfinite) {
    return frequencyHz;
  }

  var folded = frequencyHz;
  for (var i = 0; i < 8; i++) {
    final cents = centsBetweenFrequencies(folded, referenceHz);
    if (cents == null) {
      return folded;
    }
    if (cents > 600) {
      folded /= 2;
    } else if (cents < -600) {
      folded *= 2;
    } else {
      return folded;
    }
  }
  return folded;
}
