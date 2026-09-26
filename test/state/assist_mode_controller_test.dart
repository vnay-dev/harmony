import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/nearest_supported_shruti.dart';
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
    countdownStepDuration: Duration.zero,
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

  /// Completes Stage 2 with a valid recommendation: first candidate Upper Sa
  /// Comfortable, next candidate Upper Sa Strained → final = first.
  ///
  /// If the first candidate is already the top supported Shruti (B), Comfortable
  /// alone completes the session.
  Future<void> finishStage2WithoutClimbing(
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
          phase == AssistUiPhase.retry ||
          phase == AssistUiPhase.rangeUnresolved) {
        return;
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  AssistModeController buildController({
    required FakePitchDetectionService service,
    required Future<void> Function(Duration duration) wait,
    FakeAudioService? audio,
    AssistTimingConfig timing = fastTiming,
    TargetPitchMatcher? targetMatcher,
    Pitch initialReferencePitch = Pitch.c,
  }) {
    return AssistModeController(
      detectionService: service,
      audioService: audio ?? audioService,
      candidateFinder: buildFinder(),
      targetMatcher: targetMatcher ?? buildMatcher(),
      referenceSoundGenerator: referenceSound,
      timing: timing,
      initialReferencePitch: initialReferencePitch,
      wait: wait,
      prepareAudioSession: () async {},
    );
  }

  Future<void> Function(Duration) phasedWait(
    AssistModeController Function() controllerOf, {
    Future<void> Function(AssistUiPhase phase)? onPhase,
  }) {
    return (duration) async {
      final controller = controllerOf();
      final phase = controller.uiPhase;
      if (phase == AssistUiPhase.listening && controller.isExploringRange) {
        final hz = controller.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      }
      if (onPhase != null) {
        await onPhase(phase);
      }
    };
  }

  setUp(() {
    detectionService = FakePitchDetectionService();
    audioService = FakeAudioService();
    referenceSound = FakeReferenceSoundGenerator();
  });

  test('intro is shown before a session begins', () {
    final controller = buildController(
      service: detectionService,
      wait: (_) async {},
    );
    addTearDown(controller.dispose);

    expect(controller.uiPhase, AssistUiPhase.intro);
    expect(controller.isSessionActive, isFalse);
    expect(controller.isPitchAnalysisEnabled, isFalse);
  });

  test('Assist Mode starts without playing Tanpura', () async {
    late final AssistModeController controller;
    var tanpuraPlayedDuringStage1 = false;
    var sawStage1Listening = false;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (!controller.isExploringRange) {
            if (audioService.isPlaying || audioService.loadCount > 0) {
              tanpuraPlayedDuringStage1 = true;
            }
            if (phase == AssistUiPhase.listening) {
              sawStage1Listening = true;
              await emitPitch(detectionService, Pitch.g);
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(sawStage1Listening, isTrue);
    expect(tanpuraPlayedDuringStage1, isFalse);
    expect(controller.stage, AssistStage.exploringRange);
    expect(controller.stage1Shruti, Pitch.g);
  });

  test('initial discovery listens directly to the microphone', () async {
    late final AssistModeController controller;
    var micOnDuringStage1Listen = false;
    var analysisOnDuringStage1Listen = false;
    var referencePlayingDuringStage1Listen = false;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            micOnDuringStage1Listen = detectionService.isListening;
            analysisOnDuringStage1Listen = controller.isPitchAnalysisEnabled;
            referencePlayingDuringStage1Listen = controller.isReferencePlaying;
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(micOnDuringStage1Listen, isTrue);
    expect(analysisOnDuringStage1Listen, isTrue);
    expect(referencePlayingDuringStage1Listen, isFalse);
    expect(controller.stage1Shruti, Pitch.e);
  });

  test('no reference audio is played during initial discovery', () async {
    late final AssistModeController controller;
    var audioPlayingInStage1 = false;
    var synthPlayingInStage1 = false;
    var sawPlayingReferenceInStage1 = false;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (!controller.isExploringRange) {
            if (phase == AssistUiPhase.playingReference) {
              sawPlayingReferenceInStage1 = true;
            }
            if (audioService.isPlaying) {
              audioPlayingInStage1 = true;
            }
            if (referenceSound.isPlaying) {
              synthPlayingInStage1 = true;
            }
            if (phase == AssistUiPhase.listening) {
              await emitPitch(detectionService, Pitch.d);
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(sawPlayingReferenceInStage1, isFalse);
    expect(audioPlayingInStage1, isFalse);
    expect(synthPlayingInStage1, isFalse);
    expect(controller.isExploringRange, isTrue);
  });

  test(
    'stable voice candidate is accepted and mapped to nearest Shruti',
    () async {
      late final AssistModeController controller;
      // ~196 Hz ≈ G3.
      const voiceHz = 196.0;
      final expected = nearestSupportedShruti(voiceHz);

      controller = buildController(
        service: detectionService,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening &&
                !controller.isExploringRange) {
              await emitHz(detectionService, voiceHz);
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      expect(expected, isNotNull);
      expect(expected!.pitch, Pitch.g);
      expect(controller.stage1Shruti, Pitch.g);
      expect(controller.referencePitch, Pitch.g);
      expect(controller.currentExploreCandidate, Pitch.g);
      expect(controller.stage, AssistStage.exploringRange);
      // Starting point only — not a completed final Shruti.
      expect(controller.uiPhase, isNot(AssistUiPhase.completed));
    },
  );

  test('detected Shruti is only a Stage 2 starting point, not final', () async {
    late final AssistModeController controller;
    Pitch? stage1AtEntry;
    var completedImmediatelyAfterStage1 = false;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.a);
          }
          if (phase == AssistUiPhase.startingPointFound) {
            stage1AtEntry = controller.stage1Shruti;
            completedImmediatelyAfterStage1 =
                controller.uiPhase == AssistUiPhase.completed;
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(stage1AtEntry, Pitch.a);
    expect(completedImmediatelyAfterStage1, isFalse);
    expect(controller.isExploringRange, isTrue);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(controller.lastComfortableShruti, isNull);
  });

  test('initial discovery transitions into existing Stage 2', () async {
    late final AssistModeController controller;
    final phases = <AssistUiPhase>[];

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          phases.add(phase);
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.f);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(phases, contains(AssistUiPhase.listening));
    expect(phases, contains(AssistUiPhase.processing));
    expect(phases, contains(AssistUiPhase.startingPointFound));
    expect(controller.stage, AssistStage.exploringRange);
    expect(controller.stage1Shruti, Pitch.f);
    expect(controller.currentRangePoint, AssistRangePoint.lowerSa);
    expect(controller.rangeTargets, isNotNull);
    expect(controller.uiPhase, AssistUiPhase.awaitingLowerAudibility);
  });

  test('one stable Stage 1 listen is enough to enter Stage 2', () async {
    late final AssistModeController controller;
    var stage1ListenCount = 0;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            if (!controller.isExploringRange) {
              stage1ListenCount += 1;
              await emitPitch(detectionService, Pitch.c);
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(stage1ListenCount, 1);
    expect(controller.stage1Shruti, Pitch.c);
    expect(controller.isExploringRange, isTrue);
    expect(controller.isVerifying, isFalse);
  });

  test('completion keeps the confirmed Shruti playing', () async {
    late final AssistModeController controller;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.d);
    expect(controller.isReferencePlaying, isTrue);
    expect(audioService.isPlaying, isTrue);
    expect(audioService.currentAsset, AudioAssets.sampleFor(Pitch.d));
  });

  test('stable C input becomes Stage 2 starting point C', () async {
    late final AssistModeController controller;
    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.c);
  });

  test('stable C# input becomes Stage 2 starting point C#', () async {
    late final AssistModeController controller;
    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.cSharp);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('stable E input becomes Stage 2 starting point E', () async {
    late final AssistModeController controller;
    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.e);
  });

  test('220 Hz voice maps to A as Stage 2 starting point', () async {
    late final AssistModeController controller;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitHz(detectionService, 220);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.a);
    expect(
      controller.referenceFrequencyHz,
      closeTo(frequencyHzForPitch(Pitch.a), 0.5),
    );
  });

  test('candidate accepted before timeout yields success', () async {
    late final AssistModeController controller;
    final phases = <AssistUiPhase>[];

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          phases.add(phase);
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);

    expect(phases, contains(AssistUiPhase.listening));
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.d);
  });

  test(
    'candidate accepted at the same time as timeout still succeeds',
    () async {
      late final AssistModeController controller;

      controller = buildController(
        service: detectionService,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening &&
                !controller.isExploringRange) {
              await emitPitch(detectionService, Pitch.e);
              detectionService.emit(PitchReading.none);
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      await finishStage2WithoutClimbing(controller);

      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.e);
    },
  );

  test('timeout before candidate yields retry', () async {
    late final AssistModeController controller;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            detectionService.emit(PitchReading.none);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.stage, AssistStage.findingStart);
    expect(controller.stage1Shruti, isNull);
    expect(controller.stage1FailureCount, 1);
  });

  test('Stage 1 countdown runs before listening when configured', () async {
    late final AssistModeController controller;
    final phases = <AssistUiPhase>[];
    final countdownValues = <int?>[];

    controller = buildController(
      service: detectionService,
      timing: const AssistTimingConfig(
        referencePlayDuration: Duration(milliseconds: 1),
        settlingDuration: Duration(milliseconds: 1),
        listenDuration: Duration(milliseconds: 1),
        transitionDuration: Duration(milliseconds: 1),
        countdownStepDuration: Duration(milliseconds: 1),
      ),
      wait: (duration) async {
        phases.add(controller.uiPhase);
        if (controller.uiPhase == AssistUiPhase.countdown) {
          countdownValues.add(controller.countdownValue);
        }
        if (controller.uiPhase == AssistUiPhase.listening &&
            !controller.isExploringRange) {
          await emitPitch(detectionService, Pitch.g);
        }
        if (controller.uiPhase == AssistUiPhase.listening &&
            controller.isExploringRange) {
          final hz = controller.currentRangeTargetHz;
          if (hz != null) {
            await emitHz(detectionService, hz);
          }
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(phases, contains(AssistUiPhase.countdown));
    expect(countdownValues.take(3).toList(), <int>[3, 2, 1]);
    expect(controller.stage1Shruti, Pitch.g);
  });

  test('second Stage 1 failure arms guided demo before next listen', () async {
    late final AssistModeController controller;
    var listens = 0;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            listens += 1;
            detectionService.emit(PitchReading.none);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.stage1FailureCount, 1);
    expect(controller.stage1GuidedDemoPending, isFalse);
    expect(controller.teachingLevel, TutorTeachingLevel.retryOnce);

    await controller.retryRound();
    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.stage1FailureCount, 2);
    expect(controller.stage1GuidedDemoPending, isTrue);
    expect(controller.teachingLevel, TutorTeachingLevel.guided);
    expect(listens, 2);
  });

  test('silence never accepts a starting point and yields retry', () async {
    late final AssistModeController controller;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            detectionService.emit(PitchReading.none);
            detectionService.emit(const PitchReading(hasPitch: false));
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.stage1Shruti, isNull);
  });

  test('invalid pitch yields retry', () async {
    late final AssistModeController controller;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            detectionService.emit(
              const PitchReading(hasPitch: true, frequencyHz: -1),
            );
            detectionService.emit(
              const PitchReading(hasPitch: true, frequencyHz: double.nan),
            );
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.stage1Shruti, isNull);
  });

  test('unstable pitch triggers retry', () async {
    late final AssistModeController controller;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.d, count: 2);
            await emitPitch(detectionService, Pitch.e, count: 2);
            await emitPitch(detectionService, Pitch.f, count: 2);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.stage1Shruti, isNull);
  });

  test('retry resets candidate finder and listens again', () async {
    late final AssistModeController controller;
    var stage1ListenCount = 0;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            stage1ListenCount += 1;
            if (stage1ListenCount == 1) {
              // Unstable — force retry.
              await emitPitch(detectionService, Pitch.d, count: 2);
              await emitPitch(detectionService, Pitch.e, count: 2);
            } else {
              await emitPitch(detectionService, Pitch.g);
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.stage1Shruti, isNull);
    expect(stage1ListenCount, 1);

    await controller.retryRound();

    expect(stage1ListenCount, 2);
    expect(controller.stage1Shruti, Pitch.g);
    expect(controller.isExploringRange, isTrue);
  });

  test(
    'low detected F0 below C maps to nearest Shruti, not default C',
    () async {
      late final AssistModeController controller;
      final belowC = frequencyHzForPitch(Pitch.c) * math.pow(2, -150 / 1200);
      final expected = nearestSupportedShruti(belowC.toDouble());

      controller = buildController(
        service: detectionService,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening &&
                !controller.isExploringRange) {
              await emitHz(detectionService, belowC.toDouble());
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      await finishStage2WithoutClimbing(controller);

      expect(expected, isNotNull);
      expect(controller.referencePitch, isNot(Pitch.c));
      expect(controller.referencePitch, expected!.pitch);
    },
  );

  test(
    'accepted candidate is not overwritten by stop/none failure path',
    () async {
      late final AssistModeController controller;
      final aHz = frequencyHzForPitch(Pitch.a);

      controller = buildController(
        service: detectionService,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening &&
                !controller.isExploringRange) {
              await emitHz(detectionService, aHz);
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      await finishStage2WithoutClimbing(controller);

      expect(controller.uiPhase, isNot(AssistUiPhase.retry));
      expect(detectionService.stopCount, greaterThan(0));
      expect(controller.referencePitch, Pitch.a);
    },
  );

  test('stopSession cancels timers and returns to intro', () async {
    late final AssistModeController controller;
    var waitCalls = 0;

    controller = buildController(
      service: detectionService,
      timing: const AssistTimingConfig(
        referencePlayDuration: Duration(seconds: 30),
        settlingDuration: Duration(seconds: 30),
        listenDuration: Duration(seconds: 30),
        transitionDuration: Duration(seconds: 30),
        countdownStepDuration: Duration.zero,
      ),
      wait: (duration) async {
        waitCalls += 1;
        if (waitCalls == 1) {
          expect(controller.uiPhase, AssistUiPhase.listening);
          expect(controller.isExploringRange, isFalse);
          await controller.stopSession();
        }
      },
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.intro);
    expect(controller.isSessionActive, isFalse);
    expect(controller.isPitchAnalysisEnabled, isFalse);
    expect(detectionService.isListening, isFalse);
    expect(audioService.isPlaying, isFalse);
    expect(controller.currentRound, 0);
  });

  test('reference pitch does not change during Stage 1 listening', () async {
    late final AssistModeController controller;
    Pitch? referenceWhileListening;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.e);
            referenceWhileListening = controller.referencePitch;
            await controller.stopSession();
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(referenceWhileListening, Pitch.c);
  });

  test('tryAgain from completion resets Assist session state', () async {
    late final AssistModeController controller;
    var listenCount = 0;
    var allowSecondSearch = false;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            listenCount += 1;
            if (!allowSecondSearch && !controller.isExploringRange) {
              await emitPitch(detectionService, Pitch.e);
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.e);
    expect(controller.isReferencePlaying, isTrue);
    final listensBeforeRetry = listenCount;

    allowSecondSearch = true;
    final tryAgainFuture = controller.tryAgain();
    await Future<void>.delayed(Duration.zero);
    await controller.stopSession();
    await tryAgainFuture;

    expect(controller.uiPhase, AssistUiPhase.intro);
    expect(controller.isSessionActive, isFalse);
    expect(controller.referencePitch, Pitch.c);
    expect(controller.referenceFrequencyHz, isNull);
    expect(controller.isVerifying, isFalse);
    expect(controller.currentRound, 0);
    expect(controller.isReferencePlaying, isFalse);
    expect(audioService.isPlaying, isFalse);
    expect(listensBeforeRetry, greaterThan(0));
  });

  test('tryAgain starts a fresh listening session', () async {
    late final AssistModeController controller;
    var session = 0;
    final phasesBySession = <int, List<AssistUiPhase>>{};

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          phasesBySession.putIfAbsent(session, () => <AssistUiPhase>[]);
          phasesBySession[session]!.add(phase);
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.d);

    session = 1;
    await controller.tryAgain();
    await finishStage2WithoutClimbing(controller);

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(phasesBySession[1], isNotNull);
    expect(phasesBySession[1], contains(AssistUiPhase.listening));
    // Stage 2 still plays reference tones after the new Stage 1 capture.
    expect(phasesBySession[1], contains(AssistUiPhase.playingReference));
  });

  test(
    'tryAgain clears previous confirmed Shruti from the new session',
    () async {
      late final AssistModeController controller;
      var pass = 0;
      Pitch? pitchWhileListeningAfterRetry;

      controller = buildController(
        service: detectionService,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening &&
                !controller.isExploringRange) {
              if (pass == 0) {
                await emitPitch(detectionService, Pitch.g);
              } else {
                pitchWhileListeningAfterRetry ??= controller.referencePitch;
                await emitPitch(detectionService, Pitch.a);
              }
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      await finishStage2WithoutClimbing(controller);
      expect(controller.referencePitch, Pitch.g);
      expect(controller.uiPhase, AssistUiPhase.completed);

      pass = 1;
      await controller.tryAgain();
      await finishStage2WithoutClimbing(controller);

      expect(pitchWhileListeningAfterRetry, Pitch.c);
      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.a);
    },
  );

  test('voice capture still works after tryAgain', () async {
    late final AssistModeController controller;
    var pass = 0;
    var stage1ListenCountPass1 = 0;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            if (pass == 0) {
              await emitPitch(detectionService, Pitch.e);
            } else {
              stage1ListenCountPass1 += 1;
              await emitHz(detectionService, 220);
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await finishStage2WithoutClimbing(controller);
    expect(controller.referencePitch, Pitch.e);

    pass = 1;
    await controller.tryAgain();
    await finishStage2WithoutClimbing(controller);

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.a);
    expect(stage1ListenCountPass1, 1);
  });

  test(
    'stale wait from completed session cannot restore completion after tryAgain',
    () async {
      late final AssistModeController controller;
      final pendingWaits = <Completer<void>>[];
      var releaseWaits = true;

      Future<void> enqueueWait(Duration duration) async {
        final gate = Completer<void>();
        pendingWaits.add(gate);
        if (releaseWaits) {
          gate.complete();
        }
        await gate.future;
      }

      controller = buildController(
        service: detectionService,
        wait: (duration) async {
          final phase = controller.uiPhase;
          if (phase == AssistUiPhase.listening) {
            if (controller.isExploringRange) {
              final hz = controller.currentRangeTargetHz;
              if (hz != null) {
                await emitHz(detectionService, hz);
              }
            } else {
              await emitPitch(detectionService, Pitch.f);
            }
          }
          await enqueueWait(duration);
        },
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      await finishStage2WithoutClimbing(controller);
      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.f);

      releaseWaits = false;
      pendingWaits.clear();
      final tryAgainFuture = controller.tryAgain();

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.uiPhase, isNot(AssistUiPhase.completed));
      expect(controller.referencePitch, isNot(Pitch.f));

      for (final gate in List<Completer<void>>.from(pendingWaits)) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      releaseWaits = true;
      for (final gate in List<Completer<void>>.from(pendingWaits)) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }
      await tryAgainFuture;
      await finishStage2WithoutClimbing(controller);

      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.f);
      expect(controller.isVerifying, isFalse);
    },
  );

  test('tryAgain is ignored when not on the completion screen', () async {
    final controller = buildController(
      service: detectionService,
      wait: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.tryAgain();
    expect(controller.uiPhase, AssistUiPhase.intro);
    expect(controller.isSessionActive, isFalse);
  });
}
