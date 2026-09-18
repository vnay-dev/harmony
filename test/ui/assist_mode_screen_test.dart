import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
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
      timing: fastTiming,
      initialReferencePitch: pitch,
      prepareAudioSession: () async {},
      wait: (_) async {
        if (controller.uiPhase == AssistUiPhase.listening) {
          emitStable(detection, pitch);
        }
      },
    );
    await controller.startSession();
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

      expect(find.text('We found your comfortable Shruti'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
        findsOneWidget,
      );
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(find.text('Play My Shruti'), findsOneWidget);
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
}
