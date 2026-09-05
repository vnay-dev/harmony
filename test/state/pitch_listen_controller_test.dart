import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/state/pitch_listen_controller.dart';

import '../support/fake_pitch_detection_service.dart';

void main() {
  late FakePitchDetectionService detectionService;
  late PitchListenController controller;

  setUp(() {
    detectionService = FakePitchDetectionService();
    controller = PitchListenController(detectionService: detectionService);
  });

  tearDown(() {
    controller.dispose();
  });

  test('starts idle', () {
    expect(controller.isListening, isFalse);
    expect(controller.frequencyHz, isNull);
    expect(controller.note, isNull);
    expect(controller.isPitchStable, isFalse);
    expect(controller.noteSequence, isEmpty);
  });

  test('startListening enables listening', () async {
    await controller.startListening();

    expect(controller.isListening, isTrue);
    expect(detectionService.startCount, 1);
    expect(controller.errorMessage, isNull);
    expect(controller.frequencyHz, isNull);
    expect(controller.note, isNull);
  });

  test('startListening surfaces permission errors', () async {
    detectionService.failStart = true;

    await controller.startListening();

    expect(controller.isListening, isFalse);
    expect(controller.errorMessage, 'Microphone permission was denied.');
  });

  test('first valid detection updates frequency and note together', () async {
    await controller.startListening();

    detectionService.emit(
      const PitchReading(hasPitch: true, frequencyHz: 146.8, note: Pitch.d),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.frequencyHz, closeTo(146.8, 0.01));
    expect(controller.note, Pitch.d);
  });

  test('keeps last valid result when detection briefly fails', () async {
    await controller.startListening();

    detectionService.emit(
      const PitchReading(hasPitch: true, frequencyHz: 146.8, note: Pitch.d),
    );
    await Future<void>.delayed(Duration.zero);

    detectionService.emit(PitchReading.none);
    await Future<void>.delayed(Duration.zero);

    expect(controller.frequencyHz, closeTo(146.8, 0.01));
    expect(controller.note, Pitch.d);
  });

  test('updates frequency and note together when pitch changes', () async {
    await controller.startListening();

    detectionService.emit(
      const PitchReading(hasPitch: true, frequencyHz: 246.94, note: Pitch.b),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.frequencyHz, closeTo(246.94, 0.01));
    expect(controller.note, Pitch.b);

    // Stale/wrong note in the reading must not win over frequency→note.
    detectionService.emit(
      const PitchReading(hasPitch: true, frequencyHz: 277.18, note: Pitch.b),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.frequencyHz, closeTo(277.18, 0.01));
    expect(controller.note, Pitch.cSharp);
  });

  test('replaces displayed result for several pitch changes', () async {
    await controller.startListening();

    final samples = <(double, Pitch)>[
      (220.0, Pitch.a),
      (246.94, Pitch.b),
      (277.18, Pitch.cSharp),
      (293.66, Pitch.d),
      (164.81, Pitch.e),
    ];

    for (final sample in samples) {
      detectionService.emit(
        PitchReading(
          hasPitch: true,
          frequencyHz: sample.$1,
          note: Pitch.b, // intentionally wrong; controller derives from Hz
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.frequencyHz, closeTo(sample.$1, 0.01));
      expect(controller.note, sample.$2);
    }
  });

  test('stopListening clears the live reading', () async {
    await controller.startListening();
    detectionService.emit(
      const PitchReading(hasPitch: true, frequencyHz: 220.0, note: Pitch.a),
    );
    await Future<void>.delayed(Duration.zero);

    await controller.stopListening();

    expect(controller.isListening, isFalse);
    expect(controller.frequencyHz, isNull);
    expect(controller.note, isNull);
    expect(detectionService.stopCount, greaterThanOrEqualTo(1));
  });

  test('restarting starts empty until the next valid detection', () async {
    await controller.startListening();
    detectionService.emit(
      const PitchReading(hasPitch: true, frequencyHz: 146.8, note: Pitch.d),
    );
    await Future<void>.delayed(Duration.zero);
    await controller.stopListening();

    await controller.startListening();

    expect(controller.isListening, isTrue);
    expect(controller.frequencyHz, isNull);
    expect(controller.note, isNull);
    expect(controller.isPitchStable, isFalse);
  });

  test('marks a sustained note as stable', () async {
    final service = FakePitchDetectionService();
    final tuned = PitchListenController(
      detectionService: service,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: 3,
        mismatchesToBecomeUnstable: 2,
      ),
    );
    addTearDown(tuned.dispose);

    await tuned.startListening();

    for (var i = 0; i < 3; i++) {
      service.emit(
        const PitchReading(hasPitch: true, frequencyHz: 146.8, note: Pitch.d),
      );
      await Future<void>.delayed(Duration.zero);
    }

    expect(tuned.note, Pitch.d);
    expect(tuned.isPitchStable, isTrue);
    expect(tuned.noteSequence, [Pitch.d]);
    expect(tuned.noteSequenceLabel, 'D');
  });

  test('pitch changes make the reading unstable until it settles', () async {
    final service = FakePitchDetectionService();
    final tuned = PitchListenController(
      detectionService: service,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: 3,
        mismatchesToBecomeUnstable: 2,
      ),
    );
    addTearDown(tuned.dispose);

    await tuned.startListening();

    for (var i = 0; i < 3; i++) {
      service.emit(
        const PitchReading(hasPitch: true, frequencyHz: 146.8, note: Pitch.d),
      );
      await Future<void>.delayed(Duration.zero);
    }
    expect(tuned.isPitchStable, isTrue);

    service.emit(
      const PitchReading(hasPitch: true, frequencyHz: 164.8, note: Pitch.e),
    );
    await Future<void>.delayed(Duration.zero);
    service.emit(
      const PitchReading(hasPitch: true, frequencyHz: 164.8, note: Pitch.e),
    );
    await Future<void>.delayed(Duration.zero);

    expect(tuned.note, Pitch.e);
    expect(tuned.isPitchStable, isFalse);

    service.emit(
      const PitchReading(hasPitch: true, frequencyHz: 164.8, note: Pitch.e),
    );
    await Future<void>.delayed(Duration.zero);
    service.emit(
      const PitchReading(hasPitch: true, frequencyHz: 164.8, note: Pitch.e),
    );
    await Future<void>.delayed(Duration.zero);
    service.emit(
      const PitchReading(hasPitch: true, frequencyHz: 164.8, note: Pitch.e),
    );
    await Future<void>.delayed(Duration.zero);

    expect(tuned.isPitchStable, isTrue);
    expect(tuned.noteSequence, [Pitch.d, Pitch.e]);
    expect(tuned.noteSequenceLabel, 'D → E');
  });

  test('builds a note sequence across several stable pitches', () async {
    final service = FakePitchDetectionService();
    final tuned = PitchListenController(
      detectionService: service,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: 2,
        mismatchesToBecomeUnstable: 2,
      ),
    );
    addTearDown(tuned.dispose);

    await tuned.startListening();

    // From unstable: 2 matching samples stabilize.
    // From a different stable note: 2 mismatches leave stability, then more
    // matching samples restabilize on the new note.
    Future<void> settle(double hz) async {
      for (var i = 0; i < 4; i++) {
        service.emit(PitchReading(hasPitch: true, frequencyHz: hz, note: null));
        await Future<void>.delayed(Duration.zero);
      }
    }

    await settle(146.8); // D
    await settle(164.8); // E
    await settle(185.0); // F#
    await settle(164.8); // E
    await settle(146.8); // D

    expect(tuned.noteSequenceLabel, 'D → E → F# → E → D');
  });

  test('holding one stable note does not repeat it in the sequence', () async {
    final service = FakePitchDetectionService();
    final tuned = PitchListenController(
      detectionService: service,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: 2,
        mismatchesToBecomeUnstable: 2,
      ),
    );
    addTearDown(tuned.dispose);

    await tuned.startListening();

    for (var i = 0; i < 8; i++) {
      service.emit(
        const PitchReading(hasPitch: true, frequencyHz: 146.8, note: Pitch.d),
      );
      await Future<void>.delayed(Duration.zero);
    }

    expect(tuned.isPitchStable, isTrue);
    expect(tuned.noteSequence, [Pitch.d]);
  });
}
