import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/state/drone_controller.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_session.dart';
import 'package:harmony/tutor/tutor_speech_recognizer.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice.dart';
import 'package:harmony/ui/components/tutor_action_button.dart';
import 'package:harmony/ui/components/tutor_presence_circle.dart';
import 'package:harmony/ui/screens/assist_mode_screen.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';
import '../support/fake_reference_sound_generator.dart';
import '../support/fake_tutor_sa_sample_player.dart';
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

  /// On-screen completion line after compliment celebration treatment.
  Finder findCelebratedCompletion(String shrutiLabel) {
    return find.text(
      'Wonderful 💙! We found a comfortable Shruti for you. '
      'Your Shruti is $shrutiLabel.',
      findRichText: true,
    );
  }

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
  /// Comfortable, next candidate Upper Sa Strained ??? final = first.
  Future<void> finishStage2WithoutClimbing(
    AssistModeController controller,
  ) async {
    var markedFirstComfortable = false;
    for (var i = 0; i < 64; i++) {
      final phase = controller.uiPhase;
      if (phase == AssistUiPhase.awaitingLowerAudibility) {
        await controller.reportLowerSaAudible();
      } else if (phase == AssistUiPhase.awaitingPaComfort) {
        await controller.reportPaComfortable();
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

  /// Taps Stage 1 / Stage 2 CTAs while the engine advances under a live TutorSession.
  Future<void> tapStage1PrimaryActions(
    WidgetTester tester, {
    int attempts = 80,
  }) async {
    for (var i = 0; i < attempts; i++) {
      for (final label in <String>[
        TutorScripts.ctaLetsBegin,
        TutorScripts.ctaImReadyToSingSa,
        TutorScripts.ctaImReady,
        TutorScripts.ctaLetsTryAgain,
        TutorScripts.ctaPlayTheSound,
      ]) {
        final button = find.text(label);
        if (button.evaluate().isNotEmpty) {
          await tester.tap(button);
          await tester.pump();
        }
      }
      await tester.pump();
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

    expect(find.text('Tutor Mode'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('tutor-home')), findsOneWidget);
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Start'), findsNothing);
    expect(find.textContaining('Hz'), findsNothing);
    expect(find.textContaining('cents'), findsNothing);
    expect(find.textContaining('Tanpura'), findsNothing);
  });

  testWidgets(
    'Stage 1 shows Listen to an example under the instruction before the CTA',
    (tester) async {
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

      final saTransport = FakeTutorSaClipTransport();
      final tutor = TutorSession(
        engine: controller,
        voice: FakeTutorVoice(),
        speechRecognizer: SilentTutorSpeechRecognizer(),
        timing: const TutorTimingConfig.instant(),
        wait: (_) async {},
        saSamplePlayer: buildFakeSaSamplePlayer(transport: saTransport),
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

      await tester.runAsync(() async {
        unawaited(tutor.begin());
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (tutor.primaryAction != TutorPrimaryAction.letsBegin &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await tutor.continuePrimaryAction();
        while (tutor.primaryAction != TutorPrimaryAction.imReadyToListen &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();

      expect(find.text(TutorScripts.firstStepInstruction), findsOneWidget);
      expect(find.text(TutorScripts.hearSaLabel), findsOneWidget);
      expect(find.text(TutorScripts.ctaImReadyToSingSa), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('tutor-hear-sa-play')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('tutor-hear-sa')));
      await tester.pumpAndSettle();
      expect(tutor.isHearSaPlaying, isTrue);
      expect(
        find.byKey(const ValueKey<String>('tutor-hear-sa-pause')),
        findsOneWidget,
      );

      await tester.tap(find.text(TutorScripts.ctaImReadyToSingSa));
      await tester.pump();
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while ((tutor.showHearSa || tutor.isHearSaPlaying) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text(TutorScripts.hearSaLabel), findsNothing);
      expect(tutor.isHearSaPlaying, isFalse);
      expect(saTransport.stopCount, greaterThan(0));

      holdListenPhase.complete();
    },
  );

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
      saSamplePlayer: buildFakeSaSamplePlayer(),
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
    expect(find.text(TutorScripts.stage1ListenPrompt), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pitch-direction-dial')),
      findsNothing,
      reason: 'Stage 1 has no target note for pitch direction',
    );
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

      expect(findCelebratedCompletion(Pitch.cSharp.label), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
        findsOneWidget,
      );
      expect(find.text(Pitch.cSharp.label), findsOneWidget);
      expect(find.byType(TutorPresenceCircle), findsOneWidget);
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

      expect(find.text('Tutor Mode'), findsOneWidget);
      expect(find.text('Start'), findsNothing);

      // Leave via Home without completing Tutor Mode.
      await tester.tap(find.byKey(const ValueKey<String>('tutor-home')));
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
        // First completion uses the shared helper; recreate with a pass-aware
        // wait so Try Again can capture a different Stage 1 pitch.
        late final AssistModeController first;
        first = AssistModeController(
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
            if (first.uiPhase == AssistUiPhase.listening) {
              emitForCurrentListen(
                detection,
                first,
                pass == 0 ? Pitch.cSharp : Pitch.a,
              );
            }
          },
        );
        assistController = first;
        await assistController.startSession();
        await finishStage2WithoutClimbing(assistController);
        expect(assistController.uiPhase, AssistUiPhase.completed);
        expect(assistController.referencePitch, Pitch.cSharp);
        expect(assistController.isExploringRange, isTrue);
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
      // Detach tutor hooks so engine.tryAgain is not gated by Stage 1 CTAs.
      assistController.tutorHooks = null;
      await tester.runAsync(() async {
        await assistController.tryAgain();
        await finishStage2WithoutClimbing(assistController);
      });
      expect(assistController.uiPhase, AssistUiPhase.completed);
      expect(assistController.referencePitch, Pitch.a);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('assist-play-my-shruti')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('assist-try-again')),
        findsOneWidget,
      );
      expect(find.text(Pitch.a.label), findsOneWidget);
      expect(find.text(Pitch.cSharp.label), findsNothing);
      expect(assistAudio.isPlaying, isTrue);

      // Still on Assist completion ??? Default Mode must be untouched.
      expect(drone.selectedPitch, Pitch.g);
      expect(drone.isPlaying, isFalse);

      final homeButton = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('tutor-home')),
      );
      homeButton.onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

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
    expect(
      find.text('Beautiful 💙! You did it.', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expect(find.textContaining('Hz'), findsNothing);
  });

  testWidgets(
    'Stage 2 reference screen shows listen instruction without CTAs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final detection = FakePitchDetectionService();
      final audio = FakeAudioService();
      final referenceSound = FakeReferenceSoundGenerator();
      late final AssistModeController controller;
      final holdReference = Completer<void>();

      controller = AssistModeController(
        detectionService: detection,
        audioService: audio,
        candidateFinder: buildFinder(),
        targetMatcher: buildMatcher(),
        referenceSoundGenerator: referenceSound,
        timing: const AssistTimingConfig(
          referencePlayDuration: Duration(days: 1),
          settlingDuration: Duration(milliseconds: 1),
          listenDuration: Duration(milliseconds: 1),
          transitionDuration: Duration(milliseconds: 1),
          countdownStepDuration: Duration.zero,
        ),
        initialReferencePitch: Pitch.c,
        prepareAudioSession: () async {},
        wait: (_) async {
          if (controller.uiPhase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            emitStable(detection, Pitch.cSharp);
            return;
          }
          if (controller.uiPhase == AssistUiPhase.playingReference &&
              controller.isExploringRange &&
              !holdReference.isCompleted) {
            await holdReference.future;
          }
        },
      );
      addTearDown(() async {
        holdReference.complete();
        await controller.stopSession();
        controller.dispose();
      });

      final tutor = TutorSession(
        engine: controller,
        voice: SilentTutorVoice(),
        speechRecognizer: SilentTutorSpeechRecognizer(),
        timing: const TutorTimingConfig.instant(),
        wait: (_) async {},
        saSamplePlayer: buildFakeSaSamplePlayer(),
      );
      void advancePrimary() {
        if (tutor.showPrimaryAction) {
          unawaited(tutor.continuePrimaryAction());
        }
      }

      tutor.addListener(advancePrimary);
      addTearDown(() {
        tutor.removeListener(advancePrimary);
        tutor.dispose();
      });

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
      await tester.pump();

      await tester.runAsync(() async {
        unawaited(controller.startSession());
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!(controller.isExploringRange &&
                controller.uiPhase == AssistUiPhase.playingReference) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.uiPhase, AssistUiPhase.playingReference);
      expect(referenceSound.isPlaying, isTrue);
      expect(find.text(TutorScripts.referenceListenPrompt), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-reference-listen-cue')),
        findsOneWidget,
      );
      expect(find.byIcon(Symbols.music_note_2), findsOneWidget);
      expect(find.text(TutorScripts.lowerSoundListenPrompt), findsNothing);
      expect(find.byType(TutorPresenceCircle), findsOneWidget);
      expect(find.byType(TutorActionButton), findsNothing);
    },
  );

  testWidgets(
    'Stage 2 shows Play the sound CTA after S74 before reference playback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final detection = FakePitchDetectionService();
      final audio = FakeAudioService();
      final referenceSound = FakeReferenceSoundGenerator();
      final holdReference = Completer<void>();
      late final AssistModeController controller;
      controller = AssistModeController(
        detectionService: detection,
        audioService: audio,
        candidateFinder: buildFinder(),
        targetMatcher: buildMatcher(),
        referenceSoundGenerator: referenceSound,
        timing: const AssistTimingConfig(
          referencePlayDuration: Duration(days: 1),
          settlingDuration: Duration(milliseconds: 1),
          listenDuration: Duration(milliseconds: 1),
          transitionDuration: Duration(milliseconds: 1),
          countdownStepDuration: Duration.zero,
        ),
        initialReferencePitch: Pitch.c,
        prepareAudioSession: () async {},
        wait: (_) async {
          if (controller.uiPhase == AssistUiPhase.listening &&
              !controller.isExploringRange) {
            emitStable(detection, Pitch.cSharp);
            return;
          }
          if (controller.uiPhase == AssistUiPhase.playingReference &&
              controller.isExploringRange &&
              !holdReference.isCompleted) {
            await holdReference.future;
          }
        },
      );
      addTearDown(() async {
        if (!holdReference.isCompleted) {
          holdReference.complete();
        }
        await controller.stopSession();
        controller.dispose();
      });

      final voice = FakeTutorVoice();
      final tutor = TutorSession(
        engine: controller,
        voice: voice,
        speechRecognizer: SilentTutorSpeechRecognizer(),
        timing: const TutorTimingConfig.instant(),
        wait: (_) async {},
        saSamplePlayer: buildFakeSaSamplePlayer(),
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
      await tester.pump();

      await tester.runAsync(() async {
        unawaited(controller.startSession());
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (tutor.primaryAction != TutorPrimaryAction.imReadyForNextStep &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await tutor.continuePrimaryAction();
        while (tutor.primaryAction != TutorPrimaryAction.playTheSound &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(TutorScripts.lowerSoundListenPrompt), findsOneWidget);
      expect(find.text(TutorScripts.ctaPlayTheSound), findsOneWidget);
      expect(find.byType(TutorActionButton), findsOneWidget);
      expect(find.text(TutorScripts.referenceListenPrompt), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('assist-reference-listen-cue')),
        findsNothing,
      );
      expect(referenceSound.playCount, 0);
      expect(controller.uiPhase, isNot(AssistUiPhase.playingReference));

      await tester.tap(find.text(TutorScripts.ctaPlayTheSound));
      await tester.pump();
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (controller.uiPhase != AssistUiPhase.playingReference &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(TutorScripts.ctaPlayTheSound), findsNothing);
      expect(find.text(TutorScripts.lowerSoundListenPrompt), findsNothing);
      expect(find.text(TutorScripts.referenceListenPrompt), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-reference-listen-cue')),
        findsOneWidget,
      );
      expect(referenceSound.playCount, greaterThan(0));
      expect(controller.uiPhase, AssistUiPhase.playingReference);

      // Cue must leave with the listen prompt — not linger into countdown.
      holdReference.complete();
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (controller.uiPhase == AssistUiPhase.playingReference &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(TutorScripts.referenceListenPrompt), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('assist-reference-listen-cue')),
        findsNothing,
      );
    },
  );

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
    expect(find.text(TutorScripts.stage1ListenPrompt), findsOneWidget);
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('pitch-direction-dial')),
      findsOneWidget,
    );
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
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('assist-playing-icon')),
      findsNothing,
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

    expect(findCelebratedCompletion(Pitch.cSharp.label), findsOneWidget);
    expect(find.text(Pitch.cSharp.label), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('assist-confirmed-shruti')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>('assist-shruti-celebration-${Pitch.cSharp.label}'),
      ),
      findsOneWidget,
    );
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
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
    expect(findCelebratedCompletion(Pitch.e.label), findsOneWidget);

    pass = 1;
    controller.tutorHooks = null;
    await tester.runAsync(() async {
      await controller.tryAgain();
      await finishStage2WithoutClimbing(controller);
    });
    await tester.pumpAndSettle();

    expect(sawClearedMidRestart, isTrue);
    expect(find.text(Pitch.e.label), findsNothing);
    expect(find.text(Pitch.a.label), findsOneWidget);
    expect(findCelebratedCompletion(Pitch.a.label), findsOneWidget);
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
    if (targetPhase == AssistUiPhase.awaitingPaComfort ||
        targetPhase == AssistUiPhase.awaitingUpperComfort) {
      await controller.reportLowerSaAudible();
    }
    if (targetPhase == AssistUiPhase.awaitingUpperComfort) {
      expect(controller.uiPhase, AssistUiPhase.awaitingPaComfort);
      await controller.reportPaComfortable();
    }
    expect(controller.uiPhase, targetPhase);
    return controller;
  }

  Future<TutorSession> openDifferentSoundChoice({
    required WidgetTester tester,
    required AssistModeController engine,
    required FakeTutorVoice voice,
  }) async {
    final tutor = TutorSession(
      engine: engine,
      voice: voice,
      speechRecognizer: SilentTutorSpeechRecognizer(),
      timing: const TutorTimingConfig.instant(),
      wait: (_) async {},
      saSamplePlayer: buildFakeSaSamplePlayer(),
    );
    void advancePrimary() {
      if (tutor.showPrimaryAction) {
        unawaited(tutor.continuePrimaryAction());
      }
    }

    tutor.addListener(advancePrimary);
    await tester.runAsync(() async {
      await tutor.begin();
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (!tutor.canAnswerDifferentSound &&
          DateTime.now().isBefore(deadline)) {
        if (tutor.showPrimaryAction) {
          await tutor.continuePrimaryAction();
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    tutor.removeListener(advancePrimary);
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
                      controller: engine,
                      tutorSession: tutor,
                      autoBegin: false,
                    ),
                  ),
                );
              },
              child: const Text('open-choice'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open-choice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return tutor;
  }

  AssistModeController engineThatMissesUntilChoice({
    required FakePitchDetectionService detection,
    required FakeAudioService audio,
    required bool Function() matchNearby,
  }) {
    late final AssistModeController engine;
    engine = AssistModeController(
      detectionService: detection,
      audioService: audio,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      referenceSoundGenerator: FakeReferenceSoundGenerator(),
      timing: fastTiming,
      initialReferencePitch: Pitch.c,
      prepareAudioSession: () async {},
      wait: (_) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging ||
            engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          emitStable(detection, Pitch.c);
          return;
        }
        if (!matchNearby()) {
          emitStableHz(detection, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          emitStableHz(detection, hz);
        }
      },
    );
    return engine;
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
      expect(find.text('Could you hear your voice clearly?'), findsOneWidget);
      expect(find.text(TutorScripts.ctaHeardClearly), findsOneWidget);
      expect(find.text(TutorScripts.ctaHardToHear), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      expect(find.byKey(const ValueKey<String>('tutor-home')), findsOneWidget);
      expect(find.byType(TutorPresenceCircle), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('assist-range-guide')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('assist-content-scroll')),
        findsNothing,
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
      expect(find.text(TutorScripts.ctaComfortable), findsOneWidget);
      expect(find.text(TutorScripts.ctaNotComfortable), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      expect(find.byKey(const ValueKey<String>('tutor-home')), findsOneWidget);
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
    expect(find.text(TutorScripts.ctaHeardClearly), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('assist-range-guide')),
      findsNothing,
    );

    await tester.runAsync(() async {
      await controller.reportLowerSaAudible();
    });
    await tester.pumpAndSettle();

    expectNoRenderOverflow(tester);
    expect(controller.uiPhase, AssistUiPhase.awaitingPaComfort);
    expect(find.text(TutorScripts.ctaComfortable), findsOneWidget);
    expect(find.text(TutorScripts.ctaNotComfortable), findsOneWidget);

    await tester.runAsync(() async {
      await controller.reportPaComfortable();
    });
    await tester.pumpAndSettle();

    expectNoRenderOverflow(tester);
    expect(controller.uiPhase, AssistUiPhase.awaitingUpperComfort);
    expect(find.text(TutorScripts.ctaComfortable), findsOneWidget);
    expect(find.text(TutorScripts.ctaNotComfortable), findsOneWidget);
  });

  testWidgets('Home replaces Stop and cancels the tutor session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
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
      wait: (_) async {},
      prepareAudioSession: () async {},
    );
    addTearDown(controller.dispose);

    final tutor = TutorSession(
      engine: controller,
      voice: FakeTutorVoice(),
      speechRecognizer: SilentTutorSpeechRecognizer(),
      timing: const TutorTimingConfig.instant(),
      wait: (_) async {},
      saSamplePlayer: buildFakeSaSamplePlayer(),
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
    await tester.pump();

    expect(find.text('Tutor Mode'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('tutor-home')), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.byType(BackButton), findsNothing);

    final homeButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('tutor-home')),
    );
    homeButton.onPressed!();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(tutor.step, TutorStep.stopped);
    expect(controller.isSessionActive, isFalse);
    expect(tutor.showStop, isFalse);
  });

  testWidgets(
    'Stage 1 keeps the calm tutor surface without a journey checklist',
    (tester) async {
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
        saSamplePlayer: buildFakeSaSamplePlayer(),
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
      expect(find.byKey(const ValueKey<String>('tutor-journey')), findsNothing);

      unawaited(controller.startSession());
      await tester.pump();
      await tester.pump();

      expect(controller.uiPhase, AssistUiPhase.listening);
      expect(controller.isExploringRange, isFalse);
      expect(find.byKey(const ValueKey<String>('tutor-journey')), findsNothing);
      expect(find.text(TutorScripts.stage1ListenPrompt), findsOneWidget);
      expect(find.byType(TutorPresenceCircle), findsOneWidget);

      holdListenPhase.complete();
      await tester.pump();
    },
  );

  testWidgets('Stage 2 does not show the journey checklist above the circle', (
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

    expect(controller.isExploringRange, isTrue);
    expect(find.byKey(const ValueKey<String>('tutor-journey')), findsNothing);
    expect(find.text('Finding your Shruti'), findsNothing);
    expect(find.text('Explore your range'), findsNothing);
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expectNoRenderOverflow(tester);
  });

  testWidgets(
    'completion keeps the circle surface without a journey checklist',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final detection = FakePitchDetectionService();
      final audio = FakeAudioService();
      late final AssistModeController controller;
      await tester.runAsync(() async {
        controller = await buildCompletedSession(
          detection: detection,
          audio: audio,
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

      expect(controller.uiPhase, AssistUiPhase.completed);
      expect(find.byKey(const ValueKey<String>('tutor-journey')), findsNothing);
      expect(find.text('Finding your Shruti'), findsNothing);
      expect(
        findCelebratedCompletion(controller.referencePitch.label),
        findsOneWidget,
      );
      expect(find.byType(TutorPresenceCircle), findsOneWidget);
    },
  );

  testWidgets('different-sound question shows enabled Yes, No, and Home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    final voice = FakeTutorVoice();
    var matchNearby = false;
    final engine = engineThatMissesUntilChoice(
      detection: detection,
      audio: audio,
      matchNearby: () => matchNearby,
    );
    addTearDown(engine.dispose);
    final tutor = await openDifferentSoundChoice(
      tester: tester,
      engine: engine,
      voice: voice,
    );
    addTearDown(tutor.dispose);

    expectNoRenderOverflow(tester);
    expect(find.text(TutorScripts.offerDifferentSound), findsOneWidget);
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.byKey(const ValueKey<String>('tutor-home')), findsOneWidget);
    expect(
      tester
          .widget<TutorActionButton>(
            find.byKey(const ValueKey<String>('assist-different-sound-yes')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TutorActionButton>(
            find.byKey(const ValueKey<String>('assist-different-sound-no')),
          )
          .onPressed,
      isNotNull,
    );

    matchNearby = true;
    await tester.tap(
      find.byKey(const ValueKey<String>('assist-different-sound-yes')),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (engine.uiPhase != AssistUiPhase.awaitingLowerAudibility &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(engine.currentExploreCandidate, Pitch.cSharp);
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(voice.spoken, isNot(contains("Lovely. Let's try this one.")));
  });

  testWidgets('No stays with the current sound for another practice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    final voice = FakeTutorVoice();
    var matchAfterDecline = false;
    final engine = engineThatMissesUntilChoice(
      detection: detection,
      audio: audio,
      matchNearby: () => matchAfterDecline,
    );
    addTearDown(engine.dispose);
    final tutor = await openDifferentSoundChoice(
      tester: tester,
      engine: engine,
      voice: voice,
    );
    addTearDown(tutor.dispose);

    matchAfterDecline = true;
    await tester.tap(
      find.byKey(const ValueKey<String>('assist-different-sound-no')),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (engine.uiPhase != AssistUiPhase.awaitingLowerAudibility &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(engine.currentExploreCandidate, Pitch.c);
    expect(
      voice.spoken.where((line) => line == TutorScripts.practiceTogether),
      hasLength(2),
    );
    expect(voice.spoken, contains(TutorScripts.stayWithThisSound));
  });

  testWidgets('Home leaves the different-sound question and cancels work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detection = FakePitchDetectionService();
    final audio = FakeAudioService();
    final voice = FakeTutorVoice();
    final engine = engineThatMissesUntilChoice(
      detection: detection,
      audio: audio,
      matchNearby: () => false,
    );
    addTearDown(engine.dispose);
    final tutor = await openDifferentSoundChoice(
      tester: tester,
      engine: engine,
      voice: voice,
    );
    addTearDown(tutor.dispose);

    final homeButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('tutor-home')),
    );
    homeButton.onPressed!();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('open-choice'), findsOneWidget);
    expect(find.text(TutorScripts.offerDifferentSound), findsNothing);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(tutor.canAnswerDifferentSound, isFalse);
    expect(tutor.step, TutorStep.stopped);

    await tester.runAsync(() => tutor.answerDifferentSound(true));
    await tester.pump();

    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
  });
}
