import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';

void main() {
  const targetHz = 146.83; // D3
  const samplesToBecomeStable = 3;
  const samplesToMatch = 4;

  late TargetPitchMatcher matcher;

  setUp(() {
    matcher = TargetPitchMatcher(
      toleranceCents: 50,
      samplesToMatch: samplesToMatch,
      samplesToLoseMatch: 2,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: samplesToBecomeStable,
        mismatchesToBecomeUnstable: 2,
      ),
    );
  });

  PitchReading reading(double hz) {
    return PitchReading(
      hasPitch: true,
      frequencyHz: hz,
      note: noteFromFrequency(hz),
    );
  }

  /// Feeds [count] identical valid readings.
  void feed(double hz, int count) {
    for (var i = 0; i < count; i++) {
      matcher.add(reading(hz));
    }
  }

  /// From a cold/unstable start, enough identical samples to reach [matched].
  ///
  /// The sample that first becomes stable also counts toward the match hold.
  void feedUntilMatched(double hz) {
    feed(hz, samplesToBecomeStable + samplesToMatch - 1);
  }

  test('starts waiting until a target is provided', () {
    expect(matcher.state, TargetPitchMatchState.waiting);
    matcher.add(reading(targetHz));
    expect(matcher.state, TargetPitchMatchState.waiting);
  });

  test('start enters listening and stop returns to waiting', () {
    matcher.start(targetHz);
    expect(matcher.state, TargetPitchMatchState.listening);
    expect(matcher.targetFrequencyHz, targetHz);

    matcher.stop();
    expect(matcher.state, TargetPitchMatchState.waiting);
    expect(matcher.targetFrequencyHz, isNull);
  });

  test('exact target pitch becomes matched after sustained hold', () {
    matcher.start(targetHz);

    feed(targetHz, samplesToBecomeStable);
    expect(matcher.state, TargetPitchMatchState.approaching);
    expect(matcher.centsFromTarget, closeTo(0, 0.01));
    expect(matcher.isMatched, isFalse);

    feed(targetHz, samplesToMatch - 1);
    expect(matcher.state, TargetPitchMatchState.matched);
    expect(matcher.isMatched, isTrue);
  });

  test('slightly sharp pitch within tolerance can match', () {
    matcher.start(targetHz);
    // ~+25 cents sharp of D3.
    const sharpHz = 148.97;

    feedUntilMatched(sharpHz);
    expect(matcher.state, TargetPitchMatchState.matched);
    expect(matcher.centsFromTarget!.abs(), lessThanOrEqualTo(50));
    expect(matcher.centsFromTarget, greaterThan(0));
  });

  test('slightly flat pitch within tolerance can match', () {
    matcher.start(targetHz);
    // ~-25 cents flat of D3.
    const flatHz = 144.72;

    feedUntilMatched(flatHz);
    expect(matcher.state, TargetPitchMatchState.matched);
    expect(matcher.centsFromTarget!.abs(), lessThanOrEqualTo(50));
    expect(matcher.centsFromTarget, lessThan(0));
  });

  test('clearly incorrect pitch stays approaching and does not match', () {
    matcher.start(targetHz);
    // A3 ≈ 220 Hz, far from D3.
    feed(220.0, 20);

    expect(matcher.state, TargetPitchMatchState.approaching);
    expect(matcher.isMatched, isFalse);
    expect(matcher.centsFromTarget!.abs(), greaterThan(50));
  });

  test('unstable pitch remains listening', () {
    matcher.start(targetHz);

    matcher.add(reading(targetHz));
    matcher.add(reading(164.81)); // E3
    matcher.add(reading(targetHz));

    expect(matcher.state, TargetPitchMatchState.listening);
    expect(matcher.centsFromTarget, isNull);
    expect(matcher.isMatched, isFalse);
  });

  test('temporary pitch dropout does not reset the trial', () {
    matcher.start(targetHz);

    feed(targetHz, samplesToBecomeStable - 1);
    matcher.add(PitchReading.none);
    matcher.add(const PitchReading(hasPitch: false));
    matcher.add(
      const PitchReading(hasPitch: true, frequencyHz: 0, note: Pitch.d),
    );
    expect(matcher.state, TargetPitchMatchState.listening);

    // Completes stability and begins the in-tolerance hold.
    matcher.add(reading(targetHz));
    expect(matcher.state, TargetPitchMatchState.approaching);

    feed(targetHz, samplesToMatch - 2);
    matcher.add(PitchReading.none); // dropout mid-hold
    matcher.add(reading(targetHz));

    expect(matcher.state, TargetPitchMatchState.matched);
  });

  test('sustained successful match stays matched while on target', () {
    matcher.start(targetHz);
    feedUntilMatched(targetHz);
    expect(matcher.state, TargetPitchMatchState.matched);

    feed(targetHz, 8);
    expect(matcher.state, TargetPitchMatchState.matched);
    expect(matcher.isMatched, isTrue);
  });

  test('losing the target after matching enters lost', () {
    matcher.start(targetHz);
    feedUntilMatched(targetHz);
    expect(matcher.state, TargetPitchMatchState.matched);

    // Move clearly away (A3). Brief mismatch allowance keeps the first
    // sample matched; the second leaves matched → lost.
    matcher.add(reading(220.0));
    expect(matcher.state, TargetPitchMatchState.matched);
    matcher.add(reading(220.0));
    expect(matcher.state, TargetPitchMatchState.lost);
    expect(matcher.isMatched, isFalse);
  });

  test('can rematch after lost', () {
    matcher.start(targetHz);
    feedUntilMatched(targetHz);

    matcher.add(reading(220.0));
    matcher.add(reading(220.0));
    expect(matcher.state, TargetPitchMatchState.lost);

    feedUntilMatched(targetHz);
    expect(matcher.state, TargetPitchMatchState.matched);
  });

  test('boundary of configured cents tolerance is accepted', () {
    // A4 has enough room within its pitch class for a ±50 cent boundary.
    const a4 = 440.0;
    matcher.start(a4);
    final boundaryHz = a4 * 1.0293022366; // 2^(50/1200)

    feedUntilMatched(boundaryHz);

    expect(matcher.state, TargetPitchMatchState.matched);
    expect(matcher.centsFromTarget!.abs(), closeTo(50, 0.05));
  });

  test('just outside configured cents tolerance does not match', () {
    const a4 = 440.0;
    matcher.start(a4);
    // ~+55 cents, still pitch-class A.
    final outsideHz = a4 * 1.032;

    feed(outsideHz, 20);

    expect(matcher.state, TargetPitchMatchState.approaching);
    expect(matcher.isMatched, isFalse);
    expect(matcher.centsFromTarget!.abs(), greaterThan(50));
  });

  test('out-of-tolerance samples while approaching reset match progress', () {
    matcher.start(targetHz);

    feed(targetHz, samplesToBecomeStable + samplesToMatch - 2);
    expect(matcher.state, TargetPitchMatchState.approaching);
    expect(matcher.isMatched, isFalse);

    // Excursion to a different pitch clears the in-tolerance streak.
    matcher.add(reading(220.0));
    expect(matcher.state, TargetPitchMatchState.approaching);
    expect(matcher.isMatched, isFalse);

    // May need to re-stabilize after the pitch-class change.
    feedUntilMatched(targetHz);
    expect(matcher.state, TargetPitchMatchState.matched);
  });
}
