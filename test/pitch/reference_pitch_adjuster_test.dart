import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/reference_pitch_adjuster.dart';

void main() {
  late ReferencePitchAdjuster adjuster;

  setUp(() {
    adjuster = ReferencePitchAdjuster(
      convergenceToleranceCents: 50,
      hysteresisCents: 20,
      maxStepCents: 100,
    );
  });

  double shiftHz(double hz, double cents) {
    return hz * math.pow(2, cents / 1200).toDouble();
  }

  test('user pitch equal to reference is converged', () {
    final ref = frequencyHzForPitch(Pitch.d);
    adjuster.start(ref);

    final result = adjuster.observe(ref);

    expect(result.kind, ReferenceMatchKind.converged);
    expect(result.didAdjust, isFalse);
    expect(result.isConverged, isTrue);
    expect(result.referenceFrequencyHz, closeTo(ref, 0.01));
  });

  test('user pitch meaningfully above reference moves reference up', () {
    final ref = frequencyHzForPitch(Pitch.c);
    final user = shiftHz(ref, 80);
    adjuster.start(ref);

    final result = adjuster.observe(user);

    expect(result.kind, ReferenceMatchKind.adjusted);
    expect(result.didAdjust, isTrue);
    expect(result.isConverged, isFalse);
    expect(result.referenceFrequencyHz, closeTo(user, 0.05));
  });

  test('user pitch meaningfully below reference moves reference down', () {
    final ref = frequencyHzForPitch(Pitch.e);
    final user = shiftHz(ref, -80);
    adjuster.start(ref);

    final result = adjuster.observe(user);

    expect(result.kind, ReferenceMatchKind.adjusted);
    expect(result.referenceFrequencyHz, closeTo(user, 0.05));
  });

  test('within tolerance does not adjust', () {
    final ref = frequencyHzForPitch(Pitch.a);
    adjuster.start(ref);

    final slight = shiftHz(ref, 25);
    final result = adjuster.observe(slight);

    expect(result.kind, ReferenceMatchKind.converged);
    expect(result.didAdjust, isFalse);
    expect(result.referenceFrequencyHz, closeTo(ref, 0.01));
  });

  test('tiny differences after convergence stay converged via hysteresis', () {
    final ref = frequencyHzForPitch(Pitch.d);
    adjuster.start(ref);

    expect(adjuster.observe(ref).isConverged, isTrue);

    // 60 cents is outside 50 tolerance but inside 50+20 hysteresis band.
    final wobble = shiftHz(ref, 60);
    final result = adjuster.observe(wobble);

    expect(result.kind, ReferenceMatchKind.converged);
    expect(result.didAdjust, isFalse);
    expect(result.referenceFrequencyHz, closeTo(ref, 0.01));
  });

  test('large difference moves in a controlled max step', () {
    final ref = frequencyHzForPitch(Pitch.c);
    final user = shiftHz(ref, 400);
    adjuster.start(ref);

    final result = adjuster.observe(user);

    expect(result.didAdjust, isTrue);
    final moved = centsBetweenFrequencies(result.referenceFrequencyHz, ref)!;
    expect(moved, closeTo(100, 0.1));
  });

  test('invalid user frequency is rejected', () {
    final ref = frequencyHzForPitch(Pitch.g);
    adjuster.start(ref);

    expect(adjuster.observe(0).kind, ReferenceMatchKind.rejected);
    expect(adjuster.observe(-10).kind, ReferenceMatchKind.rejected);
    expect(adjuster.observe(double.nan).kind, ReferenceMatchKind.rejected);
    expect(adjuster.referenceFrequencyHz, closeTo(ref, 0.01));
  });

  test('repeated observations converge toward the user pitch', () {
    final target = frequencyHzForPitch(Pitch.e);
    var ref = frequencyHzForPitch(Pitch.c);
    adjuster.start(ref);

    ReferencePitchAdjustment? last;
    for (var i = 0; i < 12; i++) {
      last = adjuster.observe(target);
      ref = last.referenceFrequencyHz;
      if (last.isConverged) {
        break;
      }
    }

    expect(last!.isConverged, isTrue);
    final remaining = centsBetweenFrequencies(target, ref)!.abs();
    expect(remaining, lessThanOrEqualTo(50));
  });

  test(
    'octave-apart user pitch folds and converges without climbing forever',
    () {
      final ref = frequencyHzForPitch(Pitch.e, octave: 3);
      final userOctaveUp = frequencyHzForPitch(Pitch.e, octave: 4);
      adjuster.start(ref);

      final result = adjuster.observe(userOctaveUp);

      expect(result.kind, ReferenceMatchKind.converged);
      expect(result.didAdjust, isFalse);
      expect(adjuster.referenceFrequencyHz, closeTo(ref, 0.01));
    },
  );

  test(
    'in-range A3 against C3 adjusts upward instead of atBoundary',
    () {
      final ref = frequencyHzForPitch(Pitch.c);
      final userA = frequencyHzForPitch(Pitch.a);
      adjuster.start(ref);

      final result = adjuster.observe(userA);

      expect(result.kind, ReferenceMatchKind.adjusted);
      expect(result.didAdjust, isTrue);
      expect(result.centsFromReference, greaterThan(0));
      expect(result.referenceFrequencyHz, greaterThan(ref));
      expect(result.referenceFrequencyHz, lessThanOrEqualTo(userA));
    },
  );

  test('reference cannot climb above supported maximum', () {
    final maxHz = frequencyHzForPitch(Pitch.b);
    adjuster.start(maxHz);

    final above = shiftHz(maxHz, 200);
    final result = adjuster.observe(above);

    expect(result.kind, ReferenceMatchKind.atBoundary);
    expect(result.didAdjust, isFalse);
    expect(result.referenceFrequencyHz, closeTo(maxHz, 0.01));
  });

  test('reference cannot descend below supported minimum', () {
    final minHz = frequencyHzForPitch(Pitch.c);
    adjuster.start(minHz);

    final below = shiftHz(minHz, -200);
    final result = adjuster.observe(below);

    expect(result.kind, ReferenceMatchKind.atBoundary);
    expect(result.didAdjust, isFalse);
    expect(result.referenceFrequencyHz, closeTo(minHz, 0.01));
  });

  test('reset clears the reference and convergence flag', () {
    adjuster.start(frequencyHzForPitch(Pitch.f));
    adjuster.observe(frequencyHzForPitch(Pitch.f));
    expect(adjuster.isConverged, isTrue);

    adjuster.reset();

    expect(adjuster.hasReference, isFalse);
    expect(adjuster.isConverged, isFalse);
  });

  test('observe before start throws', () {
    expect(() => adjuster.observe(220), throwsStateError);
  });
}
