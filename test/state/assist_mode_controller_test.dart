import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/audio/audio_assets.dart';
import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/nearest_supported_shruti.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/reference_pitch_adjuster.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
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

  AssistModeController buildController({
    required FakePitchDetectionService service,
    required Future<void> Function(Duration duration) wait,
    FakeAudioService? audio,
    AssistTimingConfig timing = fastTiming,
    ReferencePitchAdjuster? pitchAdjuster,
    Pitch initialReferencePitch = Pitch.c,
  }) {
    return AssistModeController(
      detectionService: service,
      audioService: audio ?? audioService,
      candidateFinder: buildFinder(),
      pitchAdjuster: pitchAdjuster,
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
      final phase = controllerOf().uiPhase;
      if (onPhase != null) {
        await onPhase(phase);
      }
    };
  }

  setUp(() {
    detectionService = FakePitchDetectionService();
    audioService = FakeAudioService();
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

  test('playback phase does not perform pitch analysis', () async {
    late final AssistModeController controller;
    var analysisDuringPlay = true;
    var micListeningDuringPlay = true;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.playingReference) {
            analysisDuringPlay = controller.isPitchAnalysisEnabled;
            micListeningDuringPlay = detectionService.isListening;
            await controller.stopSession();
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(analysisDuringPlay, isFalse);
    expect(micListeningDuringPlay, isFalse);
    expect(controller.uiPhase, AssistUiPhase.intro);
  });

  test('Tanpura stops before listening begins', () async {
    late final AssistModeController controller;
    var playingDuringSettle = true;
    var playingDuringListen = true;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.preparingToListen) {
            playingDuringSettle = audioService.isPlaying;
          }
          if (phase == AssistUiPhase.listening) {
            playingDuringListen = audioService.isPlaying;
            await controller.stopSession();
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(playingDuringSettle, isFalse);
    expect(playingDuringListen, isFalse);
  });

  test('far user pitch causes adjustment', () async {
    late final AssistModeController controller;
    final startHz = frequencyHzForPitch(Pitch.c);

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.referenceFrequencyHz, isNot(closeTo(startHz, 0.5)));
    expect(controller.referencePitch, isNot(Pitch.c));
  });

  test(
    'first stable voice pitch seeds nearest Shruti instead of walking from C',
    () async {
      late final AssistModeController controller;
      var listenCount = 0;
      Pitch? pitchAfterFirstListen;
      double? hzAfterFirstListen;

      controller = buildController(
        service: detectionService,
        initialReferencePitch: Pitch.c,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening) {
              listenCount += 1;
              await emitHz(detectionService, 220);
            }
            if (phase == AssistUiPhase.showingTransition &&
                pitchAfterFirstListen == null) {
              pitchAfterFirstListen = controller.referencePitch;
              hzAfterFirstListen = controller.referenceFrequencyHz;
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      expect(pitchAfterFirstListen, Pitch.a);
      expect(hzAfterFirstListen, closeTo(frequencyHzForPitch(Pitch.a), 0.5));
      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.a);
      // Converge + verify — no chromatic walk C→C#→…→A.
      expect(listenCount, 2);
    },
  );

  test('within tolerance does not adjust and enters verification', () async {
    late final AssistModeController controller;
    var sawVerifying = false;
    final startHz = frequencyHzForPitch(Pitch.c);

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.verifying) {
            sawVerifying = true;
          }
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(sawVerifying, isTrue);
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referenceFrequencyHz, closeTo(startHz, 0.5));
    expect(controller.referencePitch, Pitch.c);
  });

  test('successful verification completes the session', () async {
    late final AssistModeController controller;
    var listenCount = 0;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            listenCount += 1;
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(listenCount, 2); // adjust/converge listen + verify listen
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.isVerifying, isFalse);
  });

  test('completion keeps the confirmed Shruti playing', () async {
    late final AssistModeController controller;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.d);
          }
        },
      ),
      initialReferencePitch: Pitch.d,
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.d);
    expect(controller.isReferencePlaying, isTrue);
    expect(audioService.isPlaying, isTrue);
    expect(audioService.currentAsset, AudioAssets.sampleFor(Pitch.d));
  });

  test('failed verification returns to adjustment', () async {
    late final AssistModeController controller;
    var listenCount = 0;
    var sawAdjustAfterVerify = false;
    double? hzAfterFirstConverge;

    controller = buildController(
      service: detectionService,
      pitchAdjuster: ReferencePitchAdjuster(
        convergenceToleranceCents: 50,
        hysteresisCents: 0,
        maxStepCents: 100,
      ),
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            listenCount += 1;
            if (listenCount == 1) {
              // Match C → converge → enter verify.
              await emitPitch(detectionService, Pitch.c);
            } else if (listenCount == 2) {
              // Verify fails: sing far from C.
              hzAfterFirstConverge = controller.referenceFrequencyHz;
              await emitPitch(detectionService, Pitch.e);
            } else {
              // Continue toward E until done.
              await emitPitch(detectionService, Pitch.e);
              if (controller.referenceFrequencyHz != hzAfterFirstConverge) {
                sawAdjustAfterVerify = true;
              }
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(sawAdjustAfterVerify, isTrue);
    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, isNot(Pitch.c));
  });

  test('repeated identical user pitch eventually completes', () async {
    late final AssistModeController controller;
    var listenCount = 0;

    controller = buildController(
      service: detectionService,
      initialReferencePitch: Pitch.c,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            listenCount += 1;
            // Always the same comfortable note.
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.e);
    expect(listenCount, lessThan(20));
    expect(controller.isVerifying, isFalse);
  });

  test('stable C input confirms C', () async {
    late final AssistModeController controller;
    controller = buildController(
      service: detectionService,
      initialReferencePitch: Pitch.c,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.c);
  });

  test('stable C# input confirms C#', () async {
    late final AssistModeController controller;
    controller = buildController(
      service: detectionService,
      initialReferencePitch: Pitch.c,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.cSharp);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.cSharp);
  });

  test('stable E input confirms E', () async {
    late final AssistModeController controller;
    controller = buildController(
      service: detectionService,
      initialReferencePitch: Pitch.c,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.e);
    expect(
      controller.referenceFrequencyHz,
      closeTo(frequencyHzForPitch(Pitch.e), 1.0),
    );
  });

  test(
    'atBoundary while far from user does not confirm the stuck reference',
    () async {
      late final AssistModeController controller;
      final maxHz = frequencyHzForPitch(Pitch.b);
      final aboveMax = maxHz * math.pow(2, 150 / 1200).toDouble();
      var listenCount = 0;

      controller = buildController(
        service: detectionService,
        initialReferencePitch: Pitch.b,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening) {
              listenCount += 1;
              if (listenCount == 1) {
                // Seed initial candidate at B, then enter verification.
                await emitPitch(detectionService, Pitch.b);
              } else {
                // Verification: still far above the supported ceiling.
                await emitHz(detectionService, aboveMax);
              }
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      // Far from user at the range edge must not be treated as "found Shruti".
      expect(controller.uiPhase, AssistUiPhase.retry);
      expect(controller.referencePitch, Pitch.b);
      expect(controller.referenceFrequencyHz, closeTo(maxHz, 0.01));
    },
  );

  test(
    'stable A against default C adjusts upward (not false steady-note failure)',
    () async {
      late final AssistModeController controller;
      final aHz = frequencyHzForPitch(Pitch.a);

      controller = buildController(
        service: detectionService,
        initialReferencePitch: Pitch.c,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening) {
              await emitHz(detectionService, aHz);
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      // Must converge on A — not retry via atBoundary-at-C from octave folding.
      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.a);
      expect(controller.referenceFrequencyHz, closeTo(aHz, 1.0));
    },
  );

  test('candidate accepted before timeout yields success', () async {
    late final AssistModeController controller;
    final phases = <AssistUiPhase>[];

    controller = buildController(
      service: detectionService,
      initialReferencePitch: Pitch.c,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          phases.add(phase);
          if (phase == AssistUiPhase.listening) {
            await emitPitch(detectionService, Pitch.d);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

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
        initialReferencePitch: Pitch.c,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening) {
              // Candidate latch + listen-window end happen in one turn.
              // stop()-style none must not overwrite success into retry.
              await emitPitch(detectionService, Pitch.e);
              detectionService.emit(PitchReading.none);
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(controller.referencePitch, Pitch.e);
    },
  );

  test('timeout before candidate yields failure', () async {
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
    expect(controller.referencePitch, Pitch.c);
  });

  test(
    'accepted candidate is not overwritten by stop/none failure path',
    () async {
      late final AssistModeController controller;
      final aHz = frequencyHzForPitch(Pitch.a);

      controller = buildController(
        service: detectionService,
        initialReferencePitch: Pitch.c,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening) {
              await emitHz(detectionService, aHz);
              // FakePitchDetectionService.stop() emits none after listen;
              // that must not clear the latched candidate into retry.
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      expect(controller.uiPhase, isNot(AssistUiPhase.retry));
      expect(detectionService.stopCount, greaterThan(0));
      expect(
        controller.referenceFrequencyHz,
        greaterThan(frequencyHzForPitch(Pitch.c)),
      );
    },
  );

  test(
    'successful candidate reaches controller state with correct note/frequency',
    () async {
      late final AssistModeController controller;
      final eHz = frequencyHzForPitch(Pitch.e);
      Pitch? pitchAfterFirstAdjust;
      double? hzAfterFirstAdjust;

      controller = buildController(
        service: detectionService,
        initialReferencePitch: Pitch.c,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening) {
              await emitHz(detectionService, eHz);
            }
            if (phase == AssistUiPhase.showingTransition &&
                pitchAfterFirstAdjust == null) {
              pitchAfterFirstAdjust = controller.referencePitch;
              hzAfterFirstAdjust = controller.referenceFrequencyHz;
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      expect(pitchAfterFirstAdjust, isNotNull);
      expect(pitchAfterFirstAdjust, isNot(Pitch.c));
      expect(hzAfterFirstAdjust, isNotNull);
      expect(hzAfterFirstAdjust, greaterThan(frequencyHzForPitch(Pitch.c)));
      expect(hzAfterFirstAdjust, lessThanOrEqualTo(eHz + 0.5));
      expect(controller.uiPhase, isNot(AssistUiPhase.retry));
    },
  );

  test(
    'low detected F0 below C does not confirm default C as Shruti',
    () async {
      late final AssistModeController controller;
      // Below C3: octave-folds into the Sa band near A#/B — smart start must
      // not leave the session stuck on the hardcoded default C.
      final belowC = frequencyHzForPitch(Pitch.c) * math.pow(2, -150 / 1200);
      final expected = nearestSupportedShruti(belowC.toDouble());

      controller = buildController(
        service: detectionService,
        initialReferencePitch: Pitch.c,
        wait: phasedWait(
          () => controller,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening) {
              await emitHz(detectionService, belowC.toDouble());
            }
          },
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();

      expect(expected, isNotNull);
      expect(controller.referencePitch, isNot(Pitch.c));
      expect(controller.referencePitch, expected!.pitch);
    },
  );

  test('tiny pitch differences do not cause endless adjustment', () async {
    late final AssistModeController controller;
    var listenCount = 0;
    final ref = frequencyHzForPitch(Pitch.d);

    controller = buildController(
      service: detectionService,
      initialReferencePitch: Pitch.d,
      pitchAdjuster: ReferencePitchAdjuster(
        convergenceToleranceCents: 50,
        hysteresisCents: 20,
        maxStepCents: 100,
      ),
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            listenCount += 1;
            final wobbleCents = listenCount.isEven ? 15.0 : -18.0;
            final hz = ref * math.pow(2, wobbleCents / 1200).toDouble();
            await emitHz(detectionService, hz);
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.completed);
    expect(controller.referencePitch, Pitch.d);
    expect(listenCount, 2);
  });

  test('silence never changes the reference and yields retry', () async {
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
    expect(controller.referencePitch, Pitch.c);
    expect(controller.referenceFrequencyHz, frequencyHzForPitch(Pitch.c));
  });

  test('invalid pitch never changes the reference', () async {
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
    expect(controller.referencePitch, Pitch.c);
  });

  test('unstable pitch never changes the reference', () async {
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
    expect(controller.referencePitch, Pitch.c);
  });

  test('reference cannot climb indefinitely past supported range', () async {
    late final AssistModeController controller;
    final maxHz = frequencyHzForPitch(Pitch.b);
    final aboveMax = maxHz * math.pow(2, 150 / 1200).toDouble();
    final frequencies = <double>[];
    var listenCount = 0;

    controller = buildController(
      service: detectionService,
      initialReferencePitch: Pitch.b,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
            listenCount += 1;
            if (listenCount == 1) {
              await emitPitch(detectionService, Pitch.b);
            } else {
              await emitHz(detectionService, aboveMax);
            }
            final hz = controller.referenceFrequencyHz;
            if (hz != null) {
              frequencies.add(hz);
            }
          }
        },
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();

    expect(controller.uiPhase, AssistUiPhase.retry);
    expect(controller.referenceFrequencyHz, closeTo(maxHz, 0.01));
    expect(frequencies.every((hz) => hz <= maxHz + 0.01), isTrue);
  });

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
      ),
      wait: (duration) async {
        waitCalls += 1;
        if (waitCalls == 1) {
          expect(controller.uiPhase, AssistUiPhase.playingReference);
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

  test('reference cannot change during listening', () async {
    late final AssistModeController controller;
    Pitch? referenceWhileListening;

    controller = buildController(
      service: detectionService,
      wait: phasedWait(
        () => controller,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening) {
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
}
