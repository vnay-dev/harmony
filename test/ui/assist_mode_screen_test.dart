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
import 'package:harmony/ui/screens/assist_mode_screen.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  PitchReading voiced(Pitch pitch) {
    final hz = frequencyHzForPitch(pitch);
    return PitchReading(hasPitch: true, frequencyHz: hz, note: pitch);
  }

  void emitStable(FakePitchDetectionService service, Pitch pitch) {
    for (var i = 0; i < 12; i++) {
      service.emit(voiced(pitch));
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
      timing: fastTiming,
      initialReferencePitch: pitch,
      prepareAudioSession: () async {},
      wait: (_) async {
        if (controller.uiPhase == AssistUiPhase.listening) {
          final target = controller.isExploringRange
              ? (controller.currentExploreCandidate ?? pitch)
              : pitch;
          emitStable(detection, target);
        }
      },
    );
    await controller.startSession();
    while (controller.uiPhase == AssistUiPhase.awaitingComfort) {
      await controller.reportNotComfortable();
    }
    expect(controller.uiPhase, AssistUiPhase.completed);
    return controller;
  }

  testWidgets('shows Assist introduction before Start', (tester) async {
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
          prepareAudioSession: () async {},
          wait: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Find your Shruti'), findsOneWidget);
    expect(
      find.text('Harmony will play a reference, then ask you to sing.'),
      findsOneWidget,
    );
    expect(find.text("You don't need to know your pitch."), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.textContaining('Hz'), findsNothing);
    expect(find.textContaining('cents'), findsNothing);
  });

  testWidgets('Start enters listen phase without technical pitch details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final holdPlayPhase = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssistModeScreen(
          detectionService: FakePitchDetectionService(),
          audioService: FakeAudioService(),
          candidateFinder: buildFinder(),
          timing: const AssistTimingConfig(
            referencePlayDuration: Duration(seconds: 30),
            settlingDuration: Duration(seconds: 30),
            listenDuration: Duration(seconds: 30),
            transitionDuration: Duration(seconds: 30),
          ),
          prepareAudioSession: () async {},
          wait: (_) => holdPlayPhase.future,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Listen to your reference'), findsOneWidget);
    expect(find.text('Relax and listen.'), findsOneWidget);
    expect(find.textContaining('Round'), findsOneWidget);
    expect(find.textContaining('Hz'), findsNothing);
    expect(find.textContaining('YIN'), findsNothing);
    expect(find.textContaining('cents'), findsNothing);
    expect(find.text('Find your Shruti'), findsNothing);

    holdPlayPhase.complete();
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
          home: AssistModeScreen(controller: controller),
        ),
      );
      await tester.pump();

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
                            builder: (_) =>
                                AssistModeScreen(controller: assistController),
                          ),
                        );
                        if (pitch != null) {
                          await drone.playPitch(pitch);
                        }
                      },
                      child: const Text('Assist Mode'),
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

      await tester.tap(find.text('Assist Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Play My Shruti'), findsOneWidget);
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(assistAudio.isPlaying, isTrue);

      await tester.tap(find.text('Play My Shruti'));
      await tester.pumpAndSettle();

      expect(find.text('Assist Mode'), findsOneWidget);
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
                              timing: const AssistTimingConfig(
                                referencePlayDuration: Duration(seconds: 30),
                                settlingDuration: Duration(seconds: 30),
                                listenDuration: Duration(seconds: 30),
                                transitionDuration: Duration(seconds: 30),
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
                      child: const Text('Assist Mode'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assist Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Find your Shruti'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Listen to your reference'), findsOneWidget);

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
          timing: fastTiming,
          initialReferencePitch: Pitch.c,
          prepareAudioSession: () async {},
          wait: (_) async {
            if (assistController.uiPhase == AssistUiPhase.listening) {
              final target = assistController.isExploringRange
                  ? (assistController.currentExploreCandidate ??
                        (pass == 0 ? Pitch.cSharp : Pitch.a))
                  : (pass == 0 ? Pitch.cSharp : Pitch.a);
              emitStable(detection, target);
            }
          },
        );
        await assistController.startSession();
        while (assistController.uiPhase == AssistUiPhase.awaitingComfort) {
          await assistController.reportNotComfortable();
        }
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
                            builder: (_) =>
                                AssistModeScreen(controller: assistController),
                          ),
                        );
                        if (pitch != null) {
                          await drone.playPitch(pitch);
                        }
                      },
                      child: const Text('Assist Mode'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assist Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Play My Shruti'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(assistAudio.isPlaying, isTrue);

      pass = 1;
      await tester.runAsync(() async {
        final restart = assistController.tryAgain();
        await tester.pump();
        await restart;
        while (assistController.uiPhase == AssistUiPhase.awaitingComfort) {
          await assistController.reportNotComfortable();
        }
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

  testWidgets(
    'Stage 1 result shows detected Shruti before Stage 2 begins',
    (tester) async {
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
          home: AssistModeScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(controller.uiPhase, AssistUiPhase.startingPointFound);
      expect(find.text('We found your match'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-prominent-shruti')),
        findsOneWidget,
      );
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(
        find.text('Now let\'s find your comfortable Shruti'),
        findsOneWidget,
      );
      expect(find.textContaining('Hz'), findsNothing);
    },
  );

  testWidgets(
    'Stage 2 comfort prompt shows current Shruti and Listen/Sing cues',
    (tester) async {
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
          timing: fastTiming,
          initialReferencePitch: Pitch.c,
          prepareAudioSession: () async {},
          wait: (_) async {
            if (controller.uiPhase == AssistUiPhase.listening) {
              emitStable(
                detection,
                controller.isExploringRange
                    ? (controller.currentExploreCandidate ?? Pitch.cSharp)
                    : Pitch.cSharp,
              );
            }
          },
        );
        await controller.startSession();
        expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AssistModeScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('assist-prominent-shruti')),
        findsOneWidget,
      );
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(find.text('How does C# feel?'), findsOneWidget);
      expect(find.text('Comfortable'), findsOneWidget);
      expect(find.text('Not comfortable'), findsOneWidget);
      expect(find.textContaining('Hz'), findsNothing);
    },
  );

  testWidgets(
    'Stage 2 keeps current Shruti visible and updates on comfortable step-up',
    (tester) async {
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
          timing: fastTiming,
          initialReferencePitch: Pitch.c,
          prepareAudioSession: () async {},
          wait: (_) async {
            if (controller.uiPhase == AssistUiPhase.listening) {
              emitStable(
                detection,
                controller.isExploringRange
                    ? (controller.currentExploreCandidate ?? Pitch.cSharp)
                    : Pitch.cSharp,
              );
            }
          },
        );
        await controller.startSession();
        expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
        expect(controller.currentExploreCandidate, Pitch.cSharp);
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AssistModeScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(find.text('How does C# feel?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-prominent-shruti')),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await controller.reportComfortable();
      });
      await tester.pumpAndSettle();

      expect(controller.uiPhase, AssistUiPhase.awaitingComfort);
      expect(controller.currentExploreCandidate, Pitch.d);
      expect(find.text(Pitch.d.label), findsOneWidget);
      expect(find.text(Pitch.cSharp.label), findsNothing);
      expect(find.text('How does D feel?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-prominent-shruti')),
        findsOneWidget,
      );
      expect(find.textContaining('Hz'), findsNothing);
      expect(find.textContaining('cents'), findsNothing);
    },
  );

  testWidgets(
    'Try Again clears previous Shruti from the Assist UI',
    (tester) async {
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
          timing: fastTiming,
          initialReferencePitch: Pitch.c,
          prepareAudioSession: () async {},
          wait: (_) async {
            // During Stage 1 of a restarted session, prior Stage 1/2 Shruti
            // state must already be cleared.
            if (pass == 1 &&
                !sawClearedMidRestart &&
                !controller.isExploringRange &&
                (controller.uiPhase == AssistUiPhase.playingReference ||
                    controller.uiPhase == AssistUiPhase.listening)) {
              expect(controller.stage1Shruti, isNull);
              expect(controller.currentExploreCandidate, isNull);
              sawClearedMidRestart = true;
            }
            if (controller.uiPhase == AssistUiPhase.listening) {
              final pitch = pass == 0
                  ? (controller.isExploringRange
                        ? (controller.currentExploreCandidate ?? Pitch.e)
                        : Pitch.e)
                  : (controller.isExploringRange
                        ? (controller.currentExploreCandidate ?? Pitch.a)
                        : Pitch.a);
              emitStable(detection, pitch);
            }
          },
        );
        await controller.startSession();
        while (controller.uiPhase == AssistUiPhase.awaitingComfort) {
          await controller.reportNotComfortable();
        }
        expect(controller.referencePitch, Pitch.e);
        expect(controller.stage1Shruti, Pitch.e);
      });
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AssistModeScreen(controller: controller),
        ),
      );
      await tester.pump();

      expect(find.text(Pitch.e.label), findsOneWidget);
      expect(find.text('Your comfortable Shruti'), findsOneWidget);

      pass = 1;
      await tester.runAsync(() async {
        await controller.tryAgain();
        while (controller.uiPhase == AssistUiPhase.awaitingComfort) {
          await controller.reportNotComfortable();
        }
      });
      await tester.pumpAndSettle();

      expect(sawClearedMidRestart, isTrue);
      expect(find.text(Pitch.e.label), findsNothing);
      expect(find.text(Pitch.a.label), findsOneWidget);
      expect(find.text('Your comfortable Shruti'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
        findsOneWidget,
      );
      expect(controller.stage1Shruti, Pitch.a);
      expect(controller.referencePitch, Pitch.a);
    },
  );
}
