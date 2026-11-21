import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kittentts/kittentts.dart';

import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/theme/app_theme.dart';
import 'package:harmony/tutor/kitten_tts_bootstrap.dart';
import 'package:harmony/tutor/kitten_tutor_voice.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_speech_recognizer.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/ui/components/tutor_presence_circle.dart';
import 'package:harmony/ui/screens/assist_mode_screen.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';
import '../support/fake_reference_sound_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StablePitchCandidateFinder buildFinder() {
    return StablePitchCandidateFinder(
      minStableSamples: 4,
      stabilityTracker: PitchStabilityTracker(
        samplesToBecomeStable: 3,
        mismatchesToBecomeUnstable: 2,
      ),
    );
  }

  Future<void> pumpAssist(
    WidgetTester tester, {
    required KittenTtsBootstrap bootstrap,
    bool autoBegin = false,
  }) async {
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
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          kittenBootstrap: bootstrap,
          autoBegin: autoBegin,
          prepareAudioSession: () async {},
          wait: (_) async {},
        ),
      ),
    );
  }

  testWidgets('shows loading until Kitten bootstrap succeeds', (tester) async {
    final release = Completer<void>();
    var openCount = 0;
    final bootstrap = KittenTtsBootstrap(
      open:
          ({
            required KittenTTSConfig config,
            ProgressHandler? onProgress,
            bool forceRedownload = false,
          }) async {
            openCount += 1;
            onProgress?.call(0.4);
            await release.future;
            onProgress?.call(1);
            return _FakeSynthesizer();
          },
    );
    addTearDown(bootstrap.dispose);

    await pumpAssist(tester, bootstrap: bootstrap);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('kitten-tts-loading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kitten-tts-progress')),
      findsOneWidget,
    );
    expect(find.text('Preparing tutor voice…'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(
      find.textContaining("Hi, I'm Harmony", findRichText: true),
      findsNothing,
    );
    expect(find.byType(TutorPresenceCircle), findsNothing);
    expect(openCount, 1);

    release.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('kitten-tts-loading')),
      findsNothing,
    );
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expect(
      find.textContaining("Hi, I'm Harmony", findRichText: true),
      findsNothing,
    );
  });

  testWidgets('does not start tutor dialogue until bootstrap succeeds', (
    tester,
  ) async {
    final release = Completer<void>();
    final bootstrap = KittenTtsBootstrap(
      open:
          ({
            required KittenTTSConfig config,
            ProgressHandler? onProgress,
            bool forceRedownload = false,
          }) async {
            await release.future;
            return _FakeSynthesizer();
          },
    );
    addTearDown(bootstrap.dispose);

    await pumpAssist(tester, bootstrap: bootstrap, autoBegin: true);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('kitten-tts-loading')),
      findsOneWidget,
    );
    expect(
      find.textContaining("Hi, I'm Harmony", findRichText: true),
      findsNothing,
    );
    expect(find.text(TutorScripts.ctaLetsBegin), findsNothing);

    release.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('kitten-tts-loading')),
      findsNothing,
    );
    expect(
      find.textContaining("Hi, I'm Harmony", findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('shows error and Retry when bootstrap fails', (tester) async {
    var openCount = 0;
    final bootstrap = KittenTtsBootstrap(
      open:
          ({
            required KittenTTSConfig config,
            ProgressHandler? onProgress,
            bool forceRedownload = false,
          }) async {
            openCount += 1;
            throw StateError('offline');
          },
    );
    addTearDown(bootstrap.dispose);

    await pumpAssist(tester, bootstrap: bootstrap, autoBegin: true);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('kitten-tts-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('kitten-tts-retry')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Could not prepare the tutor voice.'),
      findsOneWidget,
    );
    expect(find.textContaining('offline'), findsOneWidget);
    expect(
      find.textContaining("Hi, I'm Harmony", findRichText: true),
      findsNothing,
    );
    expect(openCount, 1);
  });

  testWidgets('Retry recovers and then starts the tutor session', (
    tester,
  ) async {
    var openCount = 0;
    final bootstrap = KittenTtsBootstrap(
      open:
          ({
            required KittenTTSConfig config,
            ProgressHandler? onProgress,
            bool forceRedownload = false,
          }) async {
            openCount += 1;
            if (openCount == 1) {
              throw StateError('offline');
            }
            onProgress?.call(1);
            return _FakeSynthesizer();
          },
    );
    addTearDown(bootstrap.dispose);

    await pumpAssist(tester, bootstrap: bootstrap, autoBegin: false);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('kitten-tts-retry')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('kitten-tts-retry')));
    await tester.pumpAndSettle();

    expect(openCount, 2);
    expect(
      find.byKey(const ValueKey<String>('kitten-tts-error')),
      findsNothing,
    );
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
  });

  testWidgets('reuses a ready bootstrap without a second open', (tester) async {
    var openCount = 0;
    final bootstrap = KittenTtsBootstrap(
      open:
          ({
            required KittenTTSConfig config,
            ProgressHandler? onProgress,
            bool forceRedownload = false,
          }) async {
            openCount += 1;
            return _FakeSynthesizer();
          },
    );
    addTearDown(bootstrap.dispose);

    await bootstrap.ensureReady();
    expect(openCount, 1);

    await pumpAssist(tester, bootstrap: bootstrap);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(openCount, 1);
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('kitten-tts-loading')),
      findsNothing,
    );
  });

  testWidgets('Kitten is the default without useKittenTutorVoice', (
    tester,
  ) async {
    var openCount = 0;
    final bootstrap = KittenTtsBootstrap(
      open:
          ({
            required KittenTTSConfig config,
            ProgressHandler? onProgress,
            bool forceRedownload = false,
          }) async {
            openCount += 1;
            return _FakeSynthesizer();
          },
    );
    addTearDown(bootstrap.dispose);

    await pumpAssist(tester, bootstrap: bootstrap);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(openCount, 1);
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('kitten-tts-loading')),
      findsNothing,
    );
  });

  testWidgets('HTTP flag still wins over Kitten when both are set', (
    tester,
  ) async {
    var openCount = 0;
    final bootstrap = KittenTtsBootstrap(
      open:
          ({
            required KittenTTSConfig config,
            ProgressHandler? onProgress,
            bool forceRedownload = false,
          }) async {
            openCount += 1;
            return _FakeSynthesizer();
          },
    );
    addTearDown(bootstrap.dispose);

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
          speechRecognizer: SilentTutorSpeechRecognizer(),
          tutorTiming: const TutorTimingConfig.instant(),
          kittenBootstrap: bootstrap,
          useKittenTutorVoice: true,
          useHttpTutorVoice: true,
          autoBegin: false,
          prepareAudioSession: () async {},
          wait: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // HTTP path creates the session immediately; Kitten bootstrap is not used.
    expect(openCount, 0);
    expect(
      find.byKey(const ValueKey<String>('kitten-tts-loading')),
      findsNothing,
    );
    expect(find.byType(TutorPresenceCircle), findsOneWidget);
  });
}

class _FakeSynthesizer implements KittenTutorSynthesizer {
  @override
  Future<KittenTutorAudio> synthesize(String text) async {
    // Fail closed to text-only so widget tests never need real playback.
    throw StateError('test synthesizer is text-only');
  }

  @override
  Future<void> dispose() async {}
}
