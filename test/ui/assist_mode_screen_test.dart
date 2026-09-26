import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/state/drone_controller.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/tutor/tutor_session.dart';
import 'package:harmony/tutor/tutor_speech_recognizer.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice.dart';
import 'package:harmony/ui/screens/assist_mode_screen.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';
import '../support/fake_reference_sound_generator.dart';
import '../support/fake_tutor_voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  PitchReading voiced(Pitch pitch) {
    final hz = frequencyHzForPitch(pitch);
    return PitchReading(hasPitch: true, frequencyHz: hz, note: pitch);
  }

  PitchReading voicedHz(double hz) {
    return PitchReading(
      hasPitch: true,
      frequencyHz: hz,
      note: noteFromFrequency(hz),
    );
  }

  void emitStable(FakePitchDetectionService service, Pitch pitch) {
    for (var i = 0; i < 12; i++) {
      service.emit(voiced(pitch));
    }
  }

  void emitStableHz(FakePitchDetectionService service, double hz) {
    for (var i = 0; i < 12; i++) {
      service.emit(voicedHz(hz));
    }
  }

  void emitForCurrentListen(
    FakePitchDetectionService detection,
    AssistModeController controller,
    Pitch stage1Pitch,
  ) {
    if (!controller.isExploringRange) {
      emitStable(detection, stage1Pitch);
      return;
    }
    final hz = controller.currentRangeTargetHz;
    if (hz != null) {
      emitStableHz(detection, hz);
    }
  }

  /// Completes Stage 2 with a valid recommendation: first candidate Upper Sa
  /// Comfortable, next candidate Upper Sa Strained → final = first.
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

  Future<AssistModeController> buildCompletedSession({
    required FakePitchDetectionService detection,
    required FakeAudioService audio,
    Pitch pitch = Pitch.cSharp,
  }) async {
    late final AssistModeController controller;
    controller = AssistModeController(
      detectionService: detection,
      audioService: audio,
      candidateFinder: buildFinder(),
      targetMatcher: TargetPitchMatcher(
        toleranceCents: 50,
        samplesToMatch: 4,
        samplesToLoseMatch: 2,
        stabilityTracker: PitchStabilityTracker(
          samplesToBecomeStable: 3,
          mismatchesToBecomeUnstable: 2,
        ),
      ),
      referenceSoundGenerator: FakeReferenceSoundGenerator(),
      timing: fastTiming,
      initialReferencePitch: pitch,
      prepareAudioSession: () async {},
      wait: (_) async {
        if (controller.uiPhase == AssistUiPhase.listening) {
          emitForCurrentListen(detection, controller, pitch);
        }
      },
    );
    await controller.startSession();
    await finishStage2WithoutClimbing(controller);
    expect(controller.uiPhase, AssistUiPhase.completed);
    return controller;
  }

  testWidgets('shows welcome without requiring a Start tap', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          detectionService: FakePitchDetectionService(),
          audioService: FakeAudioService(),
          candidateFinder: buildFinder(),
          referenceSoundGenerator: FakeReferenceSoundGenerator(),
          tutorVoice: SilentTutorVoice(),
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          autoBegin: false,
          prepareAudioSession: () async {},
          wait: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Find your comfortable Shruti'), findsOneWidget);
    expect(find.text("I'll guide you. You just sing."), findsOneWidget);
    expect(find.text('Start'), findsNothing);
    expect(find.textContaining('Hz'), findsNothing);
    expect(find.textContaining('cents'), findsNothing);
    expect(find.textContaining('Tanpura'), findsNothing);
  });

  testWidgets('session listens without technical pitch details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final holdListenPhase = Completer<void>();
    late final AssistModeController controller;
    controller = AssistModeController(
      detectionService: FakePitchDetectionService(),
      audioService: FakeAudioService(),
      candidateFinder: buildFinder(),
      referenceSoundGenerator: FakeReferenceSoundGenerator(),
      timing: const AssistTimingConfig(
        referencePlayDuration: Duration(seconds: 30),
        settlingDuration: Duration(seconds: 30),
        listenDuration: Duration(seconds: 30),
        transitionDuration: Duration(seconds: 30),
        countdownStepDuration: Duration.zero,
      ),
      prepareAudioSession: () async {},
      wait: (_) => holdListenPhase.future,
    );
    addTearDown(controller.dispose);

    final tutor = TutorSession(
      engine: controller,
      voice: FakeTutorVoice(),
      speechRecognizer: SilentTutorSpeechRecognizer(),
      timing: const TutorTimingConfig.instant(),
      wait: (_) async {},
    );
    addTearDown(tutor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          controller: controller,
          tutorSession: tutor,
          autoBegin: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(controller.startSession());
    await tester.pump();
    await tester.pump();

    expect(controller.uiPhase, AssistUiPhase.listening);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.textContaining('Hz'), findsNothing);
    expect(find.textContaining('YIN'), findsNothing);
    expect(find.textContaining('cents'), findsNothing);
    expect(find.textContaining('Tanpura'), findsNothing);
    expect(find.text('Listen to your reference'), findsNothing);

    holdListenPhase.complete();
    await tester.pump();
  });

  testWidgets(
    'completion shows discovered Shruti, keeps playing, and uses Play My Shruti',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final detection = FakePitchDetectionService();
      final assistAudio = FakeAudioService();
      late final AssistModeController controller;
      await tester.runAsync(() async {
        controller = await buildCompletedSession(
          detection: detection,
          audio: assistAudio,
        );
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AssistModeScreen(
            controller: controller,
            tutorVoice: SilentTutorVoice(),
            speechRecognizer: SilentTutorSpeechRecognizer(),
            tutorTiming: const TutorTimingConfig.instant(),
            autoBegin: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('We found it'), findsOneWidget);
      expect(find.text('Your comfortable Shruti'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
        findsOneWidget,
      );
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(find.text('Play My Shruti'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-try-again')),
        findsOneWidget,
      );
      expect(find.text('Done'), findsNothing);
      expect(find.textContaining('Hz'), findsNothing);
      expect(assistAudio.isPlaying, isTrue);
      expect(controller.isReferencePlaying, isTrue);
    },
  );

  testWidgets(
    'Play My Shruti navigates to Default Mode with confirmed pitch autoplaying',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final droneAudio = FakeAudioService();
      final drone = DroneController(audioService: droneAudio);
      addTearDown(drone.dispose);
      await drone.initialize();
      await drone.selectPitch(Pitch.d);
      expect(drone.selectedPitch, Pitch.d);
      expect(drone.isPlaying, isFalse);

      final detection = FakePitchDetectionService();
      final assistAudio = FakeAudioService();
      late final AssistModeController assistController;
      await tester.runAsync(() async {
        assistController = await buildCompletedSession(
          detection: detection,
          audio: assistAudio,
        );
      });
      addTearDown(assistController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ListenableBuilder(
            listenable: drone,
            builder: (context, _) {
              return Scaffold(
                body: Column(
                  children: [
                    Text(
                      drone.selectedPitch.label,
                      key: const ValueKey<String>('default-selected-pitch'),
                    ),
                    Text(
                      drone.isPlaying ? 'playing' : 'paused',
                      key: const ValueKey<String>('default-playback'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final pitch = await Navigator.of(context).push<Pitch>(
                          MaterialPageRoute<Pitch>(
                            builder: (_) => AssistModeScreen(
                              controller: assistController,
                              tutorVoice: SilentTutorVoice(),
                              speechRecognizer: SilentTutorSpeechRecognizer(),
                              tutorTiming: const TutorTimingConfig.instant(),
                              autoBegin: false,
                            ),
                          ),
                        );
                        if (pitch != null) {
                          await drone.playPitch(pitch);
                        }
                      },
                      child: const Text('Find My Shruti'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(Pitch.d.label), findsOneWidget);

      await tester.tap(find.text('Find My Shruti'));
      await tester.pumpAndSettle();

      expect(find.text('Play My Shruti'), findsOneWidget);
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(assistAudio.isPlaying, isTrue);

      await tester.tap(find.text('Play My Shruti'));
      await tester.pumpAndSettle();

      expect(find.text('Find My Shruti'), findsOneWidget);
      expect(find.text('Play My Shruti'), findsNothing);
      expect(drone.selectedPitch, Pitch.cSharp);
      expect(drone.isPlaying, isTrue);
      expect(droneAudio.isPlaying, isTrue);
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(find.text('playing'), findsOneWidget);
    },
  );

  testWidgets(
    'abandoning Assist Mode before completion does not overwrite Default Mode',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final droneAudio = FakeAudioService();
      final drone = DroneController(audioService: droneAudio);
      addTearDown(drone.dispose);
      await drone.initialize();
      await drone.selectPitch(Pitch.g);

      final hold = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ListenableBuilder(
            listenable: drone,
            builder: (context, _) {
              return Scaffold(
                body: Column(
                  children: [
                    Text(drone.selectedPitch.label),
                    TextButton(
                      onPressed: () async {
                        final pitch = await Navigator.of(context).push<Pitch>(
                          MaterialPageRoute<Pitch>(
                            builder: (_) => AssistModeScreen(
                              detectionService: FakePitchDetectionService(),
                              audioService: FakeAudioService(),
                              candidateFinder: buildFinder(),
                              referenceSoundGenerator:
                                  FakeReferenceSoundGenerator(),
                              tutorVoice: SilentTutorVoice(),
                              speechRecognizer: SilentTutorSpeechRecognizer(),
                              tutorTiming: const TutorTimingConfig.instant(),
                              autoBegin: false,
                              timing: const AssistTimingConfig(
                                referencePlayDuration: Duration(seconds: 30),
                                settlingDuration: Duration(seconds: 30),
                                listenDuration: Duration(seconds: 30),
                                transitionDuration: Duration(seconds: 30),
                                countdownStepDuration: Duration.zero,
                              ),
                              prepareAudioSession: () async {},
                              wait: (_) => hold.future,
                            ),
                          ),
                        );
                        if (pitch != null) {
                          await drone.playPitch(pitch);
                        }
                      },
                      child: const Text('Find My Shruti'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Find My Shruti'));
      await tester.pumpAndSettle();

      expect(find.text('Find your comfortable Shruti'), findsOneWidget);
      expect(find.text('Start'), findsNothing);

      // Manually start since autoBegin is false.
      // Screen with autoBegin false stays on welcome — page back from welcome.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(drone.selectedPitch, Pitch.g);
      expect(drone.isPlaying, isFalse);
      expect(find.text(Pitch.g.label), findsOneWidget);

      hold.complete();
    },
  );

  testWidgets(
    'Try Again restarts Assist Mode without changing Default Mode selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final droneAudio = FakeAudioService();
      final drone = DroneController(audioService: droneAudio);
      addTearDown(drone.dispose);
      await drone.initialize();
      await drone.selectPitch(Pitch.g);
      expect(drone.selectedPitch, Pitch.g);
      expect(drone.isPlaying, isFalse);

      final detection = FakePitchDetectionService();
      final assistAudio = FakeAudioService();
      late final AssistModeController assistController;
      var pass = 0;

      await tester.runAsync(() async {
        assistController = AssistModeController(
          detectionService: detection,
          audioService: assistAudio,
          candidateFinder: buildFinder(),
          targetMatcher: TargetPitchMatcher(
            toleranceCents: 50,
            samplesToMatch: 4,
            samplesToLoseMatch: 2,
            stabilityTracker: PitchStabilityTracker(
              samplesToBecomeStable: 3,
              mismatchesToBecomeUnstable: 2,
            ),
          ),
          referenceSoundGenerator: FakeReferenceSoundGenerator(),
          timing: fastTiming,
          initialReferencePitch: Pitch.c,
          prepareAudioSession: () async {},
          wait: (_) async {
            if (assistController.uiPhase == AssistUiPhase.listening) {
              emitForCurrentListen(
                detection,
                assistController,
                pass == 0 ? Pitch.cSharp : Pitch.a,
              );
            }
          },
        );
        await assistController.startSession();
        await finishStage2WithoutClimbing(assistController);
        expect(assistController.uiPhase, AssistUiPhase.completed);
        expect(assistController.referencePitch, Pitch.cSharp);
      });
      addTearDown(assistController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ListenableBuilder(
            listenable: drone,
            builder: (context, _) {
              return Scaffold(
                body: Column(
                  children: [
                    Text(
                      drone.selectedPitch.label,
                      key: const ValueKey<String>('default-selected-pitch'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final pitch = await Navigator.of(context).push<Pitch>(
                          MaterialPageRoute<Pitch>(
                            builder: (_) => AssistModeScreen(
                              controller: assistController,
                              tutorVoice: SilentTutorVoice(),
                              speechRecognizer: SilentTutorSpeechRecognizer(),
                              tutorTiming: const TutorTimingConfig.instant(),
                              autoBegin: false,
                            ),
                          ),
                        );
                        if (pitch != null) {
                          await drone.playPitch(pitch);
                        }
                      },
                      child: const Text('Find My Shruti'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Find My Shruti'));
      await tester.pumpAndSettle();

      expect(find.text('Play My Shruti'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(assistAudio.isPlaying, isTrue);

      pass = 1;
      await tester.runAsync(() async {
        await assistController.tryAgain();
        await finishStage2WithoutClimbing(assistController);
      });
      await tester.pumpAndSettle();

      expect(find.text('Play My Shruti'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text(Pitch.a.label), findsOneWidget);
      expect(find.text(Pitch.cSharp.label), findsNothing);
      expect(assistController.referencePitch, Pitch.a);
      expect(assistAudio.isPlaying, isTrue);

      // Still on Assist completion — Default Mode must be untouched.
      expect(drone.selectedPitch, Pitch.g);
      expect(drone.isPlaying, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(drone.selectedPitch, Pitch.g);
      expect(drone.isPlaying, isFalse);
      expect(find.text(Pitch.g.label), findsOneWidget);
    },
  );

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

  testWidgets('Stage 1 result shows detected Shruti before Stage 2 begins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    late final AssistModeController controller;
    final holdForever = Completer<void>();

    await tester.runAsync(() async {
      controller = AssistModeController(
        detectionService: detection,
        audioService: audio,
        candidateFinder: buildFinder(),
        targetMatcher: buildMatcher(),
        referenceSoundGenerator: FakeReferenceSoundGenerator(),
        timing: fastTiming,
        initialReferencePitch: Pitch.c,
        prepareAudioSession: () async {},
        wait: (_) async {
          if (controller.uiPhase == AssistUiPhase.listening) {
            emitStable(detection, Pitch.cSharp);
          }
          if (controller.uiPhase == AssistUiPhase.startingPointFound) {
            await holdForever.future;
          }
        },
      );
      unawaited(controller.startSession());
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (controller.uiPhase == AssistUiPhase.startingPointFound) {
          break;
        }
      }
    });
    addTearDown(() async {
      await controller.stopSession();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          controller: controller,
          tutorVoice: SilentTutorVoice(),
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          autoBegin: false,
        ),
      ),
    );
    await tester.pump();

    expect(controller.uiPhase, AssistUiPhase.startingPointFound);
    expect(find.text('Lovely — I heard that'), findsOneWidget);
    expect(
      find.text("Now I'll find a comfortable range for you."),
      findsOneWidget,
    );
    expect(find.textContaining('Hz'), findsNothing);
  });

  testWidgets('Stage 2 listening hides the technical range guide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    late final AssistModeController controller;
    final holdListen = Completer<void>();

    await tester.runAsync(() async {
      controller = AssistModeController(
        detectionService: detection,
        audioService: audio,
        candidateFinder: buildFinder(),
        targetMatcher: buildMatcher(),
        referenceSoundGenerator: FakeReferenceSoundGenerator(),
        timing: fastTiming,
        initialReferencePitch: Pitch.c,
        prepareAudioSession: () async {},
        wait: (_) async {
          if (controller.uiPhase == AssistUiPhase.listening) {
            if (!controller.isExploringRange) {
              emitStable(detection, Pitch.cSharp);
              return;
            }
            // Hold on first Stage 2 listen so the guide is visible.
            if (controller.currentRangePoint == AssistRangePoint.lowerSa &&
                !holdListen.isCompleted) {
              await holdListen.future;
            }
            emitForCurrentListen(detection, controller, Pitch.cSharp);
          }
        },
      );
      unawaited(controller.startSession());
      for (var i = 0; i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (controller.isExploringRange &&
            controller.uiPhase == AssistUiPhase.listening &&
            controller.currentRangePoint == AssistRangePoint.lowerSa) {
          break;
        }
      }
    });
    addTearDown(() async {
      holdListen.complete();
      await controller.stopSession();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          controller: controller,
          tutorVoice: SilentTutorVoice(),
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          autoBegin: false,
        ),
      ),
    );
    await tester.pump();

    expect(controller.currentRangePoint, AssistRangePoint.lowerSa);
    expect(find.text(Pitch.cSharp.label), findsNothing);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Lower Sa'), findsNothing);
    expect(find.text('Low'), findsNothing);
    expect(find.text('Mid'), findsNothing);
    expect(find.text('High'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('assist-range-guide')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('tutor-exercise-dots')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('voice-activity-orb')),
      findsOneWidget,
    );
    expect(find.textContaining('Hz'), findsNothing);
  });

  testWidgets('Stage 2 completion shows the last comfortable Shruti', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    late final AssistModeController controller;

    await tester.runAsync(() async {
      controller = AssistModeController(
        detectionService: detection,
        audioService: audio,
        candidateFinder: buildFinder(),
        targetMatcher: buildMatcher(),
        referenceSoundGenerator: FakeReferenceSoundGenerator(),
        timing: fastTiming,
        initialReferencePitch: Pitch.c,
        prepareAudioSession: () async {},
        wait: (_) async {
          if (controller.uiPhase == AssistUiPhase.listening) {
            emitForCurrentListen(detection, controller, Pitch.cSharp);
          }
        },
      );
      await controller.startSession();
      await finishStage2WithoutClimbing(controller);
      expect(controller.uiPhase, AssistUiPhase.completed);
    });
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          controller: controller,
          tutorVoice: SilentTutorVoice(),
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          autoBegin: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('We found it'), findsOneWidget);
    expect(find.text('Your comfortable Shruti'), findsOneWidget);
    expect(find.text(Pitch.cSharp.label), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
      findsOneWidget,
    );
    expect(find.text('Could you hear and match the lower Sa?'), findsNothing);
    expect(find.textContaining('Hz'), findsNothing);
  });

  testWidgets('Try Again clears previous Shruti from the Assist UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    late final AssistModeController controller;
    var pass = 0;
    var sawClearedMidRestart = false;

    await tester.runAsync(() async {
      controller = AssistModeController(
        detectionService: detection,
        audioService: audio,
        candidateFinder: buildFinder(),
        targetMatcher: buildMatcher(),
        referenceSoundGenerator: FakeReferenceSoundGenerator(),
        timing: fastTiming,
        initialReferencePitch: Pitch.c,
        prepareAudioSession: () async {},
        wait: (_) async {
          if (pass == 1 &&
              !sawClearedMidRestart &&
              !controller.isExploringRange &&
              (controller.uiPhase == AssistUiPhase.playingReference ||
                  controller.uiPhase == AssistUiPhase.listening)) {
            expect(controller.stage1Shruti, isNull);
            expect(controller.currentExploreCandidate, isNull);
            expect(controller.currentRangePoint, isNull);
            sawClearedMidRestart = true;
          }
          if (controller.uiPhase == AssistUiPhase.listening) {
            emitForCurrentListen(
              detection,
              controller,
              pass == 0 ? Pitch.e : Pitch.a,
            );
          }
        },
      );
      await controller.startSession();
      await finishStage2WithoutClimbing(controller);
      expect(controller.referencePitch, Pitch.e);
      expect(controller.stage1Shruti, Pitch.e);
    });
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          controller: controller,
          tutorVoice: SilentTutorVoice(),
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          autoBegin: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text(Pitch.e.label), findsOneWidget);
    expect(find.text('We found it'), findsOneWidget);
    expect(find.text('Your comfortable Shruti'), findsOneWidget);

    pass = 1;
    await tester.runAsync(() async {
      await controller.tryAgain();
      await finishStage2WithoutClimbing(controller);
    });
    await tester.pumpAndSettle();

    expect(sawClearedMidRestart, isTrue);
    expect(find.text(Pitch.e.label), findsNothing);
    expect(find.text(Pitch.a.label), findsOneWidget);
    expect(find.text('We found it'), findsOneWidget);
    expect(find.text('Your comfortable Shruti'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
      findsOneWidget,
    );
    expect(controller.stage1Shruti, Pitch.a);
    expect(controller.referencePitch, Pitch.a);
  });

  Future<AssistModeController> buildSessionAtPhase({
    required FakePitchDetectionService detection,
    required FakeAudioService audio,
    required AssistUiPhase targetPhase,
    Pitch pitch = Pitch.cSharp,
  }) async {
    late final AssistModeController controller;
    controller = AssistModeController(
      detectionService: detection,
      audioService: audio,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      referenceSoundGenerator: FakeReferenceSoundGenerator(),
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      prepareAudioSession: () async {},
      wait: (_) async {
        if (controller.uiPhase == AssistUiPhase.listening) {
          emitForCurrentListen(detection, controller, pitch);
        }
      },
    );
    await controller.startSession();
    if (targetPhase == AssistUiPhase.awaitingUpperComfort) {
      await controller.reportLowerSaAudible();
    }
    expect(controller.uiPhase, targetPhase);
    return controller;
  }

  void expectNoRenderOverflow(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    // RenderFlex overflow paints a yellow/black stripe Text; ensure absent.
    expect(find.textContaining('OVERFLOWING'), findsNothing);
    expect(find.textContaining('Bottom overflowed'), findsNothing);
  }

  testWidgets(
    'Lower Sa audibility question fits on a small phone without overflow',
    (tester) async {
      // Compact Android-like size where the old Spacer Column overflowed ~59px.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final detection = FakePitchDetectionService();
      final audio = FakeAudioService();
      late final AssistModeController controller;

      await tester.runAsync(() async {
        controller = await buildSessionAtPhase(
          detection: detection,
          audio: audio,
          targetPhase: AssistUiPhase.awaitingLowerAudibility,
        );
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AssistModeScreen(
            controller: controller,
            tutorVoice: SilentTutorVoice(),
            speechRecognizer: SilentTutorSpeechRecognizer(),
            tutorTiming: const TutorTimingConfig.instant(),
            autoBegin: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectNoRenderOverflow(tester);
      expect(find.text('Could you hear that sound clearly?'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-range-guide')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('assist-content-scroll')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Upper Sa comfort question fits on a small phone without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final detection = FakePitchDetectionService();
      final audio = FakeAudioService();
      late final AssistModeController controller;

      await tester.runAsync(() async {
        controller = await buildSessionAtPhase(
          detection: detection,
          audio: audio,
          targetPhase: AssistUiPhase.awaitingUpperComfort,
        );
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AssistModeScreen(
            controller: controller,
            tutorVoice: SilentTutorVoice(),
            speechRecognizer: SilentTutorSpeechRecognizer(),
            tutorTiming: const TutorTimingConfig.instant(),
            autoBegin: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectNoRenderOverflow(tester);
      expect(find.text('How did that feel?'), findsOneWidget);
      expect(find.text('Comfortable'), findsOneWidget);
      expect(find.text('Not comfortable'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-range-guide')),
        findsNothing,
      );
    },
  );

  testWidgets('question states remain usable at standard phone size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    late final AssistModeController controller;

    await tester.runAsync(() async {
      controller = await buildSessionAtPhase(
        detection: detection,
        audio: audio,
        targetPhase: AssistUiPhase.awaitingLowerAudibility,
      );
    });
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          controller: controller,
          tutorVoice: SilentTutorVoice(),
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          autoBegin: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectNoRenderOverflow(tester);
    expect(find.text('Yes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('assist-range-guide')),
      findsNothing,
    );

    await tester.runAsync(() async {
      await controller.reportLowerSaAudible();
    });
    await tester.pumpAndSettle();

    expectNoRenderOverflow(tester);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
    expect(find.text('Comfortable'), findsOneWidget);
    expect(find.text('Not comfortable'), findsOneWidget);
  });

  testWidgets('stop shows a stopped state and removes the exercise dots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    final hold = Completer<void>();
    addTearDown(() {
      if (!hold.isCompleted) {
        hold.complete();
      }
    });
    final controller = AssistModeController(
      detectionService: detection,
      audioService: audio,
      candidateFinder: buildFinder(),
      targetMatcher: TargetPitchMatcher(
        toleranceCents: 50,
        samplesToMatch: 4,
        samplesToLoseMatch: 2,
        stabilityTracker: PitchStabilityTracker(
          samplesToBecomeStable: 3,
          mismatchesToBecomeUnstable: 2,
        ),
      ),
      referenceSoundGenerator: FakeReferenceSoundGenerator(),
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      wait: (_) => hold.future,
      prepareAudioSession: () async {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AssistModeScreen(
                      controller: controller,
                      tutorVoice: FakeTutorVoice(),
                      speechRecognizer: SilentTutorSpeechRecognizer(),
                      tutorTiming: const TutorTimingConfig.instant(),
                      autoBegin: true,
                    ),
                  ),
                );
              },
              child: const Text('open-assist'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open-assist'));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('tutor-exercise-dots')),
      findsNothing,
    );
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('assist-stop')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('assist-stop')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Session stopped'), findsOneWidget);
    expect(
      find.text("You can try again whenever you're ready."),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('assist-session-stopped-try-again')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('assist-stop')), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('tutor-exercise-dots')),
      findsNothing,
    );
  });
}
