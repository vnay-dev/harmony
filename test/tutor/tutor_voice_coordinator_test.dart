import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/tutor/tutor_answer.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_scripts.dart';
import 'package:harmony/tutor/tutor_timing.dart';
import 'package:harmony/tutor/tutor_voice_coordinator.dart';

import '../support/fake_tutor_voice.dart';

void main() {
  group('TutorVoiceCoordinator', () {
    test('speakOnce emits each event id only once', () async {
      final voice = FakeTutorVoice();
      final coordinator = TutorVoiceCoordinator(
        voice: voice,
        timing: const TutorTimingConfig.instant(),
      );

      expect(await coordinator.speakOnce('a', 'Hello'), isTrue);
      expect(await coordinator.speakOnce('a', 'Hello again'), isFalse);
      expect(await coordinator.speakOnce('b', 'Next'), isTrue);
      expect(await coordinator.speakOnce('a', 'Hello later'), isFalse);

      expect(voice.spoken, <String>['Hello', 'Next']);
    });

    test('never speaks while reference audio is active', () async {
      final voice = FakeTutorVoice();
      final events = <String>[];
      late final TutorVoiceCoordinator coordinator;
      coordinator = TutorVoiceCoordinator(
        voice: voice,
        timing: const TutorTimingConfig.instant(),
        wait: (d) async {
          events.add('wait');
          coordinator.endReferenceAudio();
        },
      );

      await coordinator.beginReferenceAudio();
      await coordinator.speak('After reference');
      expect(voice.spoken, <String>['After reference']);
      expect(events, isNotEmpty);
    });

    test('clears speaking before the configured sentence pause', () async {
      late final TutorVoiceCoordinator coordinator;
      var speakingDuringPause = true;
      coordinator = TutorVoiceCoordinator(
        voice: FakeTutorVoice(),
        timing: const TutorTimingConfig(
          sentencePause: Duration(milliseconds: 25),
        ),
        wait: (_) async {
          speakingDuringPause = coordinator.isSpeaking;
        },
      );

      await coordinator.speak('Hello');
      expect(speakingDuringPause, isFalse);
      expect(coordinator.isSpeaking, isFalse);
    });

    test('sentence pauses use configured timing', () async {
      final voice = FakeTutorVoice();
      final pauses = <Duration>[];
      final coordinator = TutorVoiceCoordinator(
        voice: voice,
        timing: const TutorTimingConfig(
          sentencePause: Duration(milliseconds: 42),
        ),
        wait: (d) async {
          pauses.add(d);
        },
      );

      await coordinator.speak('One');
      expect(pauses, <Duration>[const Duration(milliseconds: 42)]);
    });

    test('speakDialogue binds transcript text and audio id atomically', () async {
      final voice = FakeTutorVoice();
      final coordinator = TutorVoiceCoordinator(
        voice: voice,
        timing: const TutorTimingConfig.instant(),
      );

      await coordinator.speakDialogue(TutorDialogues.s70);
      expect(coordinator.lastLine, TutorDialogues.s70.text);
      expect(coordinator.activeDialogue, same(TutorDialogues.s70));
      expect(voice.playedAssets, <String>['S70']);
      expect(voice.spoken, <String>[TutorDialogues.s70.text]);
      expect(coordinator.playedAssetLog, <String>['S70']);
    });

    test('Stage 1 failure speaks S70 then S61 only', () async {
      final voice = FakeTutorVoice();
      final coordinator = TutorVoiceCoordinator(
        voice: voice,
        timing: const TutorTimingConfig.instant(),
      );

      await coordinator.speakDialogues(TutorDialogues.stage1FailureRecovery);
      expect(voice.playedAssets, <String>['S70', 'S61']);
      expect(voice.playedAssets, isNot(contains('S60')));
      expect(voice.playedAssets, isNot(contains('S62')));
      expect(voice.playedAssets, isNot(contains('S71')));
      expect(voice.playedAssets, isNot(contains('S73')));
      expect(coordinator.lastLine, TutorDialogues.s61.text);
      expect(coordinator.activeDialogue, same(TutorDialogues.s61));
      expect(coordinator.spokenLog, TutorScripts.startingNoteGuided);
    });

    test('obsolete cancel prevents a late dialogue from sticking as active', () async {
      final voice = FakeTutorVoice();
      final coordinator = TutorVoiceCoordinator(
        voice: voice,
        timing: const TutorTimingConfig.instant(),
      );

      voice.onPlayAssets = (ids) async {
        if (ids.length == 1 && ids.first == 'S70') {
          coordinator.cancelSpeech();
        }
      };

      await coordinator.speakDialogue(TutorDialogues.s70);
      expect(coordinator.isSpeaking, isFalse);
      expect(coordinator.activeDialogue, isNull);

      // cancelSpeech blocks further speech until a new session resets keys.
      coordinator.resetEventKeys();
      await coordinator.speakDialogue(TutorDialogues.s61);
      expect(coordinator.activeDialogue, same(TutorDialogues.s61));
      expect(coordinator.lastLine, TutorDialogues.s61.text);
      expect(voice.playedAssets, contains('S61'));
    });

    test('speak(text) resolves through the same dialogue definition as speakDialogue',
        () async {
      final voice = FakeTutorVoice();
      final coordinator = TutorVoiceCoordinator(
        voice: voice,
        timing: const TutorTimingConfig.instant(),
      );

      await coordinator.speak(TutorScripts.makeThisEasier);
      expect(coordinator.activeDialogue, same(TutorDialogues.s70));
      expect(voice.playedAssets, <String>['S70']);
      expect(coordinator.lastLine, TutorDialogues.s70.text);
    });
  });

  group('TutorAnswerParser', () {
    const parser = TutorAnswerParser();

    test('classifies yes variants', () {
      for (final raw in [
        'yes',
        'Yeah',
        'yep',
        'yes I could',
        'yes, I heard it',
        'comfortable',
        'that felt comfortable',
      ]) {
        expect(parser.parseYesNo(raw), TutorYesNoAnswer.yes, reason: raw);
      }
    });

    test('classifies no variants', () {
      for (final raw in [
        'no',
        'nope',
        'not really',
        "I couldn't hear it",
        'not comfortable',
        'that felt uncomfortable',
      ]) {
        expect(parser.parseYesNo(raw), TutorYesNoAnswer.no, reason: raw);
      }
    });

    test('unclear yes/no', () {
      expect(parser.parseYesNo('maybe later'), TutorYesNoAnswer.unclear);
      expect(
        parser.parseYesNo('I noticed something'),
        TutorYesNoAnswer.unclear,
      );
    });

    test('classifies comfortable variants', () {
      for (final raw in [
        'comfortable',
        'that felt comfortable',
        'good',
        'fine',
        'easy',
        'feels good',
        'yes',
      ]) {
        expect(
          parser.parseComfort(raw),
          TutorComfortAnswer.comfortable,
          reason: raw,
        );
      }
    });

    test('classifies not comfortable variants', () {
      for (final raw in [
        'uncomfortable',
        'not comfortable',
        'strained',
        'difficult',
        'too high',
        'too much',
        'no',
      ]) {
        expect(
          parser.parseComfort(raw),
          TutorComfortAnswer.notComfortable,
          reason: raw,
        );
      }
    });
  });

  group('TutorScripts honesty', () {
    test('does not claim sing with me or sing along', () {
      final lines = <String>[
        ...TutorScripts.welcome,
        ...TutorScripts.orientation,
        ...TutorScripts.discoverIntro,
        ...TutorScripts.countdown,
        TutorScripts.listenComplete,
        ...TutorScripts.startingNoteSuccess,
        ...TutorScripts.startingNoteRetryOnce,
        ...TutorScripts.startingNoteGuided,
        TutorScripts.listenFirst,
        TutorScripts.listenOnceMore,
        TutorScripts.rangeRetryOnce,
        TutorScripts.practiceTogether,
        TutorScripts.letMeHelpYou,
        ...TutorScripts.letMeHelp,
        ...TutorScripts.makeEasier,
        ...TutorScripts.unclearYesNo,
        ...TutorScripts.unclearComfort,
      ];
      for (final line in lines) {
        if (line == TutorScripts.singAlongWithMe) {
          continue;
        }
        final lower = line.toLowerCase();
        expect(lower, isNot(contains('with me')), reason: line);
        expect(lower, isNot(contains('sing along')), reason: line);
      }
      expect(
        TutorScripts.singAlongWithMe.toLowerCase(),
        contains('sing along'),
      );
      expect(TutorScripts.listenComplete, isNot(contains("That's enough")));
    });
  });
}
