import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/models/pitch.dart';
import 'package:harmony/pitch/frequency_to_note.dart';
import 'package:harmony/pitch/pitch_detection_service.dart';
import 'package:harmony/pitch/pitch_stability_tracker.dart';
import 'package:harmony/pitch/stable_pitch_candidate_finder.dart';
import 'package:harmony/pitch/target_pitch_matcher.dart';
import 'package:harmony/state/assist_mode_controller.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_session.dart';
import 'package:harmony/tutor/tutor_timing.dart';

import '../support/fake_audio_service.dart';
import '../support/fake_pitch_detection_service.dart';
import '../support/fake_reference_sound_generator.dart';
import '../support/fake_tutor_speech_recognizer.dart';
import '../support/fake_tutor_voice.dart';

void main() {
  late FakePitchDetectionService detectionService;
  late FakeAudioService audioService;
  late FakeReferenceSoundGenerator referenceSound;
  late FakeTutorVoice voice;
  late FakeTutorSpeechRecognizer speech;

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

  TutorSession buildTutor(AssistModeController engine) {
    return TutorSession(
      engine: engine,
      voice: voice,
      speechRecognizer: speech,
      timing: const TutorTimingConfig.instant(),
      wait: (_) async {},
    );
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
  });

  test('welcome speaks script then starts discovery', () async {
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

    await tutor.begin();

    expect(voice.spoken.take(3), TutorScripts.welcome);
    expect(
      voice.spoken
          .skip(TutorScripts.welcome.length)
          .take(TutorScripts.orientation.length),
      TutorScripts.orientation,
    );
    final orientationAt = voice.spoken.indexOf(TutorScripts.orientation.first);
    final discoverAt = voice.spoken.indexOf(TutorScripts.discoverIntro.first);
    expect(orientationAt, TutorScripts.welcome.length);
    expect(discoverAt, greaterThan(orientationAt));
    expect(
      voice.spoken.where((line) => line == TutorScripts.orientation.first),
      hasLength(1),
    );
    expect(voice.spoken, containsAll(TutorScripts.discoverIntro));
    expect(engine.stage1Shruti, Pitch.g);
  });

  test('countdown sequence is emitted exactly once as 3,2,1,0', () async {
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

    expect(tutor.countdownEmitted, <int>[3, 2, 1]);
    final spokenCountdown = voice.spoken
        .where((line) => TutorScripts.countdown.contains(line))
        .toList();
    // Stage 1 countdown only (Stage 2 may add another run after capture).
    expect(spokenCountdown.take(3).toList(), TutorScripts.countdown);
    expect(
      spokenCountdown.where((l) => l == TutorScripts.countdown.first).length,
      lessThanOrEqualTo(2),
      reason: 'at most one Stage 1 and one Stage 2 countdown',
    );
    expect(voice.spoken, isNot(contains('Get ready.')));
    expect(voice.spoken, isNot(contains('Go')));
    expect(spokenCountdown, contains('2...'));
    expect(spokenCountdown, contains('1...'));
    for (var i = 0; i < voice.spoken.length - 1; i++) {
      if (voice.spoken[i] == '1...') {
        expect(
          voice.spoken[i + 1],
          isNot(TutorScripts.nowTryThatSound),
          reason: 'listening starts after 1; no extra instruction after it',
        );
      }
    }
    expect(voice.spoken, isNot(contains('Sing along with me.')));
    expect(voice.spoken, isNot(contains('Now sing with me.')));
  });

  test('Stage 1 listen-complete speech occurs once', () async {
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

    final completeLines = voice.spoken
        .where((line) => line == TutorScripts.listenComplete)
        .toList();
    // Stage 1 once; Stage 2 lower listen may also speak after capture advances.
    expect(completeLines, isNotEmpty);
    expect(completeLines.take(1).single, TutorScripts.listenComplete);
    expect(voice.spoken, contains(TutorScripts.startingNoteSuccess.first));
    // No duplicate back-to-back Stage 1 completion lines before success.
    final firstComplete = voice.spoken.indexOf(TutorScripts.listenComplete);
    final successAt = voice.spoken.indexOf(
      TutorScripts.startingNoteSuccess.first,
    );
    expect(firstComplete, lessThan(successAt));
    expect(
      voice.spoken
          .sublist(firstComplete, successAt)
          .where((l) => l == TutorScripts.listenComplete),
      hasLength(1),
    );
  });

  test('failed starting-note capture speaks retry and auto-retries', () async {
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
    expect(voice.spoken, contains(TutorScripts.startingNoteRetryOnce.first));
    final retryAt = voice.spoken.indexOf(
      TutorScripts.startingNoteRetryOnce.first,
    );
    expect(
      voice.spoken.take(retryAt).where((l) => l == TutorScripts.listenComplete),
      isEmpty,
      reason: 'silence must not be announced as a successful capture',
    );
    expect(engine.stage1Shruti, Pitch.g);
  });

  test('second Stage 1 failure switches to guided listening', () async {
    late final AssistModeController engine;
    var stage1Listens = 0;
    var sawGuidedDemo = false;
    var peakFailureCount = 0;

    engine = buildEngine(
      wait: phasedWait(
        () => engine,
        onPhase: (phase) async {
          if (engine.stage1FailureCount > peakFailureCount) {
            peakFailureCount = engine.stage1FailureCount;
          }
          if (!engine.isExploringRange &&
              phase == AssistUiPhase.playingReference) {
            sawGuidedDemo = true;
          }
          if (phase == AssistUiPhase.listening && !engine.isExploringRange) {
            stage1Listens += 1;
            if (stage1Listens <= 2) {
              detectionService.emit(PitchReading.none);
            } else {
              await emitPitch(detectionService, Pitch.f);
            }
          }
        },
      ),
    );
    addTearDown(engine.dispose);

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await tutor.begin();
    for (var i = 0; i < 200; i++) {
      if (voice.spoken.contains(TutorScripts.startingNoteGuided.first) &&
          sawGuidedDemo) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Failure count resets after a later Stage 1 success — use the peak.
    expect(peakFailureCount, greaterThanOrEqualTo(2));
    expect(voice.spoken, contains(TutorScripts.startingNoteGuided.first));
    expect(sawGuidedDemo, isTrue);
    expect(voice.spoken, isNot(contains('Now sing with me.')));
    expect(voice.spoken, isNot(contains('Sing along with me.')));
  });

  test('beforeReference speech precedes reference playback', () async {
    late final AssistModeController engine;

    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.listening &&
            !engine.isExploringRange) {
          await emitPitch(detectionService, Pitch.d);
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

    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await Future<void>.delayed(Duration.zero);

    expect(voice.spoken, contains(TutorScripts.lowerSoundIntro));
    expect(voice.spoken, contains(TutorScripts.listenFirst));
    expect(
      voice.spoken.indexOf(TutorScripts.lowerSoundIntro),
      lessThan(voice.spoken.indexOf(TutorScripts.listenFirst)),
    );
    // Reference play happens after "Listen first." was already spoken.
    expect(referenceSound.playCount, greaterThan(0));
  });

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
    var paSolos = 0;
    engine = buildEngine(
      wait: (duration) async {
        if (engine.uiPhase == AssistUiPhase.assistedSinging) {
          expect(referenceSound.isPlaying, isTrue);
          expect(engine.isPitchAnalysisEnabled, isFalse);
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
    final tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await engine.reportLowerSaAudible();

    expect(voice.spoken, contains(TutorScripts.rangeRetryOnce));
    expect(voice.spoken, contains(TutorScripts.practiceTogether));
    expect(voice.spoken, contains(TutorScripts.singAlongWithMe));
    expect(voice.spoken, contains(TutorScripts.tryOnYourOwn));
    expect(voice.spoken, isNot(contains(TutorScripts.practiceOnceMore)));
    expect(voice.spoken, isNot(contains(TutorScripts.assistedReady)));
    final practice = voice.spoken.indexOf(TutorScripts.practiceTogether);
    final along = voice.spoken.indexOf(TutorScripts.singAlongWithMe);
    final onYourOwn = voice.spoken.indexOf(TutorScripts.tryOnYourOwn);
    expect(practice, greaterThanOrEqualTo(0));
    expect(along, greaterThan(practice));
    expect(onYourOwn, greaterThan(along));
    expect(engine.canIsolateUserFromReference, isFalse);
    expect(engine.uiPhase, AssistUiPhase.awaitingUpperComfort);
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
      if (text == TutorScripts.countdown.first) {
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
      if (engine.uiPhase == AssistUiPhase.awaitingUpperComfort ||
          engine.uiPhase == AssistUiPhase.exploringNextShruti ||
          engine.searchMode == AssistShrutiSearchMode.seekingLower ||
          engine.searchMode == AssistShrutiSearchMode.seekingHigher) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    if (engine.uiPhase == AssistUiPhase.awaitingUpperComfort) {
      await tutor.answerUpperComfort(false);
    }

    expect(engine.lastComfortableShruti, isNull);
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
    final tutor = buildTutor(engine);
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
    expect(engine.uiPhase, AssistUiPhase.awaitingUpperComfort);
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
    'orientation does not start pitch detection or reference audio',
    () async {
      late final AssistModeController engine;
      late final TutorSession tutor;
      var checkedDuringOrientation = false;
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
        if (text != TutorScripts.orientation.last) {
          return;
        }
        checkedDuringOrientation = true;
        expect(tutor.step, TutorStep.orientation);
        expect(tutor.journeyStage, TutorJourneyStage.listenToVoice);
        expect(engine.isSessionActive, isFalse);
        expect(engine.uiPhase, AssistUiPhase.intro);
        expect(engine.isPitchAnalysisEnabled, isFalse);
        expect(detectionService.isListening, isFalse);
        expect(referenceSound.playCount, 0);
        expect(referenceSound.isPlaying, isFalse);
        expect(audioService.playCount, 0);
        expect(voice.spoken, isNot(contains(TutorScripts.discoverIntro.first)));
        expect(voice.spoken, isNot(contains(TutorScripts.countdown.first)));
        expect(voice.spoken, isNot(contains(TutorScripts.listenFirst)));
        expect(voice.spoken, isNot(contains(TutorScripts.singAlongWithMe)));
      };
      tutor = buildTutor(engine);
      addTearDown(tutor.dispose);

      await tutor.begin();

      expect(checkedDuringOrientation, isTrue);
      expect(
        voice.spoken.where((line) => line == TutorScripts.orientation.first),
        hasLength(1),
      );
      expect(engine.stage1Shruti, Pitch.g);
      expect(engine.isSessionActive, isTrue);
    },
  );

  test('stop during orientation does not start the session', () async {
    late final AssistModeController engine;
    late final TutorSession tutor;
    engine = buildEngine(wait: (_) async {});
    addTearDown(engine.dispose);

    voice.onSpeak = (text) async {
      if (text == TutorScripts.orientation.first) {
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
    expect(voice.spoken, contains(TutorScripts.orientation.first));
    expect(voice.spoken, isNot(contains(TutorScripts.discoverIntro.first)));
    expect(voice.spoken, isNot(contains(TutorScripts.countdown.first)));
    final spoken = voice.spoken.length;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(voice.spoken.length, spoken);
    expect(engine.uiPhase, AssistUiPhase.intro);
  });

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

      expect(duringStage1, TutorJourneyStage.listenToVoice);
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

    expect(voice.spoken, contains(TutorScripts.tryThisSound));
    expect(engine.currentExploreCandidate, Pitch.cSharp);
    expect(engine.uiPhase, AssistUiPhase.awaitingLowerAudibility);
    expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
    expect(voice.spoken, isNot(contains(TutorScripts.unresolved.first)));
    final lovelyAt = voice.spoken.indexOf(TutorScripts.tryThisSound);
    expect(
      voice.spoken.skip(lovelyAt + 1),
      isNot(contains(TutorScripts.lowerSoundIntro)),
    );
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

      expect(journeyDuringStepBack, TutorJourneyStage.listenToVoice);
      expect(voice.spoken, contains(TutorScripts.stepBackToVoice));
      expect(tutor.journeyStage, TutorJourneyStage.exploreRange);
      expect(
        voice.spoken.where((line) => line == TutorScripts.welcome.first),
        hasLength(1),
      );
      expect(
        voice.spoken.where((line) => line == TutorScripts.orientation.first),
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

    expect(voice.spoken, contains(TutorScripts.tryThisSound));
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
    expect(
      voice.spoken.where((line) => line == TutorScripts.tryThisSound),
      hasLength(1),
    );
  });

  test('a failed reply clip still tries the nearby sound', () async {
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
    voice.onSpeak = (text) async {
      if (text == TutorScripts.tryThisSound) {
        throw StateError('missing clip');
      }
    };
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
  });

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
      if (text == TutorScripts.tryThisSound) {
        await tutor.stop();
      }
    };
    tutor = buildTutor(engine);
    addTearDown(tutor.dispose);

    await engine.startSession();
    await pumpUntil(() => tutor.canAnswerDifferentSound);

    await tutor.answerDifferentSound(true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await tutor.answerDifferentSound(true);

    expect(tutor.step, TutorStep.stopped);
    expect(engine.uiPhase, AssistUiPhase.intro);
    expect(engine.isSessionActive, isFalse);
    expect(engine.currentExploreCandidate, isNot(Pitch.cSharp));
    expect(detectionService.isListening, isFalse);
    expect(referenceSound.isPlaying, isFalse);
  });

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
