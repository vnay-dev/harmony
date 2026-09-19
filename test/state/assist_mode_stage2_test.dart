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

void main() {
  late FakePitchDetectionService detectionService;
  late FakeAudioService audioService;

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

  /// Drives Stage 1 to a confirmed starting Shruti, then Stage 2 begins.
  ///
  /// [stage1Pitch] is sung during Stage 1. [onExploreListening] controls what
  /// is sung during Stage 2 listens (defaults to matching the explore target).
  AssistModeController buildExploringController({
    required Pitch stage1Pitch,
    Future<void> Function(AssistModeController controller)? onExploreListening,
    Pitch? Function(AssistModeController controller)? exploreEmitPitch,
  }) {
    late final AssistModeController controller;
    controller = AssistModeController(
      detectionService: detectionService,
      audioService: audioService,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
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
            if (onExploreListening != null) {
              await onExploreListening(controller);
              return;
            }
            final target =
                exploreEmitPitch?.call(controller) ??
                controller.currentExploreCandidate ??
                stage1Pitch;
            await emitPitch(detectionService, target);
            return;
          }
          await emitPitch(detectionService, stage1Pitch);
        },
      ),
    );
    return controller;
  }

  setUp(() {
    detectionService = FakePitchDetectionService();
    audioService = FakeAudioService();
  });

  test('Stage 1 C# confirmation enters Stage 2 and can match C#', () async {
    final controller = buildExploringController(stage1Pitch: Pitch.cSharp);
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.stage1Shruti, Pitch.cSharp);
    expect(controller.isExploringRange, isTrue);
    expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
    expect(controller.currentExploreCandidate, Pitch.cSharp);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('C# comfortable advances explore candidate to D', () async {
    final controller = buildExploringController(stage1Pitch: Pitch.cSharp);
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
    expect(controller.currentExploreCandidate, Pitch.cSharp);

    await controller.reportComfortable();

    expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
    expect(controller.lastComfortableShruti, Pitch.cSharp);
    expect(controller.currentExploreCandidate, Pitch.d);
    expect(controller.referencePitch, Pitch.d);
  });

  test('D matched but not comfortable recommends C#', () async {
    final controller = buildExploringController(stage1Pitch: Pitch.cSharp);
    addTearDown(controller.dispose);

    await controller.startSession();
    await controller.reportComfortable(); // C# → D
    expect(controller.currentExploreCandidate, Pitch.d);
    expect(controller.uiPhase, AssistUiPhase.awaitingComfort);

    await controller.reportNotComfortable();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
    expect(controller.isReferencePlaying, isTrue);
  });

  test('D not matched recommends C#', () async {
    var allowMatchOnD = false;
    final controller = buildExploringController(
      stage1Pitch: Pitch.cSharp,
      onExploreListening: (c) async {
        final target = c.currentExploreCandidate!;
        if (target == Pitch.d && !allowMatchOnD) {
          // Sing wrong pitch — must not count as matching D.
          await emitPitch(detectionService, Pitch.cSharp);
          return;
        }
        await emitPitch(detectionService, target);
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.currentExploreCandidate, Pitch.cSharp);
    await controller.reportComfortable();

    // Second explore round targets D; wrong pitch → no match → complete.
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('wrong pitch while D is target does not treat D as matched', () async {
    final controller = buildExploringController(
      stage1Pitch: Pitch.cSharp,
      onExploreListening: (c) async {
        if (c.currentExploreCandidate == Pitch.d) {
          await emitPitch(detectionService, Pitch.e);
        } else {
          await emitPitch(detectionService, c.currentExploreCandidate!);
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await controller.reportComfortable();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
    expect(controller.currentExploreCandidate, Pitch.d);
  });

  test('brief pitch crossing does not count as a successful match', () async {
    final controller = buildExploringController(
      stage1Pitch: Pitch.cSharp,
      onExploreListening: (c) async {
        final target = c.currentExploreCandidate!;
        // Two samples of target, then jump away — not enough for stable match.
        await emitPitch(detectionService, target, count: 2);
        await emitPitch(detectionService, Pitch.a, count: 8);
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    // First Stage 2 candidate also fails brief crossing → recommend stage1.
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('stable matching pitch counts as matched', () async {
    final controller = buildExploringController(stage1Pitch: Pitch.d);
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
    expect(controller.currentExploreCandidate, Pitch.d);
  });

  test('silence does not count as matched', () async {
    final controller = buildExploringController(
      stage1Pitch: Pitch.cSharp,
      onExploreListening: (_) async {
        detectionService.emit(PitchReading.none);
        detectionService.emit(const PitchReading(hasPitch: false));
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('invalid pitch does not count as matched', () async {
    final controller = buildExploringController(
      stage1Pitch: Pitch.cSharp,
      onExploreListening: (_) async {
        detectionService.emit(
          const PitchReading(hasPitch: true, frequencyHz: -1),
        );
        detectionService.emit(
          const PitchReading(hasPitch: true, frequencyHz: double.nan),
        );
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('continues upward one supported Shruti at a time', () async {
    final seen = <Pitch>[];
    final controller = buildExploringController(
      stage1Pitch: Pitch.c,
      onExploreListening: (c) async {
        final target = c.currentExploreCandidate!;
        seen.add(target);
        await emitPitch(detectionService, target);
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.currentExploreCandidate, Pitch.c);
    await controller.reportComfortable();
    expect(controller.currentExploreCandidate, Pitch.cSharp);
    await controller.reportComfortable();
    expect(controller.currentExploreCandidate, Pitch.d);
    await controller.reportNotComfortable();

    expect(controller.referencePitch, Pitch.cSharp);
    expect(seen, containsAll(<Pitch>[Pitch.c, Pitch.cSharp, Pitch.d]));
    // Never skipped ahead of one step.
    expect(seen[1], Pitch.cSharp);
    expect(seen[2], Pitch.d);
  });

  test('highest supported Shruti B comfortable completes with B', () async {
    final controller = buildExploringController(stage1Pitch: Pitch.b);
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.currentExploreCandidate, Pitch.b);
    expect(controller.uiPhase, AssistUiPhase.awaitingComfort);

    await controller.reportComfortable();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.b);
  });

  test(
    'tryAgain resets Stage 2 and restarts Stage 1 with smart start',
    () async {
      late final AssistModeController controller;
      var pass = 0;
      var listenCountPass1 = 0;

      controller = AssistModeController(
        detectionService: detectionService,
        audioService: audioService,
        candidateFinder: buildFinder(),
        targetMatcher: buildMatcher(),
        timing: fastTiming,
        initialReferencePitch: Pitch.c,
        prepareAudioSession: () async {},
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase != AssistUiPhase.listening) {
              return;
            }
            if (pass == 0) {
              await emitPitch(detectionService, Pitch.e);
              return;
            }
            if (controller.isExploringRange) {
              await emitPitch(
                detectionService,
                controller.currentExploreCandidate!,
              );
              return;
            }
            listenCountPass1 += 1;
            await emitHz(detectionService, 220);
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      expect(controller.stage1Shruti, Pitch.e);
      expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
      await controller.reportNotComfortable();
      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.e);

      pass = 1;
      await controller.tryAgain();

      // Fresh Stage 1 + Stage 2: smart-start to A, then comfort prompt on A.
      expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
      expect(controller.isExploringRange, isTrue);
      expect(controller.stage1Shruti, Pitch.a);
      expect(controller.lastComfortableShruti, isNull);
      expect(controller.currentExploreCandidate, Pitch.a);
      expect(listenCountPass1, 2);
    },
  );

  test('Stage 2 playback does not enable pitch analysis', () async {
    late final AssistModeController controller;
    var analysisDuringPlay = true;

    controller = AssistModeController(
      detectionService: detectionService,
      audioService: audioService,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      prepareAudioSession: () async {},
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.playingReference &&
              controller.isExploringRange) {
            analysisDuringPlay = controller.isPitchAnalysisEnabled;
          }
          if (phase == AssistUiPhase.listening) {
            await emitPitch(
              detectionService,
              controller.isExploringRange
                  ? (controller.currentExploreCandidate ?? Pitch.cSharp)
                  : Pitch.cSharp,
            );
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(analysisDuringPlay, isFalse);
    expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
  });

  test('candidate cannot advance without a successful match', () async {
    final controller = buildExploringController(
      stage1Pitch: Pitch.cSharp,
      onExploreListening: (c) async {
        // Always fail Stage 2 match.
        await emitPitch(detectionService, Pitch.a);
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
    expect(controller.lastComfortableShruti, isNull);
    // Never advanced past the unmatched starting candidate.
    expect(controller.currentExploreCandidate, Pitch.cSharp);
  });

  test(
    'first Stage 2 not-comfortable still recommends Stage 1 starting Shruti',
    () async {
      final controller = buildExploringController(stage1Pitch: Pitch.f);
      addTearDown(controller.dispose);

      await controller.startSession();
      expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
      expect(controller.lastComfortableShruti, isNull);

      await controller.reportNotComfortable();

      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.f);
    },
  );
}
