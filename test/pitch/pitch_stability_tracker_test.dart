import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';

void main() {
  late PitchStabilityTracker tracker;

  setUp(() {
    tracker = PitchStabilityTracker(
      samplesToBecomeStable: 4,
      mismatchesToBecomeUnstable: 2,
    );
  });

  test('starts unstable', () {
    expect(tracker.isStable, isFalse);
    expect(tracker.stablePitch, isNull);
  });

  test('becomes stable after enough consecutive matching samples', () {
    for (var i = 0; i < 3; i++) {
      tracker.add(Pitch.d);
      expect(tracker.isStable, isFalse);
    }

    tracker.add(Pitch.d);

    expect(tracker.isStable, isTrue);
    expect(tracker.stablePitch, Pitch.d);
  });

  test('changing pitches before settling stays unstable', () {
    tracker.add(Pitch.d);
    tracker.add(Pitch.e);
    tracker.add(Pitch.fSharp);
    tracker.add(Pitch.e);
    tracker.add(Pitch.d);

    expect(tracker.isStable, isFalse);
  });

  test('brief mismatches do not clear a stable pitch', () {
    for (var i = 0; i < 4; i++) {
      tracker.add(Pitch.d);
    }
    expect(tracker.isStable, isTrue);

    tracker.add(Pitch.e);

    expect(tracker.isStable, isTrue);
    expect(tracker.stablePitch, Pitch.d);
  });

  test('sustained pitch change becomes unstable then restabilizes', () {
    for (var i = 0; i < 4; i++) {
      tracker.add(Pitch.d);
    }
    expect(tracker.isStable, isTrue);

    tracker.add(Pitch.e);
    tracker.add(Pitch.e);
    expect(tracker.isStable, isFalse);

    tracker.add(Pitch.e);
    tracker.add(Pitch.e);
    tracker.add(Pitch.e);
    tracker.add(Pitch.e);

    expect(tracker.isStable, isTrue);
    expect(tracker.stablePitch, Pitch.e);
  });

  test('reset clears stability', () {
    for (var i = 0; i < 4; i++) {
      tracker.add(Pitch.a);
    }
    expect(tracker.isStable, isTrue);

    tracker.reset();

    expect(tracker.isStable, isFalse);
    expect(tracker.stablePitch, isNull);
  });
}
