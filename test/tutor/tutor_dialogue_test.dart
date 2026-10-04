import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:harmony/tutor/tutor_audio_catalog.dart';
import 'package:harmony/tutor/tutor_dialogue.dart';
import 'package:harmony/tutor/tutor_scripts.dart';

void main() {
  group('TutorDialogues', () {
    test('every dialogue id resolves to exactly one text', () {
      final seenIds = <String>{};
      for (final dialogue in TutorDialogues.all) {
        expect(dialogue.id, isNotEmpty);
        expect(dialogue.text.trim(), isNotEmpty);
        expect(
          seenIds.add(dialogue.id),
          isTrue,
          reason: 'duplicate dialogue id ${dialogue.id}',
        );
        expect(TutorDialogues.byId(dialogue.id), same(dialogue));
        expect(TutorDialogues.byId(dialogue.id)!.text, dialogue.text);
      }
    });

    test('every dialogue text resolves to exactly one definition', () {
      final seenTexts = <String>{};
      for (final dialogue in TutorDialogues.all) {
        expect(
          seenTexts.add(dialogue.text),
          isTrue,
          reason: 'duplicate dialogue text for ${dialogue.id}',
        );
        expect(TutorDialogues.byText(dialogue.text), same(dialogue));
      }
    });

    test('audio clip and text belong to the same dialogue definition', () {
      for (final dialogue in TutorDialogues.withBundledRecording) {
        expect(TutorAudioCatalog.assetIdsForSpokenLine(dialogue.text), <String>[
          dialogue.id,
        ]);
        expect(
          TutorAudioCatalog.dialogueForSpokenLine(dialogue.text),
          same(dialogue),
        );
        expect(
          TutorAudioCatalog.assetPath(dialogue.id),
          'assets/audio/tutor/${dialogue.id}.mp3',
        );
        expect(
          File(TutorAudioCatalog.assetPath(dialogue.id)).existsSync(),
          isTrue,
          reason: '${dialogue.id} must be bundled on disk',
        );
      }
    });

    test('S60-S63 stage mappings are correct and not crossed', () {
      expect(TutorDialogues.s60.text, "That's okay. Let's try again.");
      expect(
        TutorDialogues.s61.text,
        "Listen to the sound again, then sing it when you're ready.",
      );
      expect(TutorDialogues.s62.text, 'Take your time. You can do this.');
      expect(
        TutorDialogues.s63.text,
        "Let's take a small step back and listen to your voice once more.",
      );

      expect(TutorScripts.startingNoteGuided, <String>[
        TutorDialogues.s70.text,
        TutorDialogues.s61.text,
      ]);
      expect(TutorDialogues.stage1FailureRecovery.map((d) => d.id), <String>[
        'S70',
        'S61',
      ]);
      expect(
        TutorScripts.startingNoteGuided,
        isNot(contains(TutorDialogues.s60.text)),
      );
      expect(
        TutorScripts.startingNoteGuided,
        isNot(contains(TutorDialogues.s62.text)),
      );
      expect(TutorScripts.stepBackToVoice, TutorDialogues.s63.text);

      for (final dialogue in TutorDialogues.stage1FailureRecovery) {
        expect(TutorAudioCatalog.assetIdsForSpokenLine(dialogue.text), <String>[
          dialogue.id,
        ]);
      }
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.stepBackToVoice),
        <String>['S63'],
      );
    });

    test('Stage 2 opening maps onto unique S72 dialogue and audio', () {
      expect(
        TutorDialogues.s72.text,
        "Now that I understand your voice, let's find your singing range.",
      );
      expect(TutorScripts.startingNoteSuccess, <String>[
        TutorDialogues.s72.text,
      ]);
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.startingNoteSuccess.first,
        ),
        <String>['S72'],
      );
      expect(TutorAudioCatalog.assetPath('S72'), 'assets/audio/tutor/S72.mp3');
      expect(File(TutorAudioCatalog.assetPath('S72')).existsSync(), isTrue);
      expect(
        TutorScripts.startingNoteSuccess.first,
        isNot(TutorDialogues.s11.text),
      );
      for (final id in <String>['S59', 'S60', 'S61', 'S62', 'S63', 'S11']) {
        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(
            TutorScripts.startingNoteSuccess.first,
          ),
          isNot(contains(id)),
        );
      }
    });

    test('Stage 2 lower-sound listen prompt maps onto S74', () {
      expect(
        TutorDialogues.s74.text,
        "I'll play a sound for you now. Listen carefully. "
        "When it finishes, it's your turn to sing it back.",
      );
      expect(TutorScripts.lowerSoundListenPrompt, TutorDialogues.s74.text);
      expect(TutorScripts.listenFirst, TutorDialogues.s15.text);
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.lowerSoundListenPrompt,
        ),
        <String>['S74'],
      );
      expect(TutorAudioCatalog.assetPath('S74'), 'assets/audio/tutor/S74.mp3');
      expect(File(TutorAudioCatalog.assetPath('S74')).existsSync(), isTrue);
    });

    test('Stage 2 first solo countdown maps onto S75 without again', () {
      expect(TutorDialogues.s75.text, "Let's try singing it in 3...");
      expect(TutorScripts.countdownFirst.first, TutorDialogues.s75.text);
      expect(TutorScripts.countdown.first, TutorDialogues.s07.text);
      expect(
        TutorScripts.countdownFirst.first,
        isNot(contains('again')),
      );
      expect(TutorScripts.countdown.first, contains('again'));
      expect(
        TutorAudioCatalog.assetIdsForSpokenLine(
          TutorScripts.countdownFirst.first,
        ),
        <String>['S75'],
      );
      expect(TutorAudioCatalog.assetPath('S75'), 'assets/audio/tutor/S75.mp3');
      expect(File(TutorAudioCatalog.assetPath('S75')).existsSync(), isTrue);
    });

    test(
      'Stage 1 failure uses S70/S61; Stage 2 keeps S70/S71/S73 offer path',
      () {
        expect(TutorScripts.makeThisEasier, TutorDialogues.s70.text);
        expect(TutorScripts.offerDifferentSound, TutorDialogues.s71.text);
        expect(TutorScripts.stayWithThisSound, TutorDialogues.s73.text);

        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(TutorScripts.makeThisEasier),
          <String>['S70'],
        );
        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(
            TutorScripts.offerDifferentSound,
          ),
          <String>['S71'],
        );
        expect(
          TutorAudioCatalog.assetIdsForSpokenLine(
            TutorScripts.stayWithThisSound,
          ),
          <String>['S73'],
        );

        expect(TutorDialogues.stage1FailureRecovery, <TutorDialogue>[
          TutorDialogues.s70,
          TutorDialogues.s61,
        ]);
        expect(
          TutorDialogues.byId('S60')!.text,
          isNot(TutorScripts.offerDifferentSound),
        );
        expect(
          TutorDialogues.byId('S62')!.text,
          isNot(TutorScripts.stayWithThisSound),
        );

        for (final line in TutorScripts.startingNoteGuided) {
          final ids = TutorAudioCatalog.assetIdsForSpokenLine(line);
          expect(ids, hasLength(1));
          expect(ids.single, anyOf('S70', 'S61'));
          expect(ids.single, isNot(anyOf('S60', 'S62', 'S71', 'S73')));
        }
      },
    );

    test('recovery dialogues listed for verification stay synchronized', () {
      const expected = <String, String>{
        'S60': "That's okay. Let's try again.",
        'S61': "Listen to the sound again, then sing it when you're ready.",
        'S62': 'Take your time. You can do this.',
        'S70': "That's okay. Let's make this a little easier.",
        'S71':
            "That sound didn't feel quite right. Would you like to try a different one?",
        'S73': "That's perfectly okay. Let's stay with this one for now.",
        'S63':
            "Let's take a small step back and listen to your voice once more.",
      };

      for (final entry in expected.entries) {
        final dialogue = TutorDialogues.byId(entry.key);
        expect(dialogue, isNotNull, reason: entry.key);
        expect(dialogue!.text, entry.value);
        expect(TutorAudioCatalog.assetIdsForSpokenLine(entry.value), <String>[
          entry.key,
        ]);
        expect(
          TutorAudioCatalog.dialogueForSpokenLine(entry.value)!.id,
          entry.key,
        );
      }
    });

    test('a single dialogue event resolves matching text and audio ids', () {
      for (final dialogue in TutorDialogues.stage1FailureRecovery) {
        expect(dialogue.text, TutorDialogues.byId(dialogue.id)!.text);
        expect(TutorAudioCatalog.assetIdsForSpokenLine(dialogue.text), <String>[
          dialogue.id,
        ]);
        expect(
          TutorAudioCatalog.assetPath(
            dialogue.id,
          ).endsWith('/${dialogue.id}.mp3'),
          isTrue,
        );
      }
      for (final dialogue in TutorDialogues.stage2Recovery) {
        expect(TutorAudioCatalog.assetIdsForSpokenLine(dialogue.text), <String>[
          dialogue.id,
        ]);
      }
    });

    test(
      'spoken script lines do not fall back while a different clip would play',
      () {
        final spokenScriptLines = <String>[
          ...TutorScripts.welcome,
          TutorScripts.firstStepListen,
          TutorScripts.firstStepInstruction,
          TutorScripts.stage1Success,
          TutorScripts.readyForNextStep,
          ...TutorScripts.discoverIntro,
          ...TutorScripts.countdownFirst,
          ...TutorScripts.countdown,
          ...TutorScripts.assistedCountdown,
          TutorScripts.listenComplete,
          ...TutorScripts.startingNoteSuccess,
          TutorScripts.startingNoteRetryOnce[0],
          TutorScripts.startingNoteRetryOnce[1],
          ...TutorScripts.startingNoteGuided,
          TutorScripts.listenFirst,
          TutorScripts.lowerSoundListenPrompt,
          TutorScripts.lowerSoundIntro,
          TutorScripts.middleSoundIntro,
          TutorScripts.upperSoundIntro,
          TutorScripts.exploreHigher,
          TutorScripts.exploreLower,
          TutorScripts.softAffirmation,
          TutorScripts.lowerAudibilityQuestion,
          TutorScripts.upperComfortQuestion,
          TutorScripts.lowerNotClear,
          TutorScripts.upperNotComfortable,
          TutorScripts.rangeRetryOnce,
          TutorScripts.practiceTogether,
          TutorScripts.singAlongWithMe,
          TutorScripts.assistedSingAlongPrompt,
          TutorScripts.tryOnYourOwn,
          TutorScripts.practiceOnceMore,
          TutorScripts.makeThisEasier,
          TutorScripts.offerDifferentSound,
          TutorScripts.stayWithThisSound,
          TutorScripts.stepBackToVoice,
          ...TutorScripts.makeEasier,
          ...TutorScripts.unclearYesNo,
          TutorScripts.unclearComfort[1],
          ...TutorScripts.unresolved,
        ];

        for (final line in spokenScriptLines) {
          final dialogue = TutorAudioCatalog.dialogueForSpokenLine(line);
          expect(dialogue, isNotNull, reason: 'missing dialogue for: $line');
          final ids = TutorAudioCatalog.assetIdsForSpokenLine(line);
          expect(ids, <String>[dialogue!.id], reason: line);
          // Catalog must not return empty (silent fallback) for a spoken line
          // that has a bundled recording.
          expect(ids, isNotEmpty, reason: line);
          expect(dialogue.text, line);
        }
      },
    );
  });
}
