import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_mode_controller.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';
import '../support/fake_reference_sound_generator.dart';

void main() {
  late FakePitchDetectionService detectionService;
  late FakeAudioService audioService;
  late FakeReferenceSoundGenerator referenceSound;

  const fastTiming = AssistTimingConfig(
    referencePlayDuration: Duration(milliseconds: 1),
    settlingDuration: Duration(milliseconds: 1),
    listenDuration: Duration(milliseconds: 1),
    transitionDuration: Duration(milliseconds: 1),
  );

  StablePitchCandidateFinder buildFinder() {
    return StablePitchCandidateFinder(
      minStableSamples: 4,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: 3,
        mismatchesToBecomeUnstable: 2,
      ),
    );
  }

  TargetPitchMatcher buildMatcher() {
    return TargetPitchMatcher(
      toleranceCents: 50,
      samplesToMatch: 4,
      samplesToLoseMatch: 2,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: 3,
        mismatchesToBecomeUnstable: 2,
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

  Future<void> emitPitch(
    FakePitchDetectionService service,
    Pitch pitch, {
    int count = 12,
  }) async {
    final hz = frequencyHzForPitch(pitch);
    for (var i = 0; i < count; i++) {
      service.emit(voiced(hz));
    }
  }

  Future<void> emitHz(
    FakePitchDetectionService service,
    double hz, {
    int count = 12,
  }) async {
    for (var i = 0; i < count; i++) {
      service.emit(voiced(hz));
    }
  }

  Future<void> Function(Duration) phasedWait(
    AssistModeController Function() controllerOf, {
    Future<void> Function(AssistUiPhase phase)? onPhase,
  }) {
    return (duration) async {
      final phase = controllerOf().uiPhase;
      if (onPhase != null) {
        await onPhase(phase);
      }
    };
  }

  /// Drives Stage 1 to [stage1Pitch], then Stage 2 with optional listen hook.
  ///
  /// Default Stage 2 singing matches the current range-point target Hz.
  AssistModeController buildRangeController({
    required Pitch stage1Pitch,
    Future<void> Function(AssistModeController controller)? onRangeListening,
    bool autoMatchRange = true,
  }) {
    late final AssistModeController controller;
    controller = AssistModeController(
      detectionService: detectionService,
      audioService: audioService,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      referenceSoundGenerator: referenceSound,
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      prepareAudioSession: () async {},
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase != AssistUiPhase.listening) {
            return;
          }
          if (controller.isExploringRange) {
            if (onRangeListening != null) {
              await onRangeListening(controller);
              return;
            }
            if (autoMatchRange) {
              final hz = controller.currentRangeTargetHz;
              if (hz != null) {
                await emitHz(detectionService, hz);
              }
            }
            return;
          }
          await emitPitch(detectionService, stage1Pitch);
        },
      ),
    );
    return controller;
  }

  /// Completes Stage 2 with a valid recommendation: first candidate Upper Sa
  /// Comfortable, next candidate Upper Sa Strained → final = first.
  Future<void> finishCandidateAtUpperBoundary(
    AssistModeController controller,
  ) async {
    var markedFirstComfortable = false;
    for (var i = 0; i < 64; i++) {
      final phase = controller.uiPhase;
      if (phase == AssistUiPhase.awaitingLowerAudibility) {
        await controller.reportLowerSaAudible();
      } else if (phase == AssistUiPhase.awaitingUpperComfort) {
        if (!markedFirstComfortable) {
          markedFirstComfortable = true;
          await controller.reportUpperSaComfortable();
        } else {
          await controller.reportUpperSaStrained();
        }
      } else if (phase == AssistUiPhase.rangeBoundaryReached) {
        await controller.acknowledgeRangeBoundary();
      } else if (phase == AssistUiPhase.completed ||
          phase == AssistUiPhase.intro ||
          phase == AssistUiPhase.rangeUnresolved) {
        return;
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Answers Lower Yes so Pa / Upper Sa matching can continue.
  Future<void> answerLowerAudibleYes(AssistModeController controller) async {
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    await controller.reportLowerSaAudible();
  }

  setUp(() {
    detectionService = FakePitchDetectionService();
    audioService = FakeAudioService();
    referenceSound = FakeReferenceSoundGenerator();
  });

  test('C# Stage 1 creates Lower Sa target at C# octave 3', () async {
    late final AssistModeController controller;
    final hold = <AssistRangePoint?>[];
    controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        hold.add(c.currentRangePoint);
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(hold.first, AssistRangePoint.lowerSa);
    expect(
      controller.rangeTargets?.lowerSaHz,
      frequencyHzForPitch(Pitch.cSharp, octave: 3),
    );
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(controller.stage1Shruti, Pitch.cSharp);

    await finishCandidateAtUpperBoundary(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
  });

  test('Lower Sa matches and advances to Pa after audibility Yes', () async {
    final seen = <AssistRangePoint>[];
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        final point = c.currentRangePoint;
        if (point != null && (seen.isEmpty || seen.last != point)) {
          seen.add(point);
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(seen.first, AssistRangePoint.lowerSa);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);

    await answerLowerAudibleYes(controller);

    expect(seen, contains(AssistRangePoint.pa));
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
  });

  test('Lower Sa = Yes continues to Pa', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(controller.activeCandidateResult?.lowerSaMatched, isTrue);

    await controller.reportLowerSaAudible();

    expect(controller.activeCandidateResult?.lowerSaAudible, isTrue);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
    expect(controller.activeCandidateResult?.paMatched, isTrue);
    expect(controller.activeCandidateResult?.upperSaMatched, isTrue);
  });

  test('Lower Sa = No rejects candidate and moves upward', () async {
    final candidates = <Pitch>[];
    final controller = buildRangeController(
      stage1Pitch: Pitch.c,
      onRangeListening: (c) async {
        final cand = c.currentExploreCandidate;
        if (cand != null && (candidates.isEmpty || candidates.last != cand)) {
          candidates.add(cand);
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.currentExploreCandidate, Pitch.c);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);

    await controller.reportLowerSaTooLow();

    expect(controller.testedCandidates.first.lowerSaAudible, isFalse);
    expect(controller.testedCandidates.first.lowerSaMatched, isTrue);
    expect(controller.currentExploreCandidate, Pitch.cSharp);
    expect(candidates, [Pitch.c, Pitch.cSharp]);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(controller.lastComfortableShruti, isNull);
  });

  test('Upper Sa = Comfortable explores the next Shruti', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);

    await controller.reportUpperSaComfortable();

    expect(controller.lastComfortableShruti, Pitch.c);
    expect(controller.testedCandidates.first.upperSaComfortable, isTrue);
    expect(controller.currentExploreCandidate, Pitch.cSharp);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
  });

  test('C comfortable then C# strained → final Shruti is C', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaComfortable();
    expect(controller.lastComfortableShruti, Pitch.c);

    await answerLowerAudibleYes(controller);
    expect(controller.currentExploreCandidate, Pitch.cSharp);
    await controller.reportUpperSaStrained();

    expect(controller.uiPhase, AssistUiPhase.rangeBoundaryReached);
    expect(controller.currentBoundaryShruti, Pitch.cSharp);
    expect(controller.lastComfortableShruti, Pitch.c);

    await controller.acknowledgeRangeBoundary();
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.c);
    expect(controller.referencePitch, isNot(Pitch.cSharp));
  });

  test('C then C# comfortable, D strained → final Shruti is C#', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaComfortable();
    expect(controller.lastComfortableShruti, Pitch.c);

    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaComfortable();
    expect(controller.lastComfortableShruti, Pitch.cSharp);
    expect(controller.currentExploreCandidate, Pitch.d);

    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaStrained();

    expect(controller.currentBoundaryShruti, Pitch.d);
    expect(controller.lastComfortableShruti, Pitch.cSharp);

    await controller.acknowledgeRangeBoundary();
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
    expect(controller.referencePitch, isNot(Pitch.d));
  });

  test('multiple comfortable candidates before strain', () async {
    final comfortable = <Pitch>[];
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    for (final _ in [Pitch.c, Pitch.cSharp, Pitch.d]) {
      await answerLowerAudibleYes(controller);
      await controller.reportUpperSaComfortable();
      comfortable.add(controller.lastComfortableShruti!);
    }
    expect(comfortable, [Pitch.c, Pitch.cSharp, Pitch.d]);
    expect(controller.currentExploreCandidate, Pitch.dSharp);

    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaStrained();
    await controller.acknowledgeRangeBoundary();

    expect(controller.referencePitch, Pitch.d);
    expect(controller.currentBoundaryShruti, Pitch.dSharp);
  });

  test('first candidate strained leaves result unresolved', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaStrained();

    expect(controller.uiPhase, AssistUiPhase.rangeUnresolved);
    expect(controller.currentBoundaryShruti, Pitch.c);
    expect(controller.lastComfortableShruti, isNull);
    expect(controller.uiPhase, isNot(AssistUiPhase.completed));

    // Acknowledge must not apply from unresolved; tryAgain is the path.
    await controller.acknowledgeRangeBoundary();
    expect(controller.uiPhase, AssistUiPhase.rangeUnresolved);
  });

  test('strained candidate is never returned as final Shruti', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaComfortable();
    await answerLowerAudibleYes(controller);
    final strained = controller.currentExploreCandidate!;
    await controller.reportUpperSaStrained();
    await controller.acknowledgeRangeBoundary();

    expect(controller.referencePitch, isNot(strained));
    expect(controller.currentBoundaryShruti, strained);
    expect(controller.referencePitch, controller.lastComfortableShruti);
  });

  test('user answers do not alter pitch detection matching logic', () async {
    var wrongUpperAttempts = 0;
    late final AssistModeController controller;
    controller = AssistModeController(
      detectionService: detectionService,
      audioService: audioService,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      referenceSoundGenerator: referenceSound,
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      prepareAudioSession: () async {},
      wait: (duration) async {
        if (controller.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!controller.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        final point = controller.currentRangePoint;
        if (point == AssistRangePoint.upperSa && wrongUpperAttempts < 2) {
          wrongUpperAttempts += 1;
          // Same pitch class, wrong octave — must not match.
          await emitHz(
            detectionService,
            frequencyHzForPitch(Pitch.c, octave: 3),
          );
          return;
        }
        final hz = controller.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    // Lower audibility Yes must not change matching rules for Upper Sa.
    await answerLowerAudibleYes(controller);

    expect(wrongUpperAttempts, 2);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
    expect(controller.activeCandidateResult?.upperSaMatched, isTrue);
  });

  test('back-to-back taps cannot trigger multiple Shruti advances', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);

    final first = controller.reportUpperSaComfortable();
    final second = controller.reportUpperSaComfortable();
    await Future.wait<void>([first, second]);

    expect(controller.testedCandidates, hasLength(2));
    expect(controller.currentExploreCandidate, Pitch.cSharp);
    expect(
      controller.testedCandidates.map((r) => r.shruti).toList(),
      [Pitch.c, Pitch.cSharp],
    );
  });

  test('no duplicate advancement when Lower Sa is too low', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    final first = controller.reportLowerSaTooLow();
    final second = controller.reportLowerSaTooLow();
    await Future.wait<void>([first, second]);

    expect(controller.testedCandidates, hasLength(2));
    expect(controller.currentExploreCandidate, Pitch.cSharp);
  });

  test('Lower Sa does not advance on the wrong pitch', () async {
    var wrongListens = 0;
    final points = <AssistRangePoint>[];
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        final point = c.currentRangePoint;
        if (point != null) {
          points.add(point);
        }
        if (point == AssistRangePoint.lowerSa && wrongListens < 2) {
          wrongListens += 1;
          await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(wrongListens, 2);
    expect(points.take(2).every((p) => p == AssistRangePoint.lowerSa), isTrue);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    await finishCandidateAtUpperBoundary(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
  });

  test('Pa target is the correct fifth above Sa', () async {
    AssistRangeTargets? seenTargets;
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        if (c.currentRangePoint == AssistRangePoint.pa) {
          seenTargets = c.rangeTargets;
          expect(
            c.currentRangeTargetHz,
            frequencyHzForPitch(Pitch.gSharp, octave: 3),
          );
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(seenTargets?.paPitch, Pitch.gSharp);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
  });

  test('Pa does not advance on the wrong pitch', () async {
    var paWrongAttempts = 0;
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        final point = c.currentRangePoint;
        if (point == AssistRangePoint.pa && paWrongAttempts < 2) {
          paWrongAttempts += 1;
          await emitHz(
            detectionService,
            frequencyHzForPitch(Pitch.cSharp, octave: 3),
          );
          return;
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(paWrongAttempts, 2);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
  });

  test('successful Pa match advances to Upper Sa', () async {
    final seen = <AssistRangePoint>[];
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        final point = c.currentRangePoint;
        if (point != null && (seen.isEmpty || seen.last != point)) {
          seen.add(point);
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(seen, contains(AssistRangePoint.pa));
    expect(seen, contains(AssistRangePoint.upperSa));
    expect(
      seen.indexOf(AssistRangePoint.pa),
      lessThan(seen.indexOf(AssistRangePoint.upperSa)),
    );
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
  });

  test('Upper Sa is one octave above Lower Sa', () async {
    double? upperHz;
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        if (c.currentRangePoint == AssistRangePoint.upperSa) {
          upperHz = c.currentRangeTargetHz;
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(upperHz, frequencyHzForPitch(Pitch.cSharp, octave: 4));
    expect(
      upperHz! / frequencyHzForPitch(Pitch.cSharp, octave: 3),
      closeTo(2.0, 0.0001),
    );
  });

  test('Upper Sa does not advance on Lower Sa pitch', () async {
    var upperWrongAttempts = 0;
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        final point = c.currentRangePoint;
        if (point == AssistRangePoint.upperSa && upperWrongAttempts < 2) {
          upperWrongAttempts += 1;
          await emitHz(
            detectionService,
            frequencyHzForPitch(Pitch.cSharp, octave: 3),
          );
          return;
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(upperWrongAttempts, 2);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
  });

  test('successful Upper Sa match awaits comfort before completing', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.cSharp);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
    expect(controller.stage1Shruti, Pitch.cSharp);
    expect(controller.currentRangePoint, AssistRangePoint.upperSa);

    await finishCandidateAtUpperBoundary(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('silence does not advance the target', () async {
    var silentListens = 0;
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        if (c.currentRangePoint == AssistRangePoint.lowerSa &&
            silentListens < 3) {
          silentListens += 1;
          return;
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(silentListens, 3);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    await finishCandidateAtUpperBoundary(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
  });

  test('invalid pitch does not advance the target', () async {
    var attempts = 0;
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        attempts += 1;
        if (attempts < 3) {
          detectionService.emit(PitchReading.none);
          detectionService.emit(
            const PitchReading(hasPitch: true, frequencyHz: -1),
          );
          return;
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(attempts, greaterThanOrEqualTo(3));
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    await finishCandidateAtUpperBoundary(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
  });

  test('Tanpura playback does not enable pitch analysis', () async {
    final analysisDuringPlay = <bool>[];
    late final AssistModeController spying;
    spying = AssistModeController(
      detectionService: detectionService,
      audioService: audioService,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      referenceSoundGenerator: referenceSound,
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      prepareAudioSession: () async {},
      wait: (duration) async {
        if (spying.uiPhase == AssistUiPhase.playingReference) {
          analysisDuringPlay.add(spying.isPitchAnalysisEnabled);
        }
        if (spying.uiPhase == AssistUiPhase.listening) {
          if (!spying.isExploringRange) {
            await emitPitch(detectionService, Pitch.cSharp);
          } else {
            final hz = spying.currentRangeTargetHz;
            if (hz != null) {
              await emitHz(detectionService, hz);
            }
          }
        }
      },
    );
    addTearDown(spying.dispose);

    await spying.startSession();
    await finishCandidateAtUpperBoundary(spying);

    expect(analysisDuringPlay, isNotEmpty);
    expect(analysisDuringPlay.every((enabled) => !enabled), isTrue);
    expect(spying.uiPhase, AssistUiPhase.completed);
  });

  test('Try Again resets comfort state and range target to Lower Sa', () async {
    final pointsAfterRetry = <AssistRangePoint?>[];
    late final AssistModeController controller;
    var pass = 0;
    controller = AssistModeController(
      detectionService: detectionService,
      audioService: audioService,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      referenceSoundGenerator: referenceSound,
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      prepareAudioSession: () async {},
      wait: (duration) async {
        if (controller.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!controller.isExploringRange) {
          await emitPitch(
            detectionService,
            pass == 0 ? Pitch.e : Pitch.a,
          );
          return;
        }
        if (pass == 1 && pointsAfterRetry.isEmpty) {
          pointsAfterRetry.add(controller.currentRangePoint);
          expect(controller.stage1Shruti, Pitch.a);
          expect(controller.lastComfortableShruti, isNull);
          expect(controller.currentBoundaryShruti, isNull);
          expect(controller.testedCandidates, hasLength(1));
          expect(controller.testedCandidates.single.shruti, Pitch.a);
        }
        final hz = controller.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaComfortable();
    expect(controller.lastComfortableShruti, Pitch.e);
    expect(controller.testedCandidates, isNotEmpty);

    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaStrained();
    expect(controller.currentBoundaryShruti, isNot(Pitch.e));
    await controller.acknowledgeRangeBoundary();
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.e);
    expect(controller.stage1Shruti, Pitch.e);

    pass = 1;
    await controller.tryAgain();
    await finishCandidateAtUpperBoundary(controller);

    expect(pointsAfterRetry.first, AssistRangePoint.lowerSa);
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.stage1Shruti, Pitch.a);
    expect(controller.referencePitch, Pitch.a);
    expect(controller.lastComfortableShruti, Pitch.a);
    expect(controller.currentBoundaryShruti, isNot(Pitch.a));
  });

  test('range test stores flags without a numeric comfort score', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.cSharp);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaComfortable();
    await answerLowerAudibleYes(controller);
    await controller.reportUpperSaStrained();
    await controller.acknowledgeRangeBoundary();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.stage1Shruti, Pitch.cSharp);
    expect(controller.referencePitch, Pitch.cSharp);
    expect(controller.testedCandidates, hasLength(2));
    final first = controller.testedCandidates.first;
    expect(first.shruti, Pitch.cSharp);
    expect(first.lowerSaMatched, isTrue);
    expect(first.lowerSaAudible, isTrue);
    expect(first.paMatched, isTrue);
    expect(first.upperSaMatched, isTrue);
    expect(first.upperSaComfortable, isTrue);
    final boundary = controller.testedCandidates.last;
    expect(boundary.upperSaComfortable, isFalse);
    expect(controller.currentBoundaryShruti, boundary.shruti);
  });

  test('targets progress strictly Lower Sa → Pa → Upper Sa', () async {
    final seen = <AssistRangePoint>[];
    final controller = buildRangeController(
      stage1Pitch: Pitch.cSharp,
      onRangeListening: (c) async {
        final point = c.currentRangePoint;
        if (point != null && (seen.isEmpty || seen.last != point)) {
          seen.add(point);
        }
        final hz = c.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(
      seen,
      [
        AssistRangePoint.lowerSa,
        AssistRangePoint.pa,
        AssistRangePoint.upperSa,
      ],
    );
  });

  test('Stage 2 C session plays Lower C, G, and Upper C reference Hz', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(referenceSound.playedFrequencies, hasLength(1));

    await answerLowerAudibleYes(controller);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
    expect(referenceSound.playedFrequencies, hasLength(3));
    expect(referenceSound.playedFrequencies[0], closeTo(130.81, 0.02));
    expect(referenceSound.playedFrequencies[1], closeTo(196.00, 0.02));
    expect(referenceSound.playedFrequencies[2], closeTo(261.63, 0.02));
    expect(referenceSound.stopCount, greaterThanOrEqualTo(3));
  });

  test('Stage 2 range references do not load Stage 1 Tanpura assets', () async {
    final controller = buildRangeController(stage1Pitch: Pitch.c);
    addTearDown(controller.dispose);

    await controller.startSession();
    await answerLowerAudibleYes(controller);

    expect(referenceSound.playCount, 3);
    expect(
      referenceSound.playedFrequencies.toSet().length,
      3,
      reason: 'each range point must request a distinct frequency',
    );
    expect(
      referenceSound.stopCount,
      greaterThanOrEqualTo(referenceSound.playCount),
    );
  });
}
