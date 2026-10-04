import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_session.dart';
import 'package:harmony/tutor/tutor_timing.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';
import '../support/fake_reference_sound_generator.dart';
import '../support/fake_tutor_sa_sample_player.dart';
import '../support/fake_tutor_speech_recognizer.dart';
import '../support/fake_tutor_voice.dart';

void main() {
  late FakePitchDetectionService detectionService;
  late FakeAudioService audioService;
  late FakeReferenceSoundGenerator referenceSound;
  late FakeTutorVoice voice;
  late FakeTutorSpeechRecognizer speech;
  late FakeTutorSaClipTransport saTransport;

  const fastTiming = AssistTimingConfig(
    referencePlayDuration: Duration(milliseconds: 1),
    settlingDuration: Duration(milliseconds: 1),
    listenDuration: Duration(milliseconds: 1),
    transitionDuration: Duration(milliseconds: 1),
    countdownStepDuration: Duration.zero,
  );

  const countdownTiming = AssistTimingConfig(
    referencePlayDuration: Duration(milliseconds: 1),
    settlingDuration: Duration(milliseconds: 1),
    listenDuration: Duration(milliseconds: 1),
    transitionDuration: Duration(milliseconds: 1),
    countdownStepDuration: Duration(milliseconds: 1),
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

  AssistModeController buildEngine({
    required Future<void> Function(Duration duration) wait,
    AssistTimingConfig timing = fastTiming,
  }) {
    return AssistModeController(
      detectionService: detectionService,
      audioService: audioService,
      candidateFinder: buildFinder(),
      targetMatcher: buildMatcher(),
      referenceSoundGenerator: referenceSound,
      timing: timing,
      initialReferencePitch: Pitch.c,
      wait: wait,
      prepareAudioSession: () async {},
    );
  }

  TutorSession buildTutor(
    AssistModeController engine, {
    bool autoContinuePrimaryActions = true,
  }) {
    final tutor = TutorSession(
      engine: engine,
      voice: voice,
      speechRecognizer: speech,
      timing: const TutorTimingConfig.instant(),
      wait: (_) async {},
      saSamplePlayer: buildFakeSaSamplePlayer(transport: saTransport),
    );
    if (autoContinuePrimaryActions) {
      void advance() {
        if (tutor.showPrimaryAction) {
          unawaited(tutor.continuePrimaryAction());
        }
      }

      tutor.addListener(advance);
      addTearDown(() => tutor.removeListener(advance));
    }
    return tutor;
  }

  Future<void> waitUntil(
    bool Function() condition, {
    int attempts = 200,
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail('Condition not met in time');
  }

  Future<void> Function(Duration) phasedWait(
    AssistModeController Function() engineOf, {
    Future<void> Function(AssistUiPhase phase)? onPhase,
  }) {
    return (duration) async {
      final engine = engineOf();
      final phase = engine.uiPhase;
      if (phase == AssistUiPhase.listening && engine.isExploringRange) {
        final hz = engine.currentRangeTargetHz;
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
    voice = FakeTutorVoice();
    speech = FakeTutorSpeechRecognizer();
    saTransport = FakeTutorSaClipTransport();
  });

  test('Hear Sa toggles play/pause and stops for CTA or cancel', () async {
    late final AssistModeController engine;
    engine = buildEngine(wait: (_) async {});
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine, autoContinuePrimaryActions: false);
    addTearDown(tutor.dispose);

    final begin = tutor.begin();
    await waitUntil(() => tutor.primaryAction == TutorPrimaryAction.letsBegin);
    await tutor.continuePrimaryAction();
    await waitUntil(
      () => tutor.primaryAction == TutorPrimaryAction.imReadyToListen,
    );

    expect(tutor.showHearSa, isTrue);
    expect(tutor.showShuffleExample, isFalse);
    expect(tutor.isHearSaPlaying, isFalse);

    await tutor.toggleHearSa();
    expect(tutor.isHearSaPlaying, isTrue);
    expect(saTransport.playCount, 1);
    expect(saTransport.loadedLoop, <bool>[true]);
    expect(saTransport.loadedFiles, isNotEmpty);
    expect(saTransport.loaded, isEmpty);

    await tutor.toggleHearSa();
    expect(tutor.isHearSaPlaying, isFalse);
    expect(saTransport.pauseCount, 1);

    await tutor.toggleHearSa();
    expect(tutor.isHearSaPlaying, isTrue);
    saTransport.finish();
    await Future<void>.delayed(Duration.zero);
    expect(tutor.isHearSaPlaying, isTrue);

    await tutor.toggleHearSa();
    expect(tutor.isHearSaPlaying, isFalse);
    await tutor.toggleHearSa();
    expect(tutor.isHearSaPlaying, isTrue);
    await tutor.continuePrimaryAction();
    expect(tutor.showHearSa, isFalse);
    expect(tutor.isHearSaPlaying, isFalse);
    expect(saTransport.stopCount, greaterThan(0));
    await waitUntil(() => engine.isSessionActive);

    await tutor.stop();
    await begin;
    expect(tutor.isHearSaPlaying, isFalse);
  });

  test(
    'Stage 1 failure offers example controls and shuffle without autoplay',
    () async {
      late final AssistModeController engine;
      engine = buildEngine(
        wait: phasedWait(
          () => engine,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
              detectionService.emit(PitchReading.none);
            }
          },
        ),
      );
      addTearDown(engine.dispose);

      final tutor = buildTutor(engine, autoContinuePrimaryActions: false);
      addTearDown(tutor.dispose);

      final begin = tutor.begin();
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.letsBegin,
      );
      await tutor.continuePrimaryAction();
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.imReadyToListen,
      );
      await tutor.continuePrimaryAction();
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.letsTryAgain,
      );

      expect(voice.spoken, containsAll(TutorScripts.startingNoteGuided));
      expect(voice.playedAssets, containsAll(<String>['S70', 'S61']));
      expect(voice.playedAssets, isNot(contains('S60')));
      expect(voice.playedAssets, isNot(contains('S62')));
      expect(voice.playedAssets, isNot(contains('S71')));
      expect(voice.spoken, isNot(contains("That's okay. Let's try again.")));
      expect(voice.spoken, isNot(contains('Take your time. You can do this.')));
      expect(voice.spoken, isNot(contains(TutorScripts.offerDifferentSound)));
      expect(voice.spoken, isNot(contains('Just listen.')));
      expect(
        voice.spoken,
        isNot(contains("That's alright. I'll let you hear the sound first.")),
      );
      // Spoken order must be exactly S70 → S61, each paired with its clip.
      final guidedStart = voice.spoken.indexOf(
        TutorScripts.startingNoteGuided[0],
      );
      expect(
        voice.spoken.sublist(guidedStart, guidedStart + 2),
        TutorScripts.startingNoteGuided,
      );
      final assetStart = voice.playedAssets.indexOf('S70');
      expect(voice.playedAssets.sublist(assetStart, assetStart + 2), <String>[
        'S70',
        'S61',
      ]);
      // After S61: same text stays, instruction style + example UI. No autoplay.
      expect(tutor.dialogueText, TutorDialogues.s61.text);
      expect(tutor.activeDialogue?.id, 'S61');
      expect(tutor.isDialogueInstruction, isTrue);
      expect(tutor.showHearSa, isTrue);
      expect(tutor.showShuffleExample, isTrue);
      expect(tutor.canShuffleExample, isTrue);
      expect(tutor.exampleControlPhase, TutorExampleControlPhase.idle);
      expect(tutor.isHearSaPlaying, isFalse);
      expect(saTransport.playCount, 0);

      final spokenCountBefore = voice.spoken.length;
      final dialogueBefore = tutor.dialogueText;
      final playCountBeforeShuffle = saTransport.playCount;

      await tutor.shuffleExampleSound();

      expect(tutor.exampleControlPhase, TutorExampleControlPhase.idle);
      expect(tutor.isHearSaPlaying, isFalse);
      expect(saTransport.playCount, playCountBeforeShuffle);
      expect(tutor.dialogueText, dialogueBefore);
      expect(tutor.isDialogueInstruction, isTrue);
      expect(voice.spoken.length, spokenCountBefore);
      expect(
        voice.spoken.where(
          (line) => line == TutorScripts.startingNoteGuided[0],
        ),
        hasLength(1),
        reason: 'shuffle must not re-speak S70–S61',
      );

      await tutor.toggleHearSa();
      expect(tutor.isHearSaPlaying, isTrue);

      // Shuffle while playing stops audio and does not auto-play the new sound.
      await tutor.shuffleExampleSound();
      expect(tutor.isHearSaPlaying, isFalse);
      expect(tutor.dialogueText, TutorDialogues.s61.text);
      expect(tutor.isDialogueInstruction, isTrue);

      await tutor.stop();
      await begin;
    },
  );

  test(
    'entering Stage 1 listening never flashes the previous dialogue',
    () async {
      late final AssistModeController engine;
      final holdListen = Completer<void>();
      engine = buildEngine(wait: (_) => holdListen.future);
      addTearDown(engine.dispose);

      final tutor = buildTutor(engine, autoContinuePrimaryActions: false);
      addTearDown(tutor.dispose);

      final begin = tutor.begin();
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.letsBegin,
      );
      await tutor.continuePrimaryAction();
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.imReadyToListen,
      );
      expect(tutor.dialogueText, TutorScripts.firstStepInstruction);

      final seen = <String?>[];
      void capture() => seen.add(tutor.dialogueText);
      tutor.addListener(capture);

      await tutor.continuePrimaryAction();
      capture();

      expect(
        seen,
        everyElement(anyOf(isNull, equals(TutorScripts.stage1ListenPrompt))),
        reason: 'stale pre-listen dialogue must not appear after CTA',
      );
      expect(tutor.dialogueText, TutorScripts.stage1ListenPrompt);
      expect(tutor.isDialogueInstruction, isTrue);
      expect(seen, isNot(contains(TutorScripts.firstStepInstruction)));

      tutor.removeListener(capture);
      holdListen.complete();
      await tutor.stop();
      await begin;
    },
  );

  test('welcome speaks script then waits for Let\'s begin', () async {
    late final AssistModeController engine;
    engine = buildEngine(wait: (_) async {});
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine, autoContinuePrimaryActions: false);
    addTearDown(tutor.dispose);

    final begin = tutor.begin();
    await waitUntil(() => tutor.primaryAction == TutorPrimaryAction.letsBegin);
    expect(voice.spoken, TutorScripts.welcome);
    expect(engine.isSessionActive, isFalse);
    expect(voice.spoken, isNot(contains(TutorScripts.firstStepListen)));

    await tutor.continuePrimaryAction();
    await waitUntil(
      () => tutor.primaryAction == TutorPrimaryAction.imReadyToListen,
    );
    expect(voice.spoken, contains(TutorScripts.firstStepListen));
    expect(voice.spoken, contains(TutorScripts.firstStepInstruction));
    expect(engine.isSessionActive, isFalse);
    expect(tutor.showListenProgress, isFalse);
    expect(tutor.showCountdown, isFalse);

    await tutor.stop();
    await begin;
    expect(engine.isSessionActive, isFalse);
    expect(tutor.step, TutorStep.stopped);
  });

  test('Stage 1 success shows check moment before Stage 2', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine, autoContinuePrimaryActions: false);
    addTearDown(tutor.dispose);

    void advance() {
      if (tutor.primaryAction == TutorPrimaryAction.letsBegin ||
          tutor.primaryAction == TutorPrimaryAction.imReadyToListen ||
          tutor.primaryAction == TutorPrimaryAction.playTheSound) {
        unawaited(tutor.continuePrimaryAction());
      }
    }

    tutor.addListener(advance);
    addTearDown(() => tutor.removeListener(advance));

    unawaited(tutor.begin());
    await waitUntil(() => voice.spoken.contains(TutorScripts.readyForNextStep));
    await waitUntil(
      () => tutor.primaryAction == TutorPrimaryAction.imReadyForNextStep,
    );
    expect(voice.spoken, contains(TutorScripts.stage1Success));
    expect(tutor.showStage1SuccessMark, isTrue);
    expect(tutor.presenceState, TutorPresenceState.success);
    expect(voice.spoken, isNot(contains(TutorScripts.listenComplete)));

    var exploringWhileOpening = false;
    voice.onSpeak = (text) async {
      if (text == TutorScripts.startingNoteSuccess.first) {
        exploringWhileOpening = engine.isExploringRange;
      }
    };

    await tutor.continuePrimaryAction();
    await waitUntil(() => engine.isExploringRange);
    await waitUntil(() => voice.spoken.contains(TutorScripts.lowerSoundIntro));
    expect(engine.stage1Shruti, Pitch.g);
    expect(engine.isExploringRange, isTrue);
    expect(
      exploringWhileOpening,
      isFalse,
      reason: 'Stage 2 must not start until the opening line finishes',
    );
    expect(
      voice.spoken,
      contains(
        "Now that I understand your voice, let's find your singing range.",
      ),
    );
    expect(voice.spoken, contains(TutorScripts.startingNoteSuccess.first));
    expect(voice.playedAssets, contains('S72'));
    expect(voice.playedAssets, isNot(contains('S11')));
    final openingAt = voice.spoken.indexOf(
      TutorScripts.startingNoteSuccess.first,
    );
    final nextStage2At = voice.spoken.indexWhere(
      (line) =>
          line == TutorScripts.lowerSoundIntro ||
          line == TutorScripts.lowerSoundListenPrompt ||
          line == TutorScripts.listenFirst ||
          line == TutorScripts.countdownFirst.first ||
          line == TutorScripts.countdown.first,
      openingAt + 1,
    );
    expect(openingAt, greaterThanOrEqualTo(0));
    expect(
      nextStage2At,
      greaterThan(openingAt),
      reason: 'Next Stage 2 line must follow the finished opening, not overlap',
    );
    for (final retiredId in <String>['S59', 'S60', 'S61', 'S62', 'S63']) {
      expect(
        voice.playedAssets,
        isNot(contains(retiredId)),
        reason: 'Stage 2 opening must not reuse $retiredId',
      );
    }
    expect(
      voice.spoken,
      isNot(contains("Now let's find a comfortable range for your voice.")),
    );
  });

  test('Stage 1 does not speak a countdown before listening', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      timing: countdownTiming,
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final successAt = voice.spoken.indexOf(TutorScripts.stage1Success);
    expect(successAt, greaterThanOrEqualTo(0));
    expect(
      voice.spoken
          .take(successAt)
          .where((line) => TutorScripts.countdown.contains(line)),
      isEmpty,
      reason: 'Stage 1 no longer uses a spoken countdown',
    );
    expect(voice.spoken, isNot(contains('Get ready.')));
    expect(voice.spoken, isNot(contains('Go')));
    expect(voice.spoken, isNot(contains('Sing along with me.')));
    expect(voice.spoken, isNot(contains('Now sing with me.')));
  });

  test('Stage 1 success speech occurs once before Stage 2', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.a);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();
    await Future<void>.delayed(Duration.zero);

    expect(voice.spoken, contains(TutorScripts.stage1Success));
    expect(voice.spoken, contains(TutorScripts.readyForNextStep));
    expect(voice.spoken, contains(TutorScripts.startingNoteSuccess.first));
    final successAt = voice.spoken.indexOf(TutorScripts.stage1Success);
    final readyAt = voice.spoken.indexOf(TutorScripts.readyForNextStep);
    final rangeAt = voice.spoken.indexOf(
      TutorScripts.startingNoteSuccess.first,
    );
    expect(successAt, lessThan(readyAt));
    expect(readyAt, lessThan(rangeAt));
    expect(
      voice.spoken.where((line) => line == TutorScripts.stage1Success),
      hasLength(1),
    );
    expect(
      voice.spoken.where(
        (line) => line == TutorScripts.startingNoteSuccess.first,
      ),
      hasLength(1),
    );
    expect(voice.playedAssets, contains('S72'));
    expect(
      TutorDialogues.byId('S72')!.text,
      TutorScripts.startingNoteSuccess.first,
    );
  });

  test('failed starting-note capture offers Let\'s try again', () async {
    late final AssistModeController engine;
    var stage1Listens = 0;

    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            stage1Listens += 1;
            if (stage1Listens == 1) {
              detectionService.emit(PitchReading.none);
            } else {
              await emitPitch(detectionService, Pitch.g);
            }
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(stage1Listens, greaterThanOrEqualTo(2));
    expect(voice.spoken, contains(TutorScripts.startingNoteGuided.first));
    expect(voice.spoken, contains(TutorScripts.startingNoteGuided[1]));
    final retryAt = voice.spoken.indexOf(TutorScripts.startingNoteGuided.first);
    expect(
      voice.spoken.take(retryAt).where((l) => l == TutorScripts.stage1Success),
      isEmpty,
      reason: 'silence must not be announced as a successful capture',
    );
    expect(engine.stage1Shruti, Pitch.g);
  });

  test(
    'Stage 1 guided demo reuses Stage 2 Play the sound reference flow',
    () async {
      late final AssistModeController engine;
      late TutorSession tutor;
      var stage1Listens = 0;
      final holdReference = Completer<void>();
      String? dialogueDuringGuidedDemo;
      var resumedStage1Listening = false;

      engine = buildEngine(
        wait: (duration) async {
          final phase = engine.uiPhase;
          if (!engine.isExploringRange &&
              phase == AssistUiPhase.playingReference) {
            dialogueDuringGuidedDemo ??= tutor.dialogueText;
            if (!holdReference.isCompleted) {
              await holdReference.future;
            }
            return;
          }
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            stage1Listens += 1;
            if (stage1Listens <= 2) {
              detectionService.emit(PitchReading.none);
              return;
            }
            resumedStage1Listening = true;
            await emitPitch(detectionService, Pitch.f);
          }
        },
      );
      addTearDown(engine.dispose);

      tutor = buildTutor(engine, autoContinuePrimaryActions: false);
      addTearDown(tutor.dispose);

      unawaited(tutor.begin());
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.letsBegin,
      );
      await tutor.continuePrimaryAction();
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.imReadyToListen,
      );
      await tutor.continuePrimaryAction();

      // Fail Stage 1 twice so the next retry requests a guided demo.
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.letsTryAgain,
      );
      expect(engine.stage1FailureCount, 1);
      expect(engine.stage1GuidedDemoPending, isFalse);
      await tutor.continuePrimaryAction();

      await waitUntil(
        () =>
            tutor.primaryAction == TutorPrimaryAction.letsTryAgain &&
            engine.stage1FailureCount >= 2,
      );
      expect(engine.stage1GuidedDemoPending, isTrue);
      expect(voice.spoken, isNot(contains(TutorScripts.listenFirst)));
      expect(voice.spoken, isNot(contains('Just listen.')));
      expect(voice.playedAssets, isNot(contains('S15')));
      expect(referenceSound.playCount, 0);

      await tutor.continuePrimaryAction();

      // Step 1–2: S74 first, then Play the sound CTA — no auto-play.
      await waitUntil(
        () =>
            voice.spoken.contains(TutorScripts.lowerSoundListenPrompt) &&
            tutor.primaryAction == TutorPrimaryAction.playTheSound,
      );
      expect(tutor.primaryActionLabel, TutorScripts.ctaPlayTheSound);
      expect(tutor.showPrimaryAction, isTrue);
      expect(tutor.dialogueText, TutorScripts.lowerSoundListenPrompt);
      expect(voice.playedAssets, contains('S74'));
      expect(voice.spoken, isNot(contains(TutorScripts.listenFirst)));
      expect(voice.spoken, isNot(contains('Just listen.')));
      expect(voice.playedAssets, isNot(contains('S15')));
      expect(referenceSound.playCount, 0);
      expect(engine.uiPhase, isNot(AssistUiPhase.playingReference));
      expect(tutor.dialogueText, isNot(TutorScripts.referenceListenPrompt));

      // Step 3: CTA starts dedicated listen screen + reference sound.
      await tutor.continuePrimaryAction();
      expect(tutor.showPrimaryAction, isFalse);
      expect(tutor.dialogueText, TutorScripts.referenceListenPrompt);
      expect(tutor.dialogueText, isNot(TutorScripts.lowerSoundListenPrompt));

      await waitUntil(() => engine.uiPhase == AssistUiPhase.playingReference);
      expect(referenceSound.playCount, greaterThan(0));
      expect(dialogueDuringGuidedDemo, TutorScripts.referenceListenPrompt);
      expect(tutor.dialogueText, TutorScripts.referenceListenPrompt);
      expect(engine.isExploringRange, isFalse);

      holdReference.complete();

      // Step 4: after reference, existing Stage 1 singing/input resumes.
      await waitUntil(() => resumedStage1Listening);
      expect(resumedStage1Listening, isTrue);
      expect(engine.isExploringRange, isFalse);
      expect(stage1Listens, greaterThanOrEqualTo(3));
    },
  );

  test(
    'Stage 2 waits for Play the sound CTA before reference playback',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      final holdReference = Completer<void>();
      String? dialogueDuringReference;

      engine = buildEngine(
        wait: (duration) async {
          if (engine.uiPhase == AssistUiPhase.listening &&
              !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
            return;
          }
          if (engine.uiPhase == AssistUiPhase.playingReference &&
              engine.isExploringRange) {
            dialogueDuringReference ??= tutor.dialogueText;
            if (!holdReference.isCompleted) {
              await holdReference.future;
            }
            return;
          }
          if (engine.uiPhase == AssistUiPhase.listening &&
              engine.isExploringRange) {
            final hz = engine.currentRangeTargetHz;
            if (hz != null) {
              await emitHz(detectionService, hz);
            }
          }
        },
      );
      addTearDown(engine.dispose);

      tutor = buildTutor(engine, autoContinuePrimaryActions: false);
      addTearDown(tutor.dispose);

      unawaited(engine.startSession());
      await waitUntil(
        () => tutor.primaryAction == TutorPrimaryAction.imReadyForNextStep,
      );
      await tutor.continuePrimaryAction();

      await waitUntil(
        () =>
            voice.spoken.contains(TutorScripts.lowerSoundListenPrompt) &&
            tutor.primaryAction == TutorPrimaryAction.playTheSound,
      );

      expect(tutor.primaryActionLabel, TutorScripts.ctaPlayTheSound);
      expect(tutor.showPrimaryAction, isTrue);
      expect(tutor.dialogueText, TutorScripts.lowerSoundListenPrompt);
      expect(referenceSound.playCount, 0);
      expect(engine.uiPhase, isNot(AssistUiPhase.playingReference));
      expect(tutor.dialogueText, isNot(TutorScripts.referenceListenPrompt));

      await tutor.continuePrimaryAction();

      expect(tutor.showPrimaryAction, isFalse);
      expect(tutor.dialogueText, TutorScripts.referenceListenPrompt);
      expect(tutor.dialogueText, isNot(TutorScripts.lowerSoundListenPrompt));

      await waitUntil(() => engine.uiPhase == AssistUiPhase.playingReference);

      expect(referenceSound.playCount, greaterThan(0));
      expect(dialogueDuringReference, TutorScripts.referenceListenPrompt);
      expect(tutor.dialogueText, TutorScripts.referenceListenPrompt);
      expect(tutor.dialogueText, isNot(TutorScripts.lowerSoundListenPrompt));

      holdReference.complete();
    },
  );

  test('beforeReference speech precedes reference playback', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    String? dialogueDuringReference;
    String? dialogueDuringSettle;
    var spokenCountAtReference = -1;

    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.listening &&
            !engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.d);
        }
        if (engine.uiPhase == AssistUiPhase.playingReference &&
            engine.isExploringRange &&
            dialogueDuringReference == null) {
          dialogueDuringReference = tutor.dialogueText;
          spokenCountAtReference = voice.spoken.length;
        }
        if (engine.uiPhase == AssistUiPhase.preparingToListen &&
            engine.isExploringRange &&
            dialogueDuringSettle == null) {
          dialogueDuringSettle = tutor.dialogueText;
        }
        if (engine.uiPhase == AssistUiPhase.listening &&
            engine.isExploringRange) {
          final hz = engine.currentRangeTargetHz;
          if (hz != null) {
            await emitHz(detectionService, hz);
          }
        }
      },
    );
    addTearDown(engine.dispose);

    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await Future<void>.delayed(Duration.zero);

    expect(voice.spoken, contains(TutorScripts.lowerSoundIntro));
    expect(voice.spoken, contains(TutorScripts.lowerSoundListenPrompt));
    expect(voice.spoken, isNot(contains(TutorScripts.listenFirst)));
    expect(voice.spoken, isNot(contains(TutorScripts.referenceListenPrompt)));
    expect(voice.playedAssets, contains('S74'));
    expect(voice.playedAssets, isNot(contains('S15')));
    expect(
      voice.spoken.indexOf(TutorScripts.lowerSoundIntro),
      lessThan(voice.spoken.indexOf(TutorScripts.lowerSoundListenPrompt)),
    );
    // After the reference, Stage 2 goes to countdown / singing directly.
    expect(voice.spoken, isNot(contains('Now try that sound.')));
    expect(referenceSound.playCount, greaterThan(0));
    expect(dialogueDuringReference, TutorScripts.referenceListenPrompt);
    expect(dialogueDuringSettle, TutorScripts.referenceListenPrompt);
    expect(
      dialogueDuringSettle,
      isNot(TutorScripts.lowerSoundListenPrompt),
      reason: 'stale S74 must not flash after the reference ends',
    );
    expect(spokenCountAtReference, greaterThan(0));
    expect(
      voice.spoken[spokenCountAtReference - 1],
      TutorScripts.lowerSoundListenPrompt,
    );
  });

  test(
    'Stage 2 settle and pre-speech countdown never flash the S74 transcript',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      final settleDialogues = <String?>[];
      final countdownDialoguesBeforeSpeech = <String?>[];
      final preFirstCountdownDialogues = <String?>[];
      var sawFirstCountdownLine = false;

      engine = buildEngine(
        timing: countdownTiming,
        wait: (duration) async {
          if (engine.uiPhase == AssistUiPhase.listening &&
              !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
          }
          if (engine.uiPhase == AssistUiPhase.preparingToListen &&
              engine.isExploringRange) {
            settleDialogues.add(tutor.dialogueText);
            if (!sawFirstCountdownLine) {
              preFirstCountdownDialogues.add(tutor.dialogueText);
            }
          }
          if (engine.uiPhase == AssistUiPhase.countdown &&
              engine.isExploringRange &&
              !tutor.isSpeaking) {
            countdownDialoguesBeforeSpeech.add(tutor.dialogueText);
            if (!sawFirstCountdownLine) {
              preFirstCountdownDialogues.add(tutor.dialogueText);
            }
          }
          if (engine.uiPhase == AssistUiPhase.listening &&
              engine.isExploringRange) {
            final hz = engine.currentRangeTargetHz;
            if (hz != null) {
              await emitHz(detectionService, hz);
            }
          }
        },
      );
      addTearDown(engine.dispose);
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      void recordDialogue() {
        final text = tutor.dialogueText;
        if (text == TutorScripts.countdownFirst.first) {
          sawFirstCountdownLine = true;
        }
        if (!sawFirstCountdownLine &&
            engine.isExploringRange &&
            (engine.uiPhase == AssistUiPhase.preparingToListen ||
                engine.uiPhase == AssistUiPhase.countdown ||
                engine.uiPhase == AssistUiPhase.playingReference)) {
          preFirstCountdownDialogues.add(text);
        }
      }

      tutor.addListener(recordDialogue);
      addTearDown(() => tutor.removeListener(recordDialogue));

      await engine.startSession();
      await Future<void>.delayed(Duration.zero);

      expect(settleDialogues, isNotEmpty);
      expect(settleDialogues, everyElement(TutorScripts.referenceListenPrompt));
      expect(
        settleDialogues,
        isNot(contains(TutorScripts.lowerSoundListenPrompt)),
      );
      expect(
        countdownDialoguesBeforeSpeech,
        everyElement(TutorScripts.referenceListenPrompt),
        reason: 'Listen prompt stays until countdown speech binds',
      );
      expect(
        countdownDialoguesBeforeSpeech,
        isNot(contains(TutorScripts.lowerSoundListenPrompt)),
      );
      expect(sawFirstCountdownLine, isTrue);
      expect(
        preFirstCountdownDialogues,
        everyElement(
          anyOf(
            TutorScripts.referenceListenPrompt,
            TutorScripts.lowerSoundListenPrompt,
            isNull,
          ),
        ),
      );
      expect(
        preFirstCountdownDialogues,
        isNot(contains('1...')),
        reason: 'standalone 1... must never paint before countdown starts',
      );
      expect(preFirstCountdownDialogues, isNot(contains('2...')));
      expect(voice.spoken, contains(TutorScripts.countdownFirst.first));
      expect(voice.spoken, isNot(contains(TutorScripts.countdown.first)));
      expect(
        voice.spoken.indexOf(TutorScripts.lowerSoundListenPrompt),
        lessThan(voice.spoken.indexOf(TutorScripts.countdownFirst.first)),
      );
      expect(
        voice.spoken.where(
          (line) => line == TutorScripts.lowerSoundListenPrompt,
        ),
        hasLength(1),
        reason: 'S74 must not be re-spoken after the reference',
      );
    },
  );

  test(
    'Stage 2 retry never flashes prior countdown 1... after reference',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      final retryTransitionDialogues = <String?>[];
      var soloListens = 0;
      var collectingRetryTransition = false;
      var sawRetryCountdown = false;

      engine = buildEngine(
        timing: countdownTiming,
        wait: (duration) async {
          if (engine.uiPhase == AssistUiPhase.listening &&
              !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
            return;
          }
          if (engine.uiPhase == AssistUiPhase.listening &&
              engine.isExploringRange) {
            soloListens += 1;
            if (soloListens == 1) {
              // Miss once so a retry reference + countdown runs.
              detectionService.emit(PitchReading.none);
              return;
            }
            final hz = engine.currentRangeTargetHz;
            if (hz != null) {
              await emitHz(detectionService, hz);
            }
          }
        },
      );
      addTearDown(engine.dispose);
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      void recordRetryTransition() {
        // Only the retry reference → countdown window (after the first miss).
        if (engine.rangePointFailureCount >= 1 &&
            !sawRetryCountdown &&
            (engine.uiPhase == AssistUiPhase.playingReference ||
                engine.uiPhase == AssistUiPhase.preparingToListen ||
                engine.uiPhase == AssistUiPhase.countdown)) {
          collectingRetryTransition = true;
        }
        if (tutor.dialogueText == TutorScripts.countdown.first) {
          sawRetryCountdown = true;
        }
        if (collectingRetryTransition && !sawRetryCountdown) {
          retryTransitionDialogues.add(tutor.dialogueText);
        }
      }

      tutor.addListener(recordRetryTransition);
      addTearDown(() => tutor.removeListener(recordRetryTransition));

      await engine.startSession();
      await Future<void>.delayed(Duration.zero);

      expect(collectingRetryTransition, isTrue);
      expect(sawRetryCountdown, isTrue);
      expect(voice.spoken, contains(TutorScripts.countdown.first));
      expect(
        retryTransitionDialogues,
        isNotEmpty,
        reason: 'must observe the retry listen→countdown window',
      );
      expect(
        retryTransitionDialogues,
        isNot(contains('1...')),
        reason: 'prior countdown 1... must not leak after the next reference',
      );
      expect(
        retryTransitionDialogues,
        everyElement(
          anyOf(
            TutorScripts.referenceListenPrompt,
            TutorScripts.rangeRetryOnce,
            TutorScripts.listenFirst,
            isNull,
          ),
        ),
      );
    },
  );

  test(
    'Stage 2 uses first-attempt countdown then again wording on retry',
    () async {
      late final AssistModeController engine;
      var lowerSaListens = 0;

      engine = buildEngine(
        timing: countdownTiming,
        wait: (duration) async {
          if (engine.uiPhase == AssistUiPhase.listening &&
              !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
            return;
          }
          if (engine.uiPhase == AssistUiPhase.listening &&
              engine.isExploringRange &&
              engine.currentRangePoint == AssistRangePoint.lowerSa) {
            lowerSaListens += 1;
            if (lowerSaListens == 1) {
              // Miss the first solo attempt so a retry countdown runs.
              await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
              return;
            }
            final hz = engine.currentRangeTargetHz;
            if (hz != null) {
              await emitHz(detectionService, hz);
            }
          }
        },
      );
      addTearDown(engine.dispose);
      final tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await engine.startSession();
      await waitUntil(
        () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
      );

      expect(voice.spoken, contains(TutorScripts.countdownFirst.first));
      expect(voice.spoken, contains(TutorScripts.countdown.first));
      expect(voice.playedAssets, contains('S75'));
      expect(voice.playedAssets, contains('S07'));
      expect(
        voice.spoken.indexOf(TutorScripts.countdownFirst.first),
        lessThan(voice.spoken.indexOf(TutorScripts.countdown.first)),
      );
      expect(
        voice.spoken.where((line) => line == TutorScripts.countdownFirst.first),
        hasLength(1),
      );
      expect(
        voice.spoken.where((line) => line == TutorScripts.countdown.first),
        hasLength(1),
      );
      expect(engine.rangePointFailureCount, 0);
    },
  );

  test('spoken Yes advances lower audibility via STT', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    speech.enqueue('yes');
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);

    // Drive classification directly if async STT has not yet settled.
    for (var i = 0; i < 30; i++) {
      if (engine.activeCandidateResult?.lowerSaAudible == true) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (engine.activeCandidateResult?.lowerSaAudible != true) {
      await tutor.submitSpokenAnswer('yes');
    }

    expect(engine.activeCandidateResult?.lowerSaAudible, isTrue);
  });

  test('unclear spoken answer asks again', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);

    await tutor.submitSpokenAnswer('maybe later');
    expect(voice.spoken, contains(TutorScripts.unclearYesNo.first));

    await tutor.submitSpokenAnswer('yes');
    expect(engine.activeCandidateResult?.lowerSaAudible, isTrue);
  });

  test('Pa comfort question pauses after pitch match', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    await tutor.answerLowerAudibility(true);

    expect(engine.uiPhase, AssistUiPhase.awaitingPaComfort);
    expect(tutor.step, TutorStep.askMiddleComfort);
    expect(tutor.showComfortFallback, isTrue);
    expect(tutor.dialogueText, TutorScripts.upperComfortQuestion);
    expect(voice.spoken, contains(TutorScripts.upperComfortQuestion));

    await tutor.answerUpperComfort(true);
    expect(engine.activeCandidateResult?.paComfortable, isTrue);
    expect(engine.uiPhase, AssistUiPhase.awaitingUpperComfort);
    expect(tutor.step, TutorStep.askUpperComfort);
  });

  Future<void> expectNoCtaFlashDuringAck({
    required TutorSession tutor,
    required Future<void> Function() answer,
    required String acknowledgement,
    required bool Function() showPriorCtas,
    required TutorStep expectedStepDuringAck,
  }) async {
    var ctaVisibleWithAck = false;
    void watch() {
      if (tutor.dialogueText == acknowledgement && showPriorCtas()) {
        ctaVisibleWithAck = true;
      }
    }

    tutor.addListener(watch);
    final holdAck = Completer<void>();
    final ackStarted = Completer<void>();
    voice.onSpeak = (text) async {
      if (text == acknowledgement) {
        if (!ackStarted.isCompleted) {
          ackStarted.complete();
        }
        await holdAck.future;
      }
    };

    final answering = answer();
    await ackStarted.future;
    expect(tutor.dialogueText, acknowledgement);
    expect(showPriorCtas(), isFalse);
    expect(tutor.step, expectedStepDuringAck);

    // Also cover the post-speech pause window: release audio while a
    // non-zero sentence pause keeps the engine on the question step.
    holdAck.complete();
    await answering;
    tutor.removeListener(watch);
    expect(ctaVisibleWithAck, isFalse);
  }

  test('audibility Yes CTAs clear before soft affirmation', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    expect(tutor.showYesNoFallback, isTrue);

    await expectNoCtaFlashDuringAck(
      tutor: tutor,
      answer: () => tutor.answerLowerAudibility(true),
      acknowledgement: TutorScripts.softAffirmation,
      showPriorCtas: () => tutor.showYesNoFallback,
      expectedStepDuringAck: TutorStep.askLowerAudibility,
    );
  });

  test('comfort No CTAs clear before keep-comfortable line', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await tutor.answerLowerAudibility(true);
    expect(engine.uiPhase, AssistUiPhase.awaitingPaComfort);
    expect(tutor.showComfortFallback, isTrue);

    await expectNoCtaFlashDuringAck(
      tutor: tutor,
      answer: () => tutor.answerUpperComfort(false),
      acknowledgement: TutorScripts.upperNotComfortable,
      showPriorCtas: () => tutor.showComfortFallback,
      expectedStepDuringAck: TutorStep.askMiddleComfort,
    );
  });

  test('comfort Yes CTAs clear before soft affirmation', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await tutor.answerLowerAudibility(true);
    expect(engine.uiPhase, AssistUiPhase.awaitingPaComfort);
    expect(tutor.showComfortFallback, isTrue);

    await expectNoCtaFlashDuringAck(
      tutor: tutor,
      answer: () => tutor.answerUpperComfort(true),
      acknowledgement: TutorScripts.softAffirmation,
      showPriorCtas: () => tutor.showComfortFallback,
      expectedStepDuringAck: TutorStep.askMiddleComfort,
    );
  });

  test('Pa not comfortable uses the existing strain adjustment path', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await tutor.answerLowerAudibility(true);
    expect(engine.uiPhase, AssistUiPhase.awaitingPaComfort);

    await tutor.answerUpperComfort(false);

    expect(engine.testedCandidates.first.paComfortable, isFalse);
    expect(engine.searchMode, AssistShrutiSearchMode.seekingLower);
    expect(voice.spoken, contains(TutorScripts.upperNotComfortable));
  });

  test('answerLowerAudibility NO seeks higher', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);

    await tutor.answerLowerAudibility(false);
    expect(engine.searchMode, AssistShrutiSearchMode.seekingHigher);
  });

  test('tryAgain resets and restarts tutor search', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();

    var markedFirstComfortable = false;
    for (var i = 0; i < 64; i++) {
      if (engine.uiPhase == AssistUiPhase.awaitingLowerAudibility) {
        await tutor.answerLowerAudibility(true);
      } else if (engine.uiPhase == AssistUiPhase.awaitingPaComfort) {
        await tutor.answerUpperComfort(true);
      } else if (engine.uiPhase == AssistUiPhase.awaitingUpperComfort) {
        if (!markedFirstComfortable) {
          markedFirstComfortable = true;
          await tutor.answerUpperComfort(true);
        } else {
          await tutor.answerUpperComfort(false);
        }
      } else if (engine.uiPhase == AssistUiPhase.completed) {
        break;
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }

    for (var i = 0; i < 50; i++) {
      if (engine.uiPhase == AssistUiPhase.completed && !engine.isBusy) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(engine.uiPhase, AssistUiPhase.completed);

    await tutor.tryAgain();
    expect(engine.isSessionActive, isTrue);
    expect(engine.uiPhase, isNot(AssistUiPhase.completed));
    expect(engine.lastComfortableShruti, isNull);
  });

  test('stop during speech does not start or continue the session', () async {
    late final AssistModeController engine;
    engine = buildEngine(wait: (_) async {});
    addTearDown(engine.dispose);

    late final TutorSession tutor;
    voice.onSpeak = (text) async {
      if (text == TutorScripts.welcome.first) {
        await tutor.stop();
      }
    };
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();

    expect(engine.isSessionActive, isFalse);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(tutor.step, TutorStep.stopped);
    expect(tutor.headline, TutorScripts.sessionStopped);
    expect(tutor.supportText, TutorScripts.sessionStoppedSupport);
    expect(tutor.showSessionStopped, isTrue);
    expect(tutor.showStop, isFalse);
    expect(voice.spoken, contains(TutorScripts.welcome.first));
    expect(voice.spoken, isNot(contains(TutorScripts.discoverIntro.first)));
    expect(voice.stopCount, greaterThan(0));
    final spoken = voice.spoken.length;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(voice.spoken.length, spoken);
    expect(engine.uiPhase, AssistUiPhase.intro);
  });

  test('Pa assisted speech is used only for sing-along help', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    var paSolos = 0;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          expect(referenceSound.isPlaying, isTrue);
          expect(engine.isPitchAnalysisEnabled, isFalse);
          expect(tutor.dialogueText, TutorScripts.assistedSingAlongPrompt);
          expect(tutor.dialogueText, isNot(TutorDialogues.s09.text));
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.d);
          return;
        }
        if (engine.currentRangePoint != AssistRangePoint.pa) {
          final hz = engine.currentRangeTargetHz;
          if (hz != null) {
            await emitHz(detectionService, hz);
          }
          return;
        }
        paSolos += 1;
        if (paSolos <= 2) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.c));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await engine.reportLowerSaAudible();

    expect(voice.spoken, contains(TutorScripts.rangeRetryOnce));
    expect(voice.spoken, contains(TutorScripts.practiceTogether));
    expect(voice.spoken, contains(TutorScripts.singAlongWithMe));
    expect(voice.spoken, contains(TutorScripts.assistedSingAlongPrompt));
    expect(voice.spoken, contains(TutorScripts.tryOnYourOwn));
    expect(voice.spoken, isNot(contains(TutorScripts.practiceOnceMore)));
    expect(voice.spoken, isNot(contains(TutorScripts.assistedReady)));
    final practice = voice.spoken.indexOf(TutorScripts.practiceTogether);
    final along = voice.spoken.indexOf(TutorScripts.singAlongWithMe);
    final assistPrompt = voice.spoken.indexOf(
      TutorScripts.assistedSingAlongPrompt,
    );
    final onYourOwn = voice.spoken.indexOf(TutorScripts.tryOnYourOwn);
    expect(practice, greaterThanOrEqualTo(0));
    expect(along, greaterThan(practice));
    expect(assistPrompt, greaterThan(along));
    expect(onYourOwn, greaterThan(assistPrompt));
    expect(engine.canIsolateUserFromReference, isFalse);
    expect(engine.uiPhase, AssistUiPhase.awaitingPaComfort);
  });

  test('stop during countdown does not start listening', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    engine = buildEngine(
      timing: countdownTiming,
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    voice.onSpeak = (text) async {
      if (text == TutorScripts.countdownFirst.first) {
        await tutor.stop();
      }
    };
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();

    expect(tutor.step, TutorStep.stopped);
    expect(tutor.headline, TutorScripts.sessionStopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(detectionService.isListening, isFalse);
    expect(voice.spoken, isNot(contains('2...')));
    expect(voice.spoken, isNot(contains('1...')));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(voice.spoken.where((line) => line == '2...'), isEmpty);
  });

  test('stop during reference playback does not continue', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    var stopped = false;
    var playsAtStop = 0;
    engine = buildEngine(
      wait: (duration) async {
        if (!stopped && engine.uiPhase == AssistUiPhase.playingReference) {
          stopped = true;
          playsAtStop = referenceSound.playCount;
          await tutor.stop();
          return;
        }
        if (engine.uiPhase == AssistUiPhase.listening &&
            !engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.d);
        }
      },
    );
    addTearDown(engine.dispose);
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();

    expect(stopped, isTrue);
    expect(tutor.step, TutorStep.stopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(referenceSound.isPlaying, isFalse);
    expect(detectionService.isListening, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(referenceSound.playCount, playsAtStop);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(tutor.step, TutorStep.stopped);
  });

  test('stop during assisted singing does not verify afterwards', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    var paSolos = 0;
    var stopped = false;
    engine = buildEngine(
      wait: (duration) async {
        if (!stopped && engine.uiPhase == AssistUiPhase.assistedSinging) {
          stopped = true;
          await tutor.stop();
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.d);
          return;
        }
        if (engine.currentRangePoint == AssistRangePoint.pa) {
          paSolos += 1;
          await emitHz(detectionService, frequencyHzForPitch(Pitch.c));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();
    if (engine.uiPhase == AssistUiPhase.awaitingLowerAudibility) {
      await tutor.answerLowerAudibility(true);
    }

    expect(stopped, isTrue);
    expect(paSolos, 2);
    expect(tutor.step, TutorStep.stopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(referenceSound.isPlaying, isFalse);
    expect(detectionService.isListening, isFalse);
    expect(engine.isPitchAnalysisEnabled, isFalse);
    expect(voice.spoken, contains(TutorScripts.practiceTogether));
    expect(voice.spoken, isNot(contains(TutorScripts.tryOnYourOwn)));
    final plays = referenceSound.playCount;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(referenceSound.playCount, plays);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(tutor.step, TutorStep.stopped);
  });

  test('stop during processing does not advance the session', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    var stopped = false;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (!stopped &&
              phase == AssistUiPhase.processing &&
              !engine.isExploringRange) {
            stopped = true;
            await tutor.stop();
          }
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.e);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();

    expect(stopped, isTrue);
    expect(tutor.step, TutorStep.stopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(engine.isExploringRange, isFalse);
    expect(detectionService.isListening, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(voice.spoken, isNot(contains(TutorScripts.lowerSoundIntro)));
  });

  test('try again after stop starts a fresh welcome', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    final oldWindow = Completer<void>();
    var holdingOldSession = false;
    engine = buildEngine(
      wait: (duration) async {
        if (!holdingOldSession &&
            engine.uiPhase == AssistUiPhase.listening &&
            !engine.isExploringRange) {
          holdingOldSession = true;
          await tutor.stop();
          await oldWindow.future;
          return;
        }
        if (engine.uiPhase == AssistUiPhase.listening &&
            !engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.e);
        }
      },
    );
    addTearDown(engine.dispose);
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();
    expect(tutor.step, TutorStep.stopped);
    expect(engine.isSessionActive, isFalse);

    final spokenBeforeRestart = voice.spoken.length;
    final restart = tutor.tryAgain();
    for (var i = 0; i < 30; i++) {
      if (voice.spoken.length >=
          spokenBeforeRestart + TutorScripts.welcome.length) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      voice.spoken.skip(spokenBeforeRestart).take(TutorScripts.welcome.length),
      TutorScripts.welcome,
    );
    expect(
      voice.spoken
          .skip(spokenBeforeRestart)
          .where((line) => line == TutorScripts.welcome.first)
          .length,
      1,
    );

    oldWindow.complete();
    await restart;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(tutor.step, isNot(TutorStep.stopped));
    expect(tutor.headline, isNot(TutorScripts.sessionStopped));
    expect(engine.isSessionActive, isTrue);
    expect(engine.uiPhase, isNot(AssistUiPhase.intro));
    expect(
      voice.spoken.where((line) => line == TutorScripts.welcome.first).length,
      2,
    );
  });

  test('spoken yes resolves the question once and stops recognition', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    speech.enqueue('yes');
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    for (var i = 0; i < 40; i++) {
      if (engine.activeCandidateResult?.lowerSaAudible == true) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    expect(engine.activeCandidateResult?.lowerSaAudible, isTrue);
    expect(speech.listenCount, greaterThan(0));
    expect(speech.stopCount, greaterThan(0));
    expect(engine.uiPhase, isNot(AssistUiPhase.awaitingLowerAudibility));
  });

  test('spoken no resolves as not heard', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    speech.enqueue('no');
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    for (var i = 0; i < 40; i++) {
      if (engine.searchMode == AssistShrutiSearchMode.seekingHigher) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    expect(engine.searchMode, AssistShrutiSearchMode.seekingHigher);
    expect(speech.stopCount, greaterThan(0));
  });

  test('ambiguous speech does not resolve the question', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    speech.enqueue('maybe later');
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    for (var i = 0; i < 40; i++) {
      if (voice.spoken.contains(TutorScripts.unclearYesNo.first)) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(engine.activeCandidateResult?.lowerSaAudible, isNot(true));
    expect(voice.spoken, contains(TutorScripts.unclearYesNo.first));
  });

  test('button and speech cannot resolve the same question twice', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);

    final fromButton = tutor.answerLowerAudibility(true);
    final fromSpeech = tutor.submitSpokenAnswer('no');
    await Future.wait<void>([fromButton, fromSpeech]);

    expect(engine.activeCandidateResult?.lowerSaAudible, isTrue);
    expect(engine.searchMode, isNot(AssistShrutiSearchMode.seekingHigher));
  });

  test('spoken comfort answers and the button fallback', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    speech.enqueue('yes');
    speech.enqueue('not comfortable');
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    for (var i = 0; i < 50; i++) {
      if (engine.uiPhase == AssistUiPhase.awaitingPaComfort ||
          engine.uiPhase == AssistUiPhase.awaitingUpperComfort ||
          engine.uiPhase == AssistUiPhase.exploringNextShruti ||
          engine.searchMode == AssistShrutiSearchMode.seekingLower ||
          engine.searchMode == AssistShrutiSearchMode.seekingHigher) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    // "not comfortable" may already have answered Pa via speech; otherwise tap.
    if (engine.uiPhase == AssistUiPhase.awaitingPaComfort ||
        engine.uiPhase == AssistUiPhase.awaitingUpperComfort) {
      await tutor.answerUpperComfort(false);
    }

    expect(engine.lastComfortableShruti, isNull);
    expect(engine.uiPhase == AssistUiPhase.awaitingPaComfort, isFalse);
    expect(engine.uiPhase == AssistUiPhase.awaitingUpperComfort, isFalse);
  });

  test('stop during yes/no recognition does not apply the answer', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    final hold = Completer<void>();
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    speech.listenHold = hold.future;
    speech.enqueue('yes');
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    for (var i = 0; i < 40; i++) {
      if (speech.listenCount > 0) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(speech.listenCount, greaterThan(0));

    await tutor.stop();
    hold.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(tutor.step, TutorStep.stopped);
    expect(tutor.headline, TutorScripts.sessionStopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(engine.activeCandidateResult?.lowerSaAudible, isNot(true));
  });

  test('assisted countdown uses the sing-together lead-in', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    var paSolos = 0;
    var sawTogetherCountdown = false;
    var sawSoloCountdownAfterHandoff = false;
    var analysisDuringAssist = true;
    var analysisDuringSoloCountdown = true;
    var analysisDuringSoloListen = false;
    var handoffSpoken = false;
    engine = buildEngine(
      timing: countdownTiming,
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.countdown &&
            engine.countdownKind == AssistCountdownKind.singTogether) {
          sawTogetherCountdown = true;
          expect(engine.countdownValue, isNot(0));
          expect(engine.isPitchAnalysisEnabled, isFalse);
          return;
        }
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          analysisDuringAssist = engine.isPitchAnalysisEnabled;
          expect(referenceSound.isPlaying, isTrue);
          expect(engine.recoveryMode, AssistRecoveryMode.assistedSinging);
          expect(tutor.dialogueText, TutorScripts.assistedSingAlongPrompt);
          expect(
            tutor.dialogueText,
            isNot(contains('1...')),
          );
          return;
        }
        if (engine.uiPhase == AssistUiPhase.countdown &&
            engine.countdownKind == AssistCountdownKind.soloRetry &&
            voice.spoken.contains(TutorScripts.tryOnYourOwn)) {
          sawSoloCountdownAfterHandoff = true;
          analysisDuringSoloCountdown = engine.isPitchAnalysisEnabled;
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.d);
          return;
        }
        if (engine.currentRangePoint != AssistRangePoint.pa) {
          final hz = engine.currentRangeTargetHz;
          if (hz != null) {
            await emitHz(detectionService, hz);
          }
          return;
        }
        paSolos += 1;
        if (paSolos <= 2) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.c));
          return;
        }
        analysisDuringSoloListen = engine.isPitchAnalysisEnabled;
        handoffSpoken = voice.spoken.contains(TutorScripts.tryOnYourOwn);
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await engine.reportLowerSaAudible();

    expect(sawTogetherCountdown, isTrue);
    expect(sawSoloCountdownAfterHandoff, isTrue);
    expect(analysisDuringAssist, isFalse);
    expect(analysisDuringSoloCountdown, isFalse);
    expect(analysisDuringSoloListen, isTrue);
    expect(handoffSpoken, isTrue);
    expect(paSolos, greaterThan(2));
    expect(voice.spoken, contains(TutorScripts.assistedCountdown.first));
    expect(voice.spoken, contains(TutorScripts.assistedSingAlongPrompt));
    expect(voice.spoken, contains(TutorScripts.tryOnYourOwn));
    expect(voice.spoken, contains(TutorScripts.countdown.first));
    final onYourOwn = voice.spoken.indexOf(TutorScripts.tryOnYourOwn);
    final soloCountdown = voice.spoken.indexOf(
      TutorScripts.countdown.first,
      onYourOwn,
    );
    expect(onYourOwn, greaterThan(0));
    expect(
      soloCountdown,
      greaterThan(onYourOwn),
      reason: 'solo countdown follows the handoff',
    );
    expect(voice.spoken, isNot(contains('Get ready.')));
    expect(voice.spoken, isNot(contains('Go')));
    expect(voice.spoken, isNot(contains(TutorScripts.assistedReady)));
    expect(voice.spoken, isNot(contains(TutorScripts.practiceOnceMore)));
    expect(engine.canIsolateUserFromReference, isFalse);
    expect(engine.uiPhase, AssistUiPhase.awaitingPaComfort);
    expect(referenceSound.isPlaying, isFalse);
  });

  test(
    'stop during assisted countdown does not start sing-along audio',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      var paSolos = 0;
      engine = buildEngine(
        timing: countdownTiming,
        wait: (duration) async {
          if (engine.uiPhase != AssistUiPhase.listening) {
            return;
          }
          if (!engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.d);
            return;
          }
          if (engine.currentRangePoint != AssistRangePoint.pa) {
            final hz = engine.currentRangeTargetHz;
            if (hz != null) {
              await emitHz(detectionService, hz);
            }
            return;
          }
          paSolos += 1;
          await emitHz(detectionService, frequencyHzForPitch(Pitch.c));
        },
      );
      addTearDown(engine.dispose);
      voice.onSpeak = (text) async {
        if (text == TutorScripts.assistedCountdown.first) {
          await tutor.stop();
        }
      };
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await engine.startSession();
      await engine.reportLowerSaAudible();

      expect(tutor.step, TutorStep.stopped);
      expect(engine.uiPhase, AssistUiPhase.intro);
      expect(engine.isSessionActive, isFalse);
      expect(referenceSound.isPlaying, isFalse);
      expect(detectionService.isListening, isFalse);
      expect(voice.spoken, contains(TutorScripts.assistedCountdown.first));
      expect(voice.spoken, isNot(contains(TutorScripts.assistedReady)));
      final plays = referenceSound.playCount;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(referenceSound.playCount, plays);
      expect(engine.uiPhase, AssistUiPhase.intro);
      expect(paSolos, 2);
    },
  );

  test(
    'first-step instructions do not start pitch detection or reference audio',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      var checkedDuringInstruction = false;
      engine = buildEngine(
        wait: phasedWait(
          () => engine,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
              await emitPitch(detectionService, Pitch.g);
            }
          },
        ),
      );
      addTearDown(engine.dispose);

      voice.onSpeak = (text) async {
        if (text != TutorScripts.firstStepInstruction) {
          return;
        }
        checkedDuringInstruction = true;
        expect(tutor.step, TutorStep.discoverStartingNote);
        expect(tutor.journeyStage, isNull);
        expect(engine.isSessionActive, isFalse);
        expect(engine.uiPhase, AssistUiPhase.intro);
        expect(engine.isPitchAnalysisEnabled, isFalse);
        expect(detectionService.isListening, isFalse);
        expect(referenceSound.playCount, 0);
        expect(referenceSound.isPlaying, isFalse);
        expect(audioService.playCount, 0);
        expect(voice.spoken, isNot(contains(TutorScripts.countdown.first)));
        expect(voice.spoken, isNot(contains(TutorScripts.listenFirst)));
        expect(voice.spoken, isNot(contains(TutorScripts.singAlongWithMe)));
      };
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await tutor.begin();

      expect(checkedDuringInstruction, isTrue);
      expect(
        voice.spoken.where((line) => line == TutorScripts.firstStepListen),
        hasLength(1),
      );
      expect(engine.stage1Shruti, Pitch.g);
      expect(engine.isSessionActive, isTrue);
    },
  );

  test(
    'stop during first-step instructions does not start the session',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      engine = buildEngine(wait: (_) async {});
      addTearDown(engine.dispose);

      voice.onSpeak = (text) async {
        if (text == TutorScripts.firstStepListen) {
          await tutor.stop();
        }
      };
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await tutor.begin();

      expect(tutor.step, TutorStep.stopped);
      expect(tutor.showJourneyProgress, isFalse);
      expect(tutor.journeyStage, isNull);
      expect(tutor.headline, TutorScripts.sessionStopped);
      expect(tutor.showStop, isFalse);
      expect(engine.isSessionActive, isFalse);
      expect(engine.uiPhase, AssistUiPhase.intro);
      expect(detectionService.isListening, isFalse);
      expect(engine.isPitchAnalysisEnabled, isFalse);
      expect(referenceSound.playCount, 0);
      expect(referenceSound.isPlaying, isFalse);
      expect(voice.spoken, contains(TutorScripts.firstStepListen));
      expect(voice.spoken, isNot(contains(TutorScripts.firstStepInstruction)));
      expect(voice.spoken, isNot(contains(TutorScripts.countdown.first)));
      final spoken = voice.spoken.length;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(voice.spoken.length, spoken);
      expect(engine.uiPhase, AssistUiPhase.intro);
    },
  );

  test(
    'journey stage follows the existing search without changing it',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      TutorJourneyStage? duringStage1;
      TutorJourneyStage? duringStage2;

      engine = buildEngine(
        wait: phasedWait(
          () => engine,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
              duringStage1 = tutor.journeyStage;
              await emitPitch(detectionService, Pitch.g);
              return;
            }
            if (phase == AssistUiPhase.listening &&
                engine.isExploringRange &&
                engine.currentRangePoint == AssistRangePoint.lowerSa &&
                duringStage2 == null) {
              duringStage2 = tutor.journeyStage;
            }
          },
        ),
      );
      addTearDown(engine.dispose);
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await tutor.begin();

      var markedFirstComfortable = false;
      for (var i = 0; i < 64; i++) {
        if (engine.uiPhase == AssistUiPhase.awaitingLowerAudibility) {
          expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
          await tutor.answerLowerAudibility(true);
        } else if (engine.uiPhase == AssistUiPhase.awaitingPaComfort) {
          await tutor.answerUpperComfort(true);
        } else if (engine.uiPhase == AssistUiPhase.awaitingUpperComfort) {
          if (!markedFirstComfortable) {
            markedFirstComfortable = true;
            await tutor.answerUpperComfort(true);
          } else {
            await tutor.answerUpperComfort(false);
          }
        } else if (engine.uiPhase == AssistUiPhase.completed) {
          break;
        } else {
          await Future<void>.delayed(Duration.zero);
        }
      }

      for (var i = 0; i < 50; i++) {
        if (engine.uiPhase == AssistUiPhase.completed && !engine.isBusy) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      expect(duringStage1, isNull);
      expect(duringStage2, TutorJourneyStage.exploreRange);
      expect(engine.stage1Shruti, Pitch.g);
      expect(engine.lastComfortableShruti, Pitch.g);
      expect(engine.referencePitch, Pitch.g);
      expect(engine.uiPhase, AssistUiPhase.completed);
      expect(tutor.step, TutorStep.complete);
      expect(tutor.journeyStage, TutorJourneyStage.findShruti);
      expect(
        tutor.journeyMark(TutorJourneyStage.listenToVoice),
        TutorJourneyMark.complete,
      );
      expect(
        tutor.journeyMark(TutorJourneyStage.exploreRange),
        TutorJourneyMark.complete,
      );
      expect(
        tutor.journeyMark(TutorJourneyStage.findShruti),
        TutorJourneyMark.current,
      );
    },
  );

  Future<void> pumpUntil(bool Function() ready, {int turns = 30}) async {
    for (var i = 0; i < turns; i++) {
      if (ready()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('first Stage 2 miss uses the existing retry line', () async {
    late final AssistModeController engine;
    var lowerSolos = 0;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        lowerSolos += 1;
        if (lowerSolos == 1) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(
      () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
    );

    expect(voice.spoken, contains(TutorScripts.rangeRetryOnce));
    expect(voice.spoken, isNot(contains(TutorScripts.practiceTogether)));
    expect(voice.spoken, isNot(contains(TutorScripts.makeThisEasier)));
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
  });

  test('repeated Stage 2 misses offer a different sound', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          expect(engine.isPitchAnalysisEnabled, isFalse);
          expect(engine.didMatchCurrentRangeTarget, isFalse);
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
      },
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();
    await pumpUntil(
      () => voice.spoken.contains(TutorScripts.offerDifferentSound),
    );

    expect(voice.spoken, contains(TutorScripts.rangeRetryOnce));
    expect(voice.spoken, contains(TutorScripts.practiceTogether));
    expect(voice.spoken, contains(TutorScripts.singAlongWithMe));
    expect(voice.spoken, contains(TutorScripts.tryOnYourOwn));
    expect(voice.spoken, contains(TutorScripts.makeThisEasier));
    expect(voice.spoken, contains(TutorScripts.offerDifferentSound));
    expect(
      voice.spoken.indexOf(TutorScripts.makeThisEasier),
      greaterThan(voice.spoken.indexOf(TutorScripts.tryOnYourOwn)),
    );
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.last)));
    expect(engine.uiPhase, AssistUiPhase.offeringEasierSound);
    expect(tutor.step, TutorStep.offerDifferentSound);
    expect(tutor.showDifferentSoundChoice, isTrue);
    expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
    expect(tutor.headline, TutorScripts.offerDifferentSound);
    expect(tutor.supportText, 'Say yes or no — or tap below.');
    expect(tutor.canAnswerDifferentSound, isTrue);
  });

  test('yes tries the nearby sound and keeps exploring', () async {
    late final AssistModeController engine;
    var matchNearby = false;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          expect(engine.isPitchAnalysisEnabled, isFalse);
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        if (!matchNearby) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(
      () => voice.spoken.contains(TutorScripts.offerDifferentSound),
    );
    expect(tutor.journeyStage, TutorJourneyStage.exploreRange);

    matchNearby = true;
    await tutor.answerDifferentSound(true);
    await pumpUntil(
      () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
    );

    expect(engine.currentExploreCandidate, Pitch.cSharp);
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
    expect(voice.spoken, isNot(contains("Lovely. Let's try this one.")));
  });

  test('no stays with this sound and practices together again', () async {
    late final AssistModeController engine;
    var matchAfterDecline = false;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          expect(engine.isPitchAnalysisEnabled, isFalse);
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        if (!matchAfterDecline) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(
      () => voice.spoken.contains(TutorScripts.offerDifferentSound),
    );

    matchAfterDecline = true;
    await tutor.answerDifferentSound(false);
    await pumpUntil(
      () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
    );

    expect(voice.spoken, contains(TutorScripts.stayWithThisSound));
    expect(
      voice.spoken.where((line) => line == TutorScripts.practiceTogether),
      hasLength(2),
    );
    expect(engine.currentExploreCandidate, Pitch.c);
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
  });

  test(
    'another struggle after a new sound returns to Stage 1 without welcome',
    () async {
      late final AssistModeController engine;
      TutorJourneyStage? journeyDuringStepBack;
      var resumed = false;
      engine = buildEngine(
        wait: (duration) async {
          if (engine.uiPhase == AssistUiPhase.assistedSinging) {
            return;
          }
          if (engine.uiPhase != AssistUiPhase.listening) {
            return;
          }
          if (!engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
            return;
          }
          if (!resumed) {
            await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
            return;
          }
          final hz = engine.currentRangeTargetHz;
          if (hz != null) {
            await emitHz(detectionService, hz);
          }
        },
      );
      addTearDown(engine.dispose);
      late final TutorSession tutor;
      voice.onSpeak = (text) async {
        if (text != TutorScripts.stepBackToVoice) {
          return;
        }
        journeyDuringStepBack = tutor.journeyStage;
        resumed = true;
        expect(engine.stage, AssistStage.findingStart);
        expect(engine.uiPhase, AssistUiPhase.refreshingStartingNote);
      };
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await tutor.begin();
      await pumpUntil(
        () => voice.spoken.contains(TutorScripts.offerDifferentSound),
      );
      expect(tutor.journeyStage, TutorJourneyStage.exploreRange);

      await tutor.answerDifferentSound(true);
      await pumpUntil(
        () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
        turns: 80,
      );

      expect(journeyDuringStepBack, isNull);
      expect(voice.spoken, contains(TutorScripts.stepBackToVoice));
      expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
      expect(
        voice.spoken.where((line) => line == TutorScripts.welcome.first),
        hasLength(1),
      );
      expect(
        voice.spoken.where((line) => line == TutorScripts.firstStepListen),
        hasLength(1),
      );
      expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
      expect(voice.spoken, isNot(contains(TutorScripts.unresolved.last)));
      expect(engine.uiPhase, isNot(AssistUiPhase.rangeUnresolved));
      expect(engine.isSessionActive, isTrue);
    },
  );

  test('stop during easier-sound recovery cancels immediately', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
      },
    );
    addTearDown(engine.dispose);
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(
      () => voice.spoken.contains(TutorScripts.offerDifferentSound),
    );

    await tutor.stop();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(tutor.step, TutorStep.stopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(detectionService.isListening, isFalse);
    expect(referenceSound.isPlaying, isFalse);
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
  });

  test('spoken yes tries the nearby sound', () async {
    late final AssistModeController engine;
    var matchNearby = false;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        if (!matchNearby) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(
      () => voice.spoken.contains(TutorScripts.offerDifferentSound),
    );

    matchNearby = true;
    await tutor.submitSpokenAnswer('yes');
    await pumpUntil(
      () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
    );

    expect(voice.spoken, isNot(contains("Lovely. Let's try this one.")));
    expect(engine.currentExploreCandidate, Pitch.cSharp);
    expect(tutor.canAnswerDifferentSound, isFalse);
  });

  test('spoken no stays with this sound', () async {
    late final AssistModeController engine;
    var matchAfterDecline = false;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        if (!matchAfterDecline) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(
      () => voice.spoken.contains(TutorScripts.offerDifferentSound),
    );

    matchAfterDecline = true;
    await tutor.submitSpokenAnswer('no');
    await pumpUntil(
      () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
    );

    expect(voice.spoken, contains(TutorScripts.stayWithThisSound));
    expect(
      voice.spoken.where((line) => line == TutorScripts.practiceTogether),
      hasLength(2),
    );
    expect(engine.currentExploreCandidate, Pitch.c);
  });

  test('a second different-sound answer does not move twice', () async {
    late final AssistModeController engine;
    var matchNearby = false;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          return;
        }
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        if (!matchNearby) {
          await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
          return;
        }
        final hz = engine.currentRangeTargetHz;
        if (hz != null) {
          await emitHz(detectionService, hz);
        }
      },
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(() => tutor.canAnswerDifferentSound);

    matchNearby = true;
    final first = tutor.answerDifferentSound(true);
    final second = tutor.answerDifferentSound(true);
    await Future.wait<void>([first, second]);
    await pumpUntil(
      () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
    );

    expect(engine.currentExploreCandidate, Pitch.cSharp);
    expect(tutor.canAnswerDifferentSound, isFalse);
  });

  test(
    'yes still tries the nearby sound without a spoken acknowledgement',
    () async {
      late final AssistModeController engine;
      var matchNearby = false;
      engine = buildEngine(
        wait: (duration) async {
          if (engine.uiPhase == AssistUiPhase.assistedSinging) {
            return;
          }
          if (engine.uiPhase != AssistUiPhase.listening) {
            return;
          }
          if (!engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.c);
            return;
          }
          if (!matchNearby) {
            await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
            return;
          }
          final hz = engine.currentRangeTargetHz;
          if (hz != null) {
            await emitHz(detectionService, hz);
          }
        },
      );
      addTearDown(engine.dispose);
      final tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await engine.startSession();
      await pumpUntil(() => tutor.canAnswerDifferentSound);

      matchNearby = true;
      await tutor.answerDifferentSound(true);
      await pumpUntil(
        () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
      );

      expect(engine.currentExploreCandidate, Pitch.cSharp);
      expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
      expect(voice.spoken, isNot(contains("Lovely. Let's try this one.")));
    },
  );

  test('stop during the different-sound reply does not continue', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase != AssistUiPhase.listening) {
          return;
        }
        if (!engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.c);
          return;
        }
        await emitHz(detectionService, frequencyHzForPitch(Pitch.a));
      },
    );
    addTearDown(engine.dispose);
    voice.onSpeak = (text) async {
      if (text == TutorScripts.stayWithThisSound) {
        await tutor.stop();
      }
    };
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(() => tutor.canAnswerDifferentSound);

    await tutor.answerDifferentSound(false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await tutor.answerDifferentSound(false);

    expect(tutor.step, TutorStep.stopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(engine.currentExploreCandidate, isNot(Pitch.cSharp));
    expect(detectionService.isListening, isFalse);
    expect(referenceSound.isPlaying, isFalse);
  });

  test(
    'completion success dialogue finishes before Shruti sample starts',
    () async {
      late final AssistModeController engine;
      late TutorSession tutor;
      final holdCompletionSpeech = Completer<void>();
      var sawCompletionSpeech = false;
      var playCountDuringSpeech = -1;
      var playingDuringSpeech = true;

      engine = buildEngine(
        wait: phasedWait(
          () => engine,
          onPhase: (phase) async {
            if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
              await emitPitch(detectionService, Pitch.d);
            }
          },
        ),
      );
      addTearDown(engine.dispose);

      voice.onSpeak = (text) async {
        if (text != TutorScripts.completion(engine.referencePitch.label)) {
          return;
        }
        sawCompletionSpeech = true;
        playCountDuringSpeech = audioService.playCount;
        playingDuringSpeech = audioService.isPlaying;
        await holdCompletionSpeech.future;
      };

      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await engine.startSession();

      var markedFirstComfortable = false;
      for (var i = 0; i < 80; i++) {
        if (sawCompletionSpeech) {
          break;
        }
        if (engine.uiPhase == AssistUiPhase.awaitingLowerAudibility) {
          await tutor.answerLowerAudibility(true);
        } else if (engine.uiPhase == AssistUiPhase.awaitingPaComfort) {
          await tutor.answerUpperComfort(true);
        } else if (engine.uiPhase == AssistUiPhase.awaitingUpperComfort) {
          if (!markedFirstComfortable) {
            markedFirstComfortable = true;
            await tutor.answerUpperComfort(true);
          } else {
            await tutor.answerUpperComfort(false);
          }
        } else {
          await Future<void>.delayed(Duration.zero);
        }
      }

      await waitUntil(() => sawCompletionSpeech, attempts: 500);

      expect(engine.uiPhase, AssistUiPhase.completed);
      expect(tutor.step, TutorStep.complete);
      expect(playingDuringSpeech, isFalse);
      expect(playCountDuringSpeech, 0);
      expect(audioService.isPlaying, isFalse);
      expect(audioService.playCount, 0);
      expect(
        voice.spoken,
        contains(TutorScripts.completion(engine.referencePitch.label)),
      );

      holdCompletionSpeech.complete();
      await waitUntil(() => audioService.isPlaying, attempts: 500);

      expect(audioService.isPlaying, isTrue);
      expect(audioService.playCount, greaterThan(0));
      expect(engine.uiPhase, AssistUiPhase.completed);
      expect(engine.referencePitch, Pitch.d);
    },
  );

  test('a successful Stage 2 start does not enter recovery', () async {
    late final AssistModeController engine;
    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            await emitPitch(detectionService, Pitch.g);
          }
        },
      ),
    );
    addTearDown(engine.dispose);
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(
      () => engine.uiPhase == AssistUiPhase.awaitingLowerAudibility,
    );

    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(engine.currentExploreCandidate, Pitch.g);
    expect(voice.spoken, contains(TutorScripts.lowerSoundIntro));
    expect(voice.spoken, isNot(contains(TutorScripts.rangeRetryOnce)));
    expect(voice.spoken, isNot(contains(TutorScripts.practiceTogether)));
    expect(voice.spoken, isNot(contains(TutorScripts.makeThisEasier)));
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
    expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
  });
}
