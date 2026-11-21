import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';

void main() {
  late StablePitchCandidateFinder finder;

  StablePitchCandidateFinder buildFinder({
    int minStableSamples = 4,
    int samplesToBecomeStable = 3,
    int mismatchesToBecomeUnstable = 2,
  }) {
    return StablePitchCandidateFinder(
      minStableSamples: minStableSamples,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: samplesToBecomeStable,
        mismatchesToBecomeUnstable: mismatchesToBecomeUnstable,
      ),
    );
  }

  PitchReading voiced(double hz) {
    return PitchReading(
      hasPitch: true,
      frequencyHz: hz,
      note: noteFromFrequency(hz),
    );
  }

  void emit(double hz, int count) {
    for (var i = 0; i < count; i++) {
      finder.add(voiced(hz));
    }
  }

  setUp(() {
    finder = buildFinder();
  });

  test('clean sustained note produces a candidate from stable data', () {
    final hz = frequencyHzForPitch(Pitch.d);
    emit(hz, 12);

    final candidate = finder.result();

    expect(candidate, isNotNull);
    expect(candidate!.pitch, Pitch.d);
    expect(candidate.frequencyHz, closeTo(hz, 0.5));
    expect(candidate.stableSampleCount, greaterThanOrEqualTo(4));
    expect(finder.hasCandidate, isTrue);
  });

  test('slight natural variation around one note still selects that note', () {
    final center = frequencyHzForPitch(Pitch.a);
    emit(center * 0.995, 4);
    emit(center, 4);
    emit(center * 1.005, 4);

    final candidate = finder.result();

    expect(candidate, isNotNull);
    expect(candidate!.pitch, Pitch.a);
    expect(candidate.frequencyHz, closeTo(center, center * 0.02));
  });

  test('temporary pitch dropout does not clear settled evidence', () {
    final hz = frequencyHzForPitch(Pitch.e);
    emit(hz, 8);
    finder.add(PitchReading.none);
    finder.add(const PitchReading(hasPitch: false));
    emit(hz, 4);

    final candidate = finder.result();

    expect(candidate, isNotNull);
    expect(candidate!.pitch, Pitch.e);
  });

  test('silence alone does not produce a candidate', () {
    finder.add(PitchReading.none);
    finder.add(const PitchReading(hasPitch: false));
    finder.add(const PitchReading(hasPitch: true, frequencyHz: 0));

    expect(finder.result(), isNull);
    expect(finder.hasCandidate, isFalse);
  });

  test('insufficient voiced data does not produce a candidate', () {
    final hz = frequencyHzForPitch(Pitch.g);
    emit(hz, 3);

    expect(finder.result(), isNull);
    expect(finder.hasCandidate, isFalse);
  });

  test('changing pitches prefers the more stably held note', () {
    final dHz = frequencyHzForPitch(Pitch.d);
    final gHz = frequencyHzForPitch(Pitch.g);

    emit(dHz, 5);
    emit(gHz, 14);

    final candidate = finder.result();

    expect(candidate, isNotNull);
    expect(candidate!.pitch, Pitch.g);
  });

  test('stable note after a short initial fluctuation is selected', () {
    final dHz = frequencyHzForPitch(Pitch.d);
    final eHz = frequencyHzForPitch(Pitch.e);

    emit(dHz, 2);
    emit(eHz, 12);

    final candidate = finder.result();

    expect(candidate, isNotNull);
    expect(candidate!.pitch, Pitch.e);
  });

  test('unstable random pitch data does not produce a confident candidate', () {
    final pitches = <Pitch>[Pitch.c, Pitch.d, Pitch.e, Pitch.f, Pitch.g];
    for (var i = 0; i < 20; i++) {
      emit(frequencyHzForPitch(pitches[i % pitches.length]), 1);
    }

    expect(finder.result(), isNull);
    expect(finder.hasCandidate, isFalse);
  });

  test('candidate comes from stable counts, not raw frame majority', () {
    // Many unstable frames on C, then a shorter settled hold on D.
    final cHz = frequencyHzForPitch(Pitch.c);
    final dHz = frequencyHzForPitch(Pitch.d);

    // Alternate so C never becomes stable, despite more raw frames.
    for (var i = 0; i < 10; i++) {
      finder.add(voiced(cHz));
      finder.add(voiced(frequencyHzForPitch(Pitch.e)));
    }
    emit(dHz, 10);

    final candidate = finder.result();

    expect(candidate, isNotNull);
    expect(candidate!.pitch, Pitch.d);
  });

  test('reset clears prior capture evidence', () {
    emit(frequencyHzForPitch(Pitch.a), 12);
    expect(finder.result(), isNotNull);

    finder.reset();

    expect(finder.result(), isNull);
    expect(finder.hasCandidate, isFalse);
  });

  test(
    'production defaults: 14 steady A frames are rejected, 15 are accepted',
    () {
      // Mirrors Assist Mode production wiring:
      // samplesToBecomeStable=6, minStableSamples=10
      // → first 5 frames warm up the tracker (not credited)
      // → frames 6..15 credit 10 stable samples
      final productionFinder = StablePitchCandidateFinder(
        minStableSamples: 10,
        stabilityTracker: PitchStabilityTracker(
          samplesToBecomeStable: 6,
          mismatchesToBecomeUnstable: 3,
        ),
      );
      final aHz = frequencyHzForPitch(Pitch.a);

      for (var i = 0; i < 14; i++) {
        productionFinder.add(
          PitchReading(hasPitch: true, frequencyHz: aHz, note: Pitch.a),
        );
      }
      expect(
        productionFinder.result(),
        isNull,
        reason: '9 credited stable samples < minStableSamples=10',
      );
      expect(productionFinder.debugCreditedStableSamples, 9);

      productionFinder.add(
        PitchReading(hasPitch: true, frequencyHz: aHz, note: Pitch.a),
      );
      final candidate = productionFinder.result();
      expect(candidate, isNotNull);
      expect(candidate!.pitch, Pitch.a);
      expect(candidate.stableSampleCount, 10);
    },
  );
}
